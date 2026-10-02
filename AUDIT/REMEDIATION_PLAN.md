# Remediation Plan

Phased per the brief. Each item gives the finding ID, the problem, the proposed change, affected files, the risk of making the change, dependencies, and how to validate it.

**Nothing in this plan has been applied.** No source file was modified during the audit.

---

## PHASE 0 — Immediate security / production risk

### R0.1 — Rotate every exposed credential  *(SEC-002, SEC-004, SEC-005, DOC-001)*
**Problem:** a JWT signing key is public on GitHub; `elastic123`/`kibana123` are published in configs, scripts and ~18 docs; the working-tree `.env` holds a live Gmail app password, a Slack webhook and an OTX API key which are baked into the backend image.
**Change:** rotate — the k8s `SECRET_KEY`, the Gmail app password, the Slack webhook, the OTX API key, `KIBANA_SYSTEM_PASSWORD`, and all Elasticsearch/Kibana passwords. Move them to a secret manager.
**Files:** `k8s/base/configmap.yaml`, `.env`, `docker-compose.yml`, beats/logstash configs, `scripts/*.sh`.
**Risk of the fix:** low technically; requires coordinated restart. **Risk of not doing it: these credentials must be assumed compromised.**
**Dependencies:** none — do this first.
**Validation:** old credentials rejected; `gitleaks detect` clean after history purge.
> **This is the only item that cannot be deferred.** Removing a secret from a file does not undo its publication.

### R0.2 — Authenticate the security router  *(SEC-001)*
**Change:** add `dependencies=[Depends(get_current_active_user)]` to the router include at `app/main.py:47`. Gate `/simulate/*` behind both an explicit role and `settings.environment != "production"`, or move them to `scripts/`. Bound `LateralMovementSimulation.hosts`.
**Files:** `app/main.py:47`, `app/api/security.py`.
**Risk:** low. No frontend code calls these endpoints (verified), so nothing in the product breaks. Any external consumer relying on anonymous access would break — intentionally.
**Validation:** re-run the audit probe — all 14 endpoints must return 403 without a token and 200 with one.

### R0.3 — Fix the Elasticsearch credential split and stop failing open  *(FUNC-001)*
**Change:** give `ThreatDetectionService` the same `basic_auth` as `SecurityLogger` — preferably one shared client factory in `app/services/`. Separately, stop returning `[]` on exception: re-raise or return an explicit `{"status":"degraded","error":...}` with HTTP 503.
**Files:** `app/services/threat_detection.py:11` + the 8 handlers; `app/services/alerting.py:74`; new shared factory.
**Risk:** **medium — this changes observable behaviour.** Endpoints that currently always return 200 will start returning 503 when ES is unreachable. That is the point, but any dashboard or monitor treating 200 as success needs updating.
**Dependencies:** R0.1 (use the rotated credentials).
**Validation:** repeat the audit experiment — point the app at a security-enabled ES and confirm detectors return real results, and that an auth failure surfaces as 503 rather than an empty list.

### R0.4 — Fix OTP generation and add rate limiting  *(SEC-003, SEC-011)*
**Change:**
1. `email_service.py:16` → `secrets.choice`; lengthen the OTP or use an alphanumeric token.
2. Add a per-account attempt counter with lockout on `/reset-password`.
3. Invalidate outstanding OTPs when a new one is issued.
4. Throttle `/forgot-password` per account and per IP.
5. Apply the existing `auth_limit` zone in `nginx/nginx.conf` to the auth endpoints.
6. Store a hash of the OTP rather than the cleartext.
**Files:** `app/services/email_service.py`, `app/api/users.py`, `app/models/password_reset.py` (+ a migration), `nginx/nginx.conf:92`.
**Risk:** medium — hashing the OTP requires a schema migration; lockout can be abused for denial of service against a known account, so scope the lockout to the attempting IP where possible.
**Validation:** replay the audit's 60-guess loop and confirm lockout/429; confirm only one OTP is valid at a time.

### R0.5 — Make the documented setup work  *(OPS-001)*
**Change:** delete `docker-compose.yml:284-285` and merge `logstash` into the `depends_on` block at `:266`.
**Risk:** very low — a two-line deletion.
**Validation:** `docker compose config` exits 0; `docker compose up -d` starts the stack.
> Add `docker compose config` to CI so this class of error cannot recur.

### R0.6 — Stop baking secrets into the image; drop root  *(SEC-005)*
**Change:** add `.env`, `*.pem`, `test.db`, `AUDIT/` to `.dockerignore`; add a non-root `USER`; split the build so `gcc` is not in the final layer.
**Files:** `.dockerignore`, `Dockerfile`.
**Risk:** low — a non-root user may require adjusting file ownership for any write paths.
**Validation:** `docker history` / `docker run --rm <img> ls -la /app/.env` must fail; `whoami` must not be root.

---

## PHASE 1 — High-impact correctness

### R1.1 — `/health` must report failure  *(OPS-002)*
Return 503 when a dependency is down; wrap `engine.connect()` in a context manager.
**Risk:** **medium — deployment-affecting.** Once `/health` can fail, Kubernetes will begin restarting genuinely unhealthy pods. Verify dependencies are actually healthy before shipping, or a correct fix will look like an outage.
**Validation:** stop Redis → `/health` returns 503; confirm pool size is stable across 1,000 probes.

### R1.2 — Fix alerting  *(ALERT-001)*
Read `SLACK_WEBHOOK_URL` from `app/config.py`; fail loudly when unset; implement or delete `send_email_alert`; use `.get()` for `threat_type`.
**Dependencies:** R0.1 (rotated webhook). **Note:** this also makes the `requests` CVEs genuinely reachable — pair with R2.1.
**Validation:** a test threat produces a real Slack message.

### R1.3 — Invalidate the stats cache  *(BUG-001)*
Delete `stats:user:{id}` in the create/update/delete paths (`app/api/todos.py:57,97-98,114-115`).
**Risk:** very low. **Validation:** the audit's reproduction — create a todo, confirm `total_todos` increments immediately.

### R1.4 — Close the user-enumeration oracle  *(SEC-007)*
Return an identical 200 body on every `/forgot-password` path; queue mail asynchronously; log failures server-side only. Add a dummy-hash comparison in `authenticate_user` for SEC-013.
**Validation:** existing and unknown emails return byte-identical responses; timing difference within noise.

### R1.5 — Invalidate sessions on password change  *(SEC-012)*
Add a `password_changed_at` or token-version claim and reject older tokens; add a logout endpoint.
**Risk:** medium — all existing tokens are invalidated on deploy; users must log in again.
**Validation:** the audit's reproduction — a pre-change token must return 401.

### R1.6 — Upgrade reachable-CVE dependencies  *(DEP-001, DEP-002)*
`python-multipart`, `starlette`, `fastapi`, `python-jose`, `next`.
**Risk:** medium — FastAPI/Starlette majors change middleware and `on_event` behaviour; `elasticsearch` 8.x later clients remove the `body=` kwarg used at 7 sites in `threat_detection.py`. Upgrade incrementally.
**Dependencies:** needs a test suite worth trusting — pair with R3.1.

### R1.7 — Stop leaking rejected input  *(SEC-015)*
Strip `input`/`ctx` from both the logged and returned validation payloads (`app/exceptions.py:71-80`); add a redaction processor to structlog.
**Risk:** low — slightly less helpful client errors.

---

## PHASE 2 — Architectural and deployment

### R2.1 — Make outbound I/O non-blocking  *(P1)*
`redis.asyncio`, `AsyncElasticsearch`, `httpx.AsyncClient`; move SMTP to a background queue; set explicit timeouts everywhere (SMTP currently has none).
**Risk:** **high — this is the largest change in the plan.** It touches every service module and changes concurrency behaviour.
**Dependencies:** requires R3.1 first. Do not attempt this without tests.

### R2.2 — Introduce a client seam  *(A4)*
Replace import-time singletons (`cache.py:59`, `security_logger.py:410`, `threat_detection.py`, `config.py:38`) with FastAPI dependencies or a lifespan-managed container.
**Why it matters:** this is the precondition for testing `app/services/` at all, and for R2.1.

### R2.3 — Secure the deployment surface  *(CFG-001, SEC-010, SEC-008, K8S-001, K8S-002)*
Bind all non-nginx ports to `127.0.0.1`; set a Redis password; terminate TLS and redirect 80→443; enable xpack in the k8s manifests; replace the Logstash `hostPath` with a ConfigMap; add securityContexts, NetworkPolicies and real StorageClasses; remove `--reload` and the source bind-mount from the app service.
**Risk:** medium-high — changes network reachability; stage carefully.

### R2.4 — Reduce Packetbeat capture  *(SEC-009)*
`send_request: false`, `send_response: false`; exclude the application's own ports; enable TLS and auth on the Logstash output.
**Risk:** low functionally; reduces captured detail by design.

### R2.5 — Fix cache and query efficiency  *(P2, P3, P6)*
`SCAN` instead of `KEYS`; hash the `search` component of cache keys; add the `password_reset_tokens.user_id` index and a `(owner_id, created_at)` composite; call `cleanup_expired_tokens` from a scheduled job.

### R2.6 — Unify compose and Kubernetes  *(A5)*
Reconcile xpack posture, token lifetime, and the reverse proxy so the two describe one system.

---

## PHASE 3 — Testing and documentation

### R3.1 — Build a test suite worth trusting  *(TEST_AUDIT)*
Priorities: an authorization matrix over **every** route; the full password-reset flow; cross-tenant writes; JWT edge cases; `/health` failure; cache invalidation; detector behaviour under ES failure; a migration test against Postgres.
Also: fix `pytest.ini` to `[pytest]`; add a test env fixture so the suite runs on a clean checkout; move the SQLite file to `tmp_path`.
**Why it is Phase 3 and not later:** R1.6 and R2.1 are unsafe without it. Consider pulling R3.1 forward ahead of those items.

### R3.2 — Add CI
Run pytest, ruff, mypy, `pip-audit`, `npm audit`, `docker compose config`, and `tsc --noEmit` on every PR. There is currently **no CI at all**, which is how a non-parsing compose file reached `master`.

### R3.3 — Reconcile the documentation  *(DOCUMENTATION_AUDIT, DOCUMENTATION_GAPS)*
Correct the 20 catalogued discrepancies; document the 19 gaps; fix `mkdocs.yaml:121`; add the 15 orphaned docs to the nav; add a real `SECURITY.md` disclosure policy and a `LICENSE`.
**Requires a human decision:** the six status-report documents (D18) and their unsubstantiated metrics (D13). Either substantiate the claims with real measurements or delete them. **They should not be quietly rewritten** — they currently assert capabilities the system does not have, and that gap is itself the finding.

### R3.4 — Fix the frontend toolchain  *(QA-002, DEP-003, CONTRACT-001)*
Resolve the `vaul`/React-19 conflict; restore `npm ci`; pin the four `latest` dependencies; remove `ignoreBuildErrors`/`ignoreDuringBuilds` and fix the 13 TS errors; enable `strict`; correct `Todo.id` to `number`; add `eslint` as a dependency.

---

## PHASE 4 — Lower-priority technical debt

- Delete dead code (QA-003): `cleanup_expired_tokens` (or wire it up), `log_api_access_event`, `send_email_alert`, the unreachable `ConsoleRenderer` branch, unused schemas and the five unraised exception classes; remove 14 unused imports.
- **Add `bcrypt` as an explicit dependency *before* removing the unused `passlib`** — the reverse order breaks password hashing.
- Replace `@app.on_event` with lifespan; migrate pydantic v1 `from_orm`/`.dict()` to v2 (removes 581 warnings per test run).
- Label Prometheus metrics by route template (P9); authenticate `/metrics`.
- Add a `size` to `hunt_privilege_escalation_ecs` (P10).
- Make detection thresholds and risk scores configurable rather than magic numbers.
- `git rm --cached test.db` (QA-004).
- Align `.python-version`, the Dockerfile base image and CI on one Python version.
- Add `pool_pre_ping` and explicit pool sizing (P5); add `rollback()` to `get_db`.
- Resolve the CORS conflict in exactly one layer (CORS-001).
- Add ILM/retention policies for the 13 index patterns (G9).

---

## Suggested sequencing

```
R0.1 (rotate) ──► R0.2, R0.3, R0.4, R0.5, R0.6        [week 1]
                      │
R1.1 … R1.5, R1.7 ◄───┘                                [week 2]
                      │
R3.1 (tests) + R3.2 (CI) ◄─── pull forward              [weeks 2-3]
                      │
R1.6 (dep upgrades), R2.1 (async), R2.2 (seams)        [weeks 3-5]
                      │
R2.3 … R2.6, R3.3, R3.4                                 [weeks 5-8]
                      │
Phase 4                                                 [ongoing]
```

The ordering constraint that matters most: **R3.1 should precede R1.6 and R2.1.** Upgrading a web framework and converting the entire I/O layer to async against 18 tests covering half the codebase is how correct-looking changes become outages.
