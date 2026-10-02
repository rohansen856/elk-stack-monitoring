# Architecture Audit

## Reconstructed architecture (from code, not docs)

```
Browser
  │
  ▼  http://host/  → 301 → /frontend
nginx :80  (nginx/nginx.conf)                      [no TLS]
  ├─ /frontend  → Next.js :3000  (basePath /frontend)
  ├─ /api/      → Next.js :3000/frontend/api/
  ├─ /backend/  → FastAPI :8000  (limit_req api_limit)
  ├─ /monitoring→ Kibana :5601   (no auth gate at proxy)
  └─ /nginx-health → 200

Next.js (website/)
  app/*/page.tsx ──fetch──► app/api/**/route.ts   (BFF, server-side)
                                   │  BACKEND_URL=http://nginx/backend/api/v1
                                   ▼
FastAPI (app/main.py, root_path="/backend")
  ├─ /api/v1/users   → users.py  → crud/user.py   → Postgres
  ├─ /api/v1/todos   → todos.py  → crud/todo.py   → Postgres
  │                              └→ cache.py      → Redis
  └─ /api/v1/security→ security.py                       [NO AUTH]
        ├─ threat_detection.py ──► Elasticsearch  (NO credentials)
        ├─ security_logger.py  ──► Elasticsearch  (basic_auth)
        └─ alerting.py         ──► Slack webhook  (placeholder URL)

Telemetry: Filebeat/Metricbeat/Packetbeat/Winlogbeat ──► Logstash :5044/:5000/:514/:12201 ──► Elasticsearch ──► Kibana
App logs: structlog → root logger → TCPLogstashHandler :5000 (plaintext)
```

## Request flow traced end to end — login

1. `components/auth/login-form.tsx` → `lib/store/auth-store.ts:33` → `POST /api/auth/login` (same-origin).
2. `website/app/api/auth/login/route.ts:16` → `POST ${BACKEND_URL}/users/login` as `x-www-form-urlencoded`, mapping `email` → the `username` field.
3. nginx `/backend/` → FastAPI `app/api/users.py:41`.
4. `authenticate_user` (`crud/user.py:43`) → bcrypt verify.
5. `security_logger.log_authentication_event` → Elasticsearch `security-auth-logs-*` (**blocking**, inside an async handler).
6. `create_access_token` (`auth.py:15`) → HS256 JWT, `sub`=email, 30 min.
7. Response → route handler → token written to a **non-httpOnly** cookie by client JS (`lib/auth-cookies.ts:61`).
8. Subsequent calls send `Authorization: Bearer` (`lib/api-client.ts:17-19`).

The frontend↔backend contract is otherwise consistent: all 10 endpoints the frontend calls exist on the backend with matching methods and paths, and the trailing-slash convention is handled correctly.

## Architectural findings

### A1 — The "security platform" is architecturally vestigial
The `security` router is not integrated with the rest of the application: it has no authentication, no frontend caller, no tests, and its detection half cannot authenticate to Elasticsearch. The todo CRUD app and the security surface share only a process. The project's identity (name, README, 32 docs) describes the security surface; the working, tested code is the to-do app.

### A2 — Two Elasticsearch clients with divergent configuration
`security_logger.py:14-16` authenticates; `threat_detection.py:11` does not; `alerting.py:74` reaches into `threat_detector.es` (cross-module private access) and inherits the unauthenticated one. There is no shared client factory, so the write path works and the read path is broken (FUNC-001). `config.py:15` declares `elasticsearch_url` which **no client uses** — both build URLs from host/port instead.

### A3 — Blocking I/O in an async framework
Every outbound integration uses a synchronous client inside `async def`: Redis (`cache.py`), Elasticsearch (`security_logger.py`, `threat_detection.py`), HTTP (`alerting.py:35`), SMTP (`email_service.py:32`). The application is effectively single-threaded under load. This is a design-level issue, not a local one.

### A4 — Module-level side effects defeat testability and fail-fast
`config.py:38`, `cache.py:59`, `security_logger.py:410` and `threat_detection.py` instantiate singletons at **import time**, and `main.py:29` opens a Logstash socket. Consequences: the test suite cannot import the app without a fully populated `.env` (verified — 9 missing-field errors on a clean environment); there is no dependency-injection seam for the ES/Redis/SMTP clients, which is why `app/services/` has 0% test coverage.

### A5 — Compose and Kubernetes have diverged into different systems
| Aspect | docker-compose | Kubernetes |
|---|---|---|
| ES/Kibana security | **enabled** | **disabled** |
| Token lifetime | 30 min | **30 days** |
| Logstash pipeline | bind mount `./logstash/pipeline` | `hostPath` to a developer's absolute path |
| Ingress | nginx container | `ingress.yaml` **excluded** from kustomization |
| Backend command | `uvicorn --reload` (dev server in the "prod" image) | plain `uvicorn` |
| nginx | present | **absent** — no reverse proxy at all |
Neither is a faithful representation of the other, and the documentation describes a third thing.

### A6 — Layering violations and duplication
- `app/api/security.py` calls services directly with no CRUD/service seam, unlike the todos path.
- `docker-compose.packetbeat.yml` duplicates the inline `packetbeat` service in `docker-compose.yml:254-290` byte-for-byte; it is untracked, so the two will drift.
- `security_logger.py` repeats the same index/try/except block six times (409 LOC).
- `app/exceptions.py` defines a full exception hierarchy that no code raises; endpoints throw bare `HTTPException` instead.

### A7 — Dead and unreachable components
`cleanup_expired_tokens`, `log_api_access_event`, `send_email_alert`, the `ConsoleRenderer` branch, `UserLogin`, `PasswordResetTokenBase`, the custom exception classes, and the nginx `auth_limit`/`general_limit` zones. See QA-003.

### A8 — The `/simulate/*` endpoints are test fixtures shipped as production API
Four endpoints exist solely to inject fake telemetry for demos. They are mounted on the production router, unauthenticated, with no environment gate. They belong behind a flag or in `scripts/`.

## What the architecture gets right

- Clean CRUD layering for todos: router → crud → model, with ownership enforced in the data layer rather than the handler.
- A genuine BFF pattern — the backend URL is server-side only and never reaches the browser bundle.
- Alembic is wired correctly (`env.py:24` overrides the ini URL from settings) and a dedicated `migrate` service runs it before the app.
- Structured JSON logging with request-id propagation (`middleware.py:17,43`).
- Prometheus metrics middleware is present and functional.
- Cache keys are correctly user-scoped, so no cross-tenant cache leakage is possible.
