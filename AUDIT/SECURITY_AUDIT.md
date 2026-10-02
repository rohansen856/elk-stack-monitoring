# Security Audit

Scope: authentication, authorization, input/output handling, secrets, cryptography, API security, infrastructure, dependencies, logging. Findings are indexed in `FINDINGS.md`; this document gives the analysis and attack paths.

## Trust boundaries (as actually implemented)

```
Internet
  └─ nginx :80  (HTTP ONLY — no TLS anywhere)         <- boundary 1
       ├─ /frontend  -> Next.js :3000
       │     └─ BFF route handlers (server-side)      <- boundary 2
       │           └─ FastAPI /api/v1/*
       ├─ /backend/  -> FastAPI :8000  (api_limit 10r/s)
       └─ /monitoring-> Kibana :5601   (NO nginx auth gate)
docker-compose ALSO publishes 8000, 5432, 6379, 9200, 5601 on 0.0.0.0
  => boundary 1 is bypassable entirely
```

The reverse proxy is **not** a security boundary in the shipped compose file: the backend, Postgres, Redis, Elasticsearch and Kibana are all published directly to the host (CFG-001).

## Authentication

| Property | Implementation | Assessment |
|---|---|---|
| Hashing | raw `bcrypt`, `gensalt()` cost 12 (`crud/user.py:14-19`) | **Sound.** 72-byte truncation applied consistently on hash and verify |
| Token | JWT HS256, claims **only** `sub` + `exp` (`auth.py:15-23`) | No `jti`, `iat`, `nbf`, `iss`, `aud`, no token type |
| Secret | required, no default (`config.py:8`) | Good — **but committed for k8s** (SEC-002) |
| Algorithm | `algorithms=[settings.algorithm]` (`auth.py:36`) | **Sound** — no alg-confusion |
| Expiry | 30 min (`.env`), **30 days** (`k8s configmap:11`) | Inconsistent; k8s value is dangerous |
| Refresh / logout / revocation | **none** | SEC-012 |
| Email verification | **none** — `is_active` defaults True | Accounts usable immediately |
| Password policy | **none** — `password: str` unconstrained (`schemas/user.py:12`) | One-character passwords accepted |

`HTTPBearer(auto_error=True)` returns **403** for a missing header rather than 401 (asserted in `tests/test_todos.py:131`), and `get_current_active_user` returns **400** for an inactive user — both non-standard.

## Authorization

Two very different pictures:

- **`todos` router — correct.** Every CRUD path filters by `owner_id` (`crud/todo.py:9,29-32,43-44,57-58`), and `owner_id` is taken from the token, never the request body, so mass assignment is not possible. Verified at runtime: cross-user GET/PUT/DELETE all 404. **No IDOR.**
- **`security` router — absent.** No authorization of any kind on 14 endpoints (SEC-001).

There is no role model at all — no RBAC, no admin concept. Every authenticated user is equivalent.

## Input / output handling

| Class | Status |
|---|---|
| SQL injection | **Not present.** All access via SQLAlchemy ORM with bound parameters; `ilike` search is parameterised (`crud/todo.py:21-22`) |
| ES query injection | **Not present** in the detectors — queries are static dicts; no user input is interpolated into query DSL |
| Command injection | No `subprocess`/`os.system` in `app/` |
| Path traversal | No file-serving endpoints |
| SSRF | `alerting.py:35` posts to a hardcoded URL; no user-controlled fetch |
| XSS (API) | JSON responses; FastAPI escapes correctly |
| HTML injection | **Present** — `user.username` interpolated unescaped into outbound reset email (`email_service.py:68`), username unvalidated |
| Log injection | **Present** — `/simulate/*` write attacker-controlled strings into the SIEM (SEC-001) |
| Mass assignment | Not present — `owner_id` is server-assigned |
| Excessive data exposure | **Present** — validation errors echo rejected input (SEC-015); `/metrics` public (SEC-014) |
| CSRF | Token is in a **non-httpOnly cookie read by JS** and sent as an `Authorization` header, so classic cookie-CSRF does not apply; but `SameSite=Lax` + JS-readable storage means XSS is the dominant risk (SEC-006) |

## Secrets

Three distinct exposure classes, with different urgency:

1. **Publicly committed** (worst — assume compromised): `k8s/base/configmap.yaml` JWT signing key and passwords (SEC-002); Kibana `encryptedSavedObjects`/`reporting`/`security` encryption keys in `docker-compose.yml:91-93`, `k8s/base/kibana.yaml:13-15` and `docs/KIBANA.md:78-80`; `elastic123`/`kibana123` across configs, scripts and ~18 docs (SEC-004).
2. **On disk, correctly gitignored, but baked into images** (SEC-005): the working-tree `.env` holds a live-format Slack webhook, a Gmail app password, an OTX API key, `SECRET_KEY` and `KIBANA_SYSTEM_PASSWORD`; `.dockerignore` omits `.env` and `*.pem`, so `COPY . .` embeds them plus `sentinel.pem`.
3. **Printed to terminals/logs**: `scripts/aws-ec2-setup.sh:181-182` echoes credentials; `docs/SECURITY_CREDENTIALS.md:18-19` publishes a generated kibana_system password.

Verified clean: no secret was ever committed in the root `.env` or `sentinel.pem`; no secret reaches the client JS bundle (the only `NEXT_PUBLIC_*` var is unused).

## Cryptography

- **bcrypt** — correct.
- **HS256 JWT** — acceptable for a single-service deployment; algorithm pinned.
- **`random` for password-reset OTPs** — incorrect and the basis of SEC-003.
- **TLS** — absent everywhere (SEC-010): nginx HTTP-only, ES/Kibana `ssl.enabled=false`, Logstash inputs unencrypted, beats outputs unencrypted, SMTP `starttls()` without certificate verification (SEC-016).
- **Kibana encryption keys** are committed, and the values contain non-hex characters (`g`,`h`,…) despite being presented as hex keys — they appear fabricated, which means saved-object encryption is both publicly known and possibly misconfigured.

## API security

- Rate limiting: none in the app; nginx applies only `api_limit`, and `auth_limit` is dead config (SEC-011).
- Expensive unauthenticated operations: `/threats/scan`, `/hunt/comprehensive` (SEC-001).
- Unbounded input: `simulate/lateral-movement` `hosts: List[str]`; `title` has no length cap in the schema while the column is `String(255)` (`models/todo.py:11`) → a >255-char title raises a DB error surfaced as a 500.
- Pagination is bounded (`skip>=0`, `limit 1..1000`) — correct.
- `/docs` and `/redoc` are disabled only when `ENVIRONMENT == "production"`, and the default is `development` (`config.py:11`).

## Logging and monitoring

The logging pipeline is itself a data-exposure channel:

- The Logstash handler is attached to the **root logger** (`logging_config.py:23-29`), so every library record (SQLAlchemy, uvicorn, urllib3) is shipped — over **plaintext TCP, unauthenticated**.
- Emails are logged on registration, login, reset request and reset completion (`users.py:36,75,98,104,126`) and indexed into `security-auth-logs-*`.
- Full request URLs including query strings are logged (`middleware.py:26,38`).
- SQLAlchemy exception text is logged verbatim (`exceptions.py:85`); for an `IntegrityError` on the globally-unique OTP column this can include the OTP itself.
- Validation `input` values are logged (SEC-015).
- No redaction processor exists.

Conversely, genuine security events are **under**-logged: there is no audit trail for password changes, no alerting on repeated failures (and alerts do not work at all — ALERT-001), and `log_api_access_event` is dead code.

`middleware.py:27` dereferences `request.client.host` without a `None` guard (unlike `users.py:43`), which will raise inside middleware on transports where `client` is `None`.

## Infrastructure

Covered in detail in `CONFIGURATION_AUDIT.md`. Headlines: no TLS (SEC-010); 13 ports on `0.0.0.0` incl. password-less Redis (CFG-001); backend image runs as **root** with `gcc` retained (SEC-005); k8s runs privileged/root containers with host networking and cluster-wide RBAC (K8S-002); ES/Kibana security disabled in k8s (SEC-008).

## Attack paths worth highlighting

**Path A — anonymous SIEM poisoning (no credentials needed).**
`POST /api/v1/security/simulate/*` → forged events indexed → `/threats/*` reads them back → risk_score ≥ 7 → `BackgroundTasks` fires Slack + ES alerts. An attacker controls the content of the defenders' own alert stream. (In the shipped configuration the Slack leg is dead (ALERT-001) and the read-back leg is broken (FUNC-001) — so today this mostly corrupts stored evidence rather than generating alerts. Fixing those two defects without fixing SEC-001 would make this fully live.)

**Path B — account takeover.**
`POST /forgot-password` ×N (no throttle) → N simultaneously valid 6-digit OTPs → brute force `/reset-password` at ~67 req/s with no lockout → exhaust 10^6 within the 15-minute window → set a new password. Existing tokens for the victim remain valid regardless (SEC-012).

**Path C — total auth bypass on Kubernetes.**
Read `SECRET_KEY` from the public repository → forge `{"sub":"<any email>"}` with HS256 → 30-day validity per `configmap.yaml:11`. No revocation mechanism exists.
