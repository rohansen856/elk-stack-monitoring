# Findings Register

Severity: CRITICAL / HIGH / MEDIUM / LOW / INFO
Confidence: CONFIRMED (reproduced at runtime) / HIGH / MEDIUM / LOW

---

## CRITICAL

### SEC-001 — Entire `/api/v1/security/*` router is unauthenticated (14 endpoints)
**Category:** Authorization · **Confidence:** CONFIRMED
**Component:** backend / security API
**Locations:** `app/api/security.py:38,62,68,74,80,86,92,98,104,110,132,155,180,202`; mounted `app/main.py:47`

**Evidence.** No `Depends(...)` appears anywhere in `app/api/security.py`. Measured against a live instance with no `Authorization` header:
```
GET  /api/v1/security/threats/scan            -> 200
GET  /api/v1/security/threats/brute-force     -> 200
GET  /api/v1/security/threats/data-exfiltration -> 200
GET  /api/v1/security/threats/powershell      -> 200
GET  /api/v1/security/threats/apt-correlation -> 200
GET  /api/v1/security/hunt/powershell-external  -> 200
GET  /api/v1/security/hunt/apt-kill-chain     -> 200
GET  /api/v1/security/hunt/lateral-movement   -> 200
GET  /api/v1/security/hunt/privilege-escalation -> 200
GET  /api/v1/security/hunt/comprehensive      -> 200
--- control, same client, same run ---
GET  /api/v1/todos/                           -> 403
GET  /api/v1/users/me                         -> 403
```
The 403s prove the gap is specific to this router, not a harness artifact.

Unauthenticated **write** proven:
```
POST /api/v1/security/simulate/powershell
{"command":"AUDIT-PROOF-forged-event","user":"DOMAIN\\Administrator",
 "host":"dc01.corp.local","process_id":1337,"source_ip":"203.0.113.9"}
-> 200 {"status":"success","message":"PowerShell event logged for detection testing", ...}
```

**Impact.**
- *Confidentiality:* 10 GET endpoints return raw SIEM telemetry — source IPs, usernames, hostnames and `command_line` values (`threat_detection.py:394`) — to any anonymous caller.
- *Integrity:* the 4 `/simulate/*` endpoints forge security events with attacker-chosen identity fields. The detectors read these back as ground truth, so an attacker can fabricate incidents, bury a real intrusion in noise, or frame an account. For a security-monitoring product this destroys evidentiary value.
- *Availability:* `/threats/scan` runs 4 ES aggregations and queues Slack + ES alerts via `BackgroundTasks` (`security.py:52-54`) per call. `simulate/lateral-movement` takes an **unbounded** `hosts: List[str]` (`security.py:29`) — one request yields N Elasticsearch writes.

**Actual:** anonymous read and write. **Expected:** authenticated, and simulation endpoints restricted to non-production or an admin role.
**Fix:** add `dependencies=[Depends(get_current_active_user)]` to the router in `app/main.py:47`; gate `/simulate/*` behind an explicit role plus `settings.environment != "production"`; bound `hosts`.
**Doc impact:** `docs/API_DOCUMENTATION.md:351` claims "All user endpoints (except registration/login) require valid JWT" — false for this router.

---

### SEC-002 — JWT signing key committed to a public repository
**Category:** Secrets · **Confidence:** CONFIRMED
**Locations:** `k8s/base/configmap.yaml:36-45`; consumed by `k8s/base/backend.yaml:33,63`, `k8s/base/migrate-job.yaml:31,40`; also `configmap.yaml:16` (DB URL with password in a **ConfigMap**)

**Evidence.** A `kind: Secret` block commits base64 values for `SECRET_KEY`, `POSTGRES_PASSWORD`, `ELASTIC_PASSWORD` and `KIBANA_PASSWORD`. `SECRET_KEY` decodes to a 48-byte key. Tracked in git (`git ls-files` confirms) since `2bdbbba`; repository is public. Independently flagged by gitleaks (`generic-api-key`, `kubernetes-secret-yaml`).

**Impact.** `SECRET_KEY` is the HS256 JWT signing key (`app/api/auth.py:22`). Anyone can mint a token for any user (`{"sub": "<victim email>"}`) against any Kubernetes deployment using these manifests — complete authentication bypass. `ACCESS_TOKEN_EXPIRE_MINUTES` is `43200` here (`configmap.yaml:11`) = **30 days**, versus 30 minutes in `.env`.
**Fix:** rotate the key; remove the Secret from git; source it from a sealed secret / external secret manager; purge from history. **Rotation is mandatory — removing the file does not undo public exposure.**

---

### SEC-003 — Password-reset OTP is predictable and brute-forceable (account takeover)
**Category:** Cryptography / Rate limiting · **Confidence:** CONFIRMED
**Locations:** `app/services/email_service.py:14-16,47-60,110-117`; `app/api/users.py:84-129`

**Evidence — weak generator.** `email_service.py:16`:
```python
return ''.join(random.choices(string.digits, k=length))
```
`random` is Mersenne Twister (MT19937), not a CSPRNG; `secrets` is never imported. PoC confirmed output is fully reproducible from generator state, and that state is recoverable from 624 consecutive 32-bit outputs.

**Evidence — no rate limiting.** Measured against the live app:
```
50 consecutive failed logins          -> 50 x 401   (no 429, no lockout)
60 consecutive wrong OTP submissions  -> 60 x 400   (no 429, no lockout)
```
`grep -rniE "ratelimit|rate_limit|slowapi|limiter" app/` returns nothing.

**Evidence — OTP accumulation.** Five `send_password_reset_otp` calls produced five rows, all `is_used = False`:
```
issued OTPs                  : ['363203','381395','518798','554558','537918']
simultaneously VALID (unused): 5
```
Prior OTPs are not invalidated, so an attacker multiplies the valid-OTP density at will.

**Exploitability.** Measured 66.7 req/s sequential on loopback → 10^6 keyspace in ~4.2 h single-threaded; expected hit ~2.1 h; ~6 min at 20 workers. The OTP window is 15 min (`email_service.py:56`), and the keyspace is exhaustible **within a single window** at modest concurrency. Weak generation and unlimited guessing are independently sufficient; together they make takeover routine.

**Verified NOT broken (recorded to bound the finding):** OTPs are single-use (`is_used` honoured) and correctly scoped to their owner — redeeming user A's OTP on user B's account returns `None`.
**Fix:** `secrets.choice`; ≥8 chars or an alphanumeric token; per-account attempt counter with lockout; invalidate outstanding OTPs on issue; throttle `/forgot-password` per account and per IP; store a hash rather than the cleartext OTP (`password_reset.py:12` currently stores cleartext).

---

### FUNC-001 — Threat detection fails open: 401s are swallowed and reported as "no threats"
**Category:** Correctness / Observability · **Confidence:** CONFIRMED
**Locations:** `app/services/threat_detection.py:11` (no auth) vs `app/services/security_logger.py:14-16` (auth); swallow sites `threat_detection.py:75-77,126-128,170-172,196-198,252-254,301-303,358-360,402-404`

**Evidence.** The app was pointed at a **security-enabled Elasticsearch 8.11.0** — the same configuration as `docker-compose.yml:49`. The authenticated writer path worked:
```
POST /simulate/powershell -> 200
GET  _cat/indices/security-*  ->  security-powershell-logs-2026.10.07
```
Every detector failed and was silently swallowed:
```
GET /api/v1/security/threats/brute-force -> 200 {"threats":[],"count":0}
GET /api/v1/security/threats/scan        -> 200 {"total_threats":0,...}

server log:
 "event": "Error in brute force detection"
 "error": "AuthenticationException(401, 'security_exception',
           'missing authentication credentials for REST request [/security-*/_search]')"
```

**Impact.** The single capability the project exists to provide is inoperative whenever Elasticsearch security is on — which is the shipped compose configuration, enabled deliberately in commit `ace9a3c`. Worse, the failure is indistinguishable from a clean result: an operator watching this dashboard sees "0 threats" and concludes they are safe. Every "detection working" claim in the documentation rests on this code path.
**Fix:** give `ThreatDetectionService` the same `basic_auth` as `SecurityLogger` (ideally one shared, configured client); surface detector errors as HTTP 503 with an explicit `degraded` flag rather than `[]`; add a health signal for ES reachability and authentication.
**Doc impact:** invalidates the "✅ WORKING" rule claims in `docs/KIBANA_ESQL_ALERTING_RULES.md:60` and the success metrics in `SECURITY.md:314-318`.

---

### OPS-001 — `docker-compose.yml` is invalid; the documented setup cannot run
**Category:** Configuration · **Confidence:** CONFIRMED
**Locations:** `docker-compose.yml:266` and `:284` (duplicate `depends_on` on `packetbeat`)

**Evidence.**
```
$ docker compose up -d
failed to parse docker-compose.yml: line 284: mapping key "depends_on" already defined at line 266
```
Present in HEAD (`88746ef`, most recent commit), not just the working tree. Removing the second `depends_on` in a scratch copy makes the file parse cleanly, so this is the **only** YAML blocker.

**Impact.** `docker compose up -d` is the primary documented start command (`README.md:55`, `docs/index.md:45`, `SECURITY.md:234`, `docs/SETUP_AND_TROUBLESHOOTING.md:151`, `CLAUDE.md`). No one cloning the repository can start the stack. Compose v2 treats duplicate mapping keys as a hard error.
**Fix:** delete `docker-compose.yml:284-285` and merge `logstash` into the `depends_on` block at `:266`. Add `docker compose config` to CI.

---

## HIGH

### SEC-004 — `elastic123` hardcoded as the cluster superuser password across the repository
**Confidence:** CONFIRMED (static, corroborated by gitleaks: 71 `curl-auth-user` hits)
**Locations:** `app/config.py:18` (default — and the value that actually runs, since no `ELASTICSEARCH_PASSWORD` key exists in `.env`); `docker-compose.yml:52,72`; `logstash/pipeline/logstash.conf:456-457,466-467,476-477,486-487,496-497,506-507,516-517`; `logstash/pipeline/threat-intel-enrichment.conf:20-21,72-73,116-117,162-163,189-190,313-314,322-323`; `filebeat/filebeat.yml:104-105,110-111`; `metricbeat/metricbeat.yml:51-52,57-58`; `docker-compose.packetbeat.yml:26`; `scripts/{aws-ec2-setup,import-otx-threat-intel,populate-threat-intel-data,setup-threat-intel-indices}.sh`; ~18 documentation files.
**Impact.** A single published password grants `elastic` superuser on every deployment that uses the defaults — full read/write/delete over all security indices. `scripts/aws-ec2-setup.sh:181-182` prints the credentials to stdout.
**Fix:** source from env/secret store with **no default**; fail closed when unset; rotate; purge from docs.

### SEC-005 — Live secrets on disk are baked into the backend image; container runs as root
**Confidence:** HIGH (static)
**Locations:** `.dockerignore` (omits `.env`, `test.db`, `sentinel.pem`); `Dockerfile:12` `COPY . .`; `Dockerfile` (no `USER`)
**Evidence.** The working-tree `.env` contains real-looking, currently-valid credentials: `SECRET_KEY`, `KIBANA_SYSTEM_PASSWORD`, a live-format `SLACK_WEBHOOK_URL`, a Gmail **app password** (`EMAIL_SMTP_PASSWORD`), and `ALIENVAULT_OTX_API_KEY`. `.env` is correctly gitignored and **was never committed** (verified). But `.dockerignore` does not exclude it, so `COPY . .` bakes it — plus `sentinel.pem` (an unencrypted RSA private key) — into every image layer. Anyone who can pull the image reads them.
**Fix:** add `.env`, `*.pem`, `test.db` to `.dockerignore`; add a non-root `USER`; multi-stage build to drop `gcc` (`Dockerfile:5-7`); rotate all five secrets.

### SEC-006 — JWT stored in a JavaScript-readable cookie for 30 days
**Confidence:** HIGH (static)
**Locations:** `website/lib/server-auth-cookies.ts:36,44` (`httpOnly: false, // Allow client-side access`); `website/lib/auth-cookies.ts:49,57-62`; `website/middleware.ts:5-9`
**Impact.** Any XSS yields full account takeover for 30 days. `Secure` is omitted over HTTP (`auth-cookies.ts:49`), so the token also crosses the wire in cleartext given nginx is HTTP-only (SEC-010). `middleware.ts` checks only cookie **presence** — any arbitrary string passes the gate (real enforcement is the backend's JWT check, so this is a UX gate, not a security boundary).
Secondary: `auth-cookies.ts:19` splits on `=` and takes `[1]`, truncating any value containing `=`.
**Fix:** `httpOnly: true` with a server-side session/BFF exchange; `Secure` always; shorten lifetime; add CSP.

### SEC-007 — User enumeration oracle on `/forgot-password`
**Confidence:** CONFIRMED
**Locations:** `app/api/users.py:88-108`
**Evidence.** With SMTP unreachable:
```
EXISTING victim@example.com -> HTTP 500 {"detail":"Failed to send password reset email..."}
UNKNOWN  nobody@example.com -> HTTP 200 {"message":"If the email exists in our system..."}
```
A clean, unambiguous oracle — directly contradicting the code's own comment at `users.py:89` ("Don't reveal if email exists or not for security").
**Fix:** return the same 200 body on every path; queue mail asynchronously; log failures server-side only.

### SEC-008 — Elasticsearch and Kibana are unauthenticated in all Kubernetes manifests
**Confidence:** HIGH (static — no cluster available)
**Locations:** `k8s/base/elasticsearch.yaml:71-72` (`xpack.security.enabled: "false"`); `k8s/base/kibana.yaml:12,43-44`; `k8s/base/ingress.yaml:111-119` (`kibana-loadbalancer`), `:8-9` (ssl-redirect disabled), no `tls:` block
**Impact.** Security is **off**, so the committed `ELASTIC_PASSWORD`/`KIBANA_PASSWORD` are irrelevant — anyone reaching the service reads and writes all security indices and Kibana saved objects. `ingress.yaml` would expose Kibana via a LoadBalancer over plain HTTP. Note `ingress.yaml` is **commented out** of `kustomization.yaml:18`, so the LoadBalancer is not applied by default — but ES/Kibana remain unauthenticated in-cluster regardless.
**Contradiction:** `docs/SECURITY_CREDENTIALS.md:5` asserts "Elasticsearch Security: ENABLED … All connections authenticated."
**Fix:** enable xpack security in k8s; add NetworkPolicies; put Kibana behind authentication; add TLS.

### SEC-009 — Packetbeat captures full HTTP request and response bodies, including credentials
**Confidence:** HIGH (static — **not** runtime-verified; requires host networking + NET_ADMIN/NET_RAW)
**Locations:** `packetbeat/packetbeat.yml:17-18` (`send_request: true`, `send_response: true`), `:14` ports `[80,8080,8002,5000,9200]`, `:78-79` output to Logstash with no credentials and no TLS
**Impact.** Port 80 and 8080 carry this application's own traffic, so `POST /api/v1/users/login` bodies (`username`+`password`), registration passwords, `Authorization: Bearer` headers and reset OTPs are captured verbatim and shipped unencrypted to Logstash, then indexed. This converts the monitoring layer into a plaintext credential store. `send_certificates: true` (`:24`) similarly captures TLS metadata.
**Fix:** `send_request: false`, `send_response: false`; exclude the application's own ports; configure `redact_headers` / drop body fields; enable TLS and auth on the Logstash output.

### SEC-010 — No TLS anywhere in the shipped topology
**Confidence:** CONFIRMED (static)
**Locations:** `nginx/nginx.conf:32` (`listen 80;` only — no `ssl_certificate`, no 443 server, no HTTP→HTTPS redirect, no HSTS); `kibana/kibana.yml:4`; `docker-compose.yml:50-51` (ES http/transport SSL disabled); `logstash` inputs (`logstash.conf:6-36`) have no `ssl_enabled`; `k8s/base/ingress.yaml` has no `tls:` block
**Impact.** JWTs, passwords, reset OTPs, `elastic123` and all security telemetry cross every hop in cleartext. `next.config.mjs:36` sends an HSTS header the server cannot honour over HTTP.
**Fix:** terminate TLS at nginx/ALB; redirect 80→443; enable TLS on ES, Logstash inputs and beats outputs.

### ALERT-001 — Security alerting is a hardcoded placeholder; alerts reach nobody
**Confidence:** CONFIRMED (static)
**Locations:** `app/services/alerting.py:17` (`"https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"`), `:35`, `:37-38` (failure swallowed), `:40-59` (`send_email_alert` builds a message and never sends)
**Evidence.** The only caller, `app/api/security.py:53`, passes a single argument, so `webhook_url` always falls back to the placeholder. `SLACK_WEBHOOK_URL` exists in `.env:30` but **no Python code reads it** — it is not even declared in `app/config.py`.
**Impact.** Every alert POSTs to a non-existent Slack URL and the exception is logged and discarded. Email alerting is dead code. Combined with FUNC-001, the detect→alert pipeline is non-functional end to end.
**Contradiction:** `SECURITY.md:27-37` claims multi-channel Slack + email + Elasticsearch alerting is implemented.
**Fix:** read the webhook from config; fail loudly when unset; implement or delete `send_email_alert`.

### SEC-011 — No rate limiting in the application; nginx auth limiting declared but never applied
**Confidence:** CONFIRMED
**Locations:** `nginx/nginx.conf:15-17` (three zones declared), `:92` (**only** `api_limit` applied, on `/backend/`); no limiter anywhere in `app/`
**Evidence.** `auth_limit` (5 r/s, intended for login) and `general_limit` are declared and **never referenced by any `location`**. Runtime: 50 logins + 60 OTP guesses, zero `429`.
**Impact.** Credential stuffing, OTP brute force (SEC-003), email bombing via `/forgot-password`, and expensive-endpoint abuse are unthrottled. `docker-compose.yml` publishes the backend directly on `0.0.0.0:8000`, so nginx can be bypassed entirely.
**Contradiction:** `CLAUDE.md` states auth endpoints are limited to 5 r/s burst 5.
**Fix:** apply `auth_limit` to login/register/forgot-password/reset-password; add application-layer per-account limiting; stop publishing port 8000.

### DEP-001 — 50 known vulnerabilities in 9 Python dependencies
**Confidence:** CONFIRMED (pip-audit) · Reachability triaged individually
**Locations:** `requirements.txt`
**Reachable and unauthenticated:** `python-multipart 0.0.6` (8 advisories incl. PYSEC-2024-38 ReDoS) and `starlette 0.27.0` (10 advisories) parse the **login form** (`OAuth2PasswordRequestForm`, `users.py:41`) — pre-auth DoS. `fastapi 0.104.1` (PYSEC-2024-38) same path.
**Reachable, authenticated:** `python-jose 3.3.0` PYSEC-2024-233 (JWT decode DoS) on every authenticated request.
**Lower reachability:** `requests 2.31.0` (used only by the dead Slack path); `ecdsa 0.19.2` (transitive; unused — HS256 only); `pytest`/`python-dotenv` (dev).
**Explicitly NOT exploitable here:** `python-jose` PYSEC-2024-232 algorithm confusion — `app/api/auth.py:36` passes an explicit `algorithms=[...]` list. See §Disproved.
**Fix:** upgrade the pinned set, prioritising `python-multipart`, `starlette`, `fastapi`.

### DEP-002 — Critical advisories in `next@16.0.3`
**Confidence:** CONFIRMED (npm audit) · Reachability triaged
**Locations:** `website/package.json:50`
**Reachable:** GHSA-9qr9-h5gf-34mp — critical RCE in the React flight protocol (App Router RSC is in use).
**NOT reachable (verified):** the AVIF Image-Optimization RCE and Image-Optimizer DoS advisories — `next.config.mjs:11` sets `images.unoptimized: true`, disabling the optimizer. The Windows RCE does not apply (alpine). Server-Action advisories do not apply — `grep -rn "use server"` returns nothing.
**Partially relevant:** middleware/proxy-bypass advisories affect `middleware.ts`, but impact is limited because that middleware is only a UX gate (SEC-006); the backend JWT check is authoritative.
**Fix:** upgrade `next` to a patched release.

### DEP-003 — `npm ci` fails; build is not reproducible
**Confidence:** CONFIRMED
**Locations:** `website/package.json:40,47,61,64`; `website/Dockerfile:9`
**Evidence.**
```
npm error ERESOLVE could not resolve
npm error While resolving: vaul@0.9.9
npm error Found: react@19.2.0
npm error peer react@"^16.8 || ^17.0 || ^18.0" from vaul@0.9.9
```
`website/Dockerfile:9` uses `npm i -f --production=false`, which **overrides peer-dependency resolution** — shipping `vaul` against an unsupported React major. Four dependencies (`@vercel/analytics`, `immer`, `use-sync-external-store`, `zustand`) are pinned to the floating tag `latest`, so two builds of the same commit can differ.
**Fix:** resolve or replace `vaul`; pin exact versions; restore `npm ci`.

---

## MEDIUM

### SEC-012 — Password change does not invalidate existing sessions
**Confidence:** CONFIRMED · `app/api/auth.py:15-23`; `app/api/users.py:111-129`
Runtime: token issued → password changed → **same token still returns 200 on `/users/me`**. No refresh tokens, no revocation list, no logout, no `jti`, no token version. A stolen token survives a reset for up to `ACCESS_TOKEN_EXPIRE_MINUTES` (30 min in `.env`, **30 days** in `k8s/base/configmap.yaml:11`).
**Fix:** add a token version or `password_changed_at` claim and reject older tokens; add logout + denylist.

### SEC-013 — Login timing oracle enables account enumeration
**Confidence:** HIGH (static) · `app/crud/user.py:43-49`
`authenticate_user` returns at `:46` for an unknown user **without performing any bcrypt work**, so responses for existing vs non-existing accounts differ by a full bcrypt cost-12 computation (tens of ms).
**Fix:** always compare against a dummy hash.

### OPS-002 — `/health` always returns 200, and leaks a DB connection per call
**Confidence:** CONFIRMED · `app/main.py:67-84` (status), `:71` (`engine.connect()` never closed)
Runtime, with Redis down: `HTTP/1.1 200 OK` with body `{"status":"unhealthy","database":"ok","redis":"error"}`. Kubernetes probes (`backend.yaml` liveness/readiness on `/health`) test the status code, so **a broken pod is never restarted or removed from service**. Separately, `engine.connect()` is called without `with`/`.close()`, leaking a pooled connection on every probe — unbounded growth given probes run continuously.
**Fix:** return 503 when unhealthy; use `with engine.connect()`.

### BUG-001 — Todo statistics cache is never invalidated (users see stale data)
**Confidence:** CONFIRMED · `app/api/todos.py:57,97-98,114-115` (invalidate `todos:*` and the single-todo key, never `stats:user:{id}`); set at `:144` with a 120 s TTL
Runtime with live Redis:
```
stats -> {"total_todos":1,...}       # primed
POST /todos/ (create a 2nd todo)
stats -> {"total_todos":1,...}       # STILL 1
GET /todos/ -> actual length 2
```
**Fix:** delete `stats:user:{id}` in the create/update/delete paths.

### SEC-015 — Validation errors echo the rejected value to the client **and** to Elasticsearch
**Confidence:** CONFIRMED · **Scope corrected during audit** · `app/exceptions.py:71-80`
`exc.errors()` is both logged (`:73`) and returned (`:79`). Pydantic v2 includes an `input` key echoing the rejected value, and `app/logging_config.py:23-29` ships the root logger to Logstash → Elasticsearch over plaintext TCP.
**Correction:** a broader claim — that *any* validation failure leaks the password — was **tested and disproved**. `input` is per-field, and `password`/`otp`/`new_password` are unconstrained `str`, so a normal string value never fails validation. The leak occurs only when a secret-bearing field fails **type** validation:
```
POST /users/reset-password {"otp":123456,"new_password":55512345}
-> response AND log contain: "input": 123456 , "input": 55512345
```
**Impact.** Secret-bearing values reach the SIEM and the client on malformed input. Real but narrower than first suspected.
**Fix:** strip `input` (and `ctx`) from both the logged and returned payloads; add a redaction processor to structlog.

### SEC-016 — SMTP TLS is unauthenticated and untimed; blocking call in an async path
**Confidence:** HIGH (static) · `app/services/email_service.py:32-34,38`
`smtplib.SMTP(...)` has **no timeout** and `starttls()` is called without an SSL context, so no certificate verification occurs — the mail session is MITM-able and the credentials (a Gmail app password) can be captured. Called synchronously from `async def forgot_password` (`users.py:96`), so a hung SMTP server blocks the event loop indefinitely. Errors are `print()`ed (`:43`), bypassing the log pipeline.
Also: `user.username` is f-string-interpolated into HTML email (`:68`) with no escaping and no username validation (`schemas/user.py:8`) — HTML injection into outbound mail.
**Fix:** `ssl.create_default_context()`, explicit timeout, run in a threadpool or a queue, escape template values, use structlog.

### DATA-001 — Alembic migration is Postgres-only and is never exercised by tests
**Confidence:** CONFIRMED · `alembic/versions/844a86b079e6_*.py`; `tests/conftest.py:27`
`alembic upgrade head` against SQLite fails — `server_default=func.now()` emits `DEFAULT now()`, which SQLite rejects. Tests use `Base.metadata.create_all`, so they validate the **models**, never the **migration**: the migration could break entirely and the suite would stay green.
Model/migration comparison showed **no drift** today (verified column-by-column).
Also `alembic.ini:5` hardcodes `postgresql://user:password@localhost:5432/todo_db` (overridden at runtime by `alembic/env.py:24`, so dead but leaky); `env.py` sets neither `compare_type` nor `compare_server_default`, so future autogenerate will miss type/default drift.
**Fix:** run migrations against Postgres in CI and assert the resulting schema matches the models.

### PERF-001 — Blocking synchronous I/O throughout `async def` handlers
**Confidence:** HIGH (static) · `app/cache.py:14-56` (sync `redis` in async methods); `app/services/security_logger.py` (sync `elasticsearch` client, 6 methods); `app/services/threat_detection.py` (same); `app/services/alerting.py:35` (`requests.post`); `app/services/email_service.py:32-39` (`smtplib`)
Every one of these blocks the event loop for the duration of a network round trip, serialising all concurrent requests behind it. `/health` (`main.py:75`) does the same with a sync Redis `ping`.
**Fix:** `redis.asyncio`, `AsyncElasticsearch`, `httpx.AsyncClient`, or offload to a threadpool.

### PERF-002 — Redis `KEYS` used for cache invalidation on every write
**Confidence:** HIGH (static) · `app/cache.py:41-49`, called from `app/api/todos.py:57,98,115`
`KEYS` is O(N) over the entire keyspace and **blocks the Redis server** for the duration — on every todo create, update and delete.
Related: `app/api/todos.py:25` interpolates the raw user-supplied `search` string into the cache key, so an attacker can mint unbounded distinct keys (60 s TTL each) — memory-exhaustion vector.
**Fix:** `SCAN` with a cursor, or maintain a per-user key set.

### SEC-014 — `/metrics` is unauthenticated and has unbounded label cardinality
**Confidence:** CONFIRMED (200 unauthenticated) · `app/main.py:84-89`; `app/middleware.py:55,61`
Exposes request volumes, latencies and every path. `endpoint=request.url.path` uses the **raw** path, so `/api/v1/todos/1`, `/2`, `/3` … each create a distinct time series — unbounded Prometheus cardinality, a memory-exhaustion vector an anonymous user can drive.
**Fix:** authenticate or bind to an internal interface; label by route template.

### K8S-001 — Logstash mounts a developer's absolute host path; the pod cannot start
**Confidence:** HIGH (static) · `k8s/base/logstash.yaml:81-84`
```yaml
hostPath: /home/rcsen/Documents/sih25/ps25238/logstash/pipeline
type: Directory
```
A workstation-specific path that does not even match this repository's directory name (`elk-stack-monitoring` vs `ps25238`). On any other node the `Directory` type fails and the pod will not schedule.
Related: PVs use `hostPath` under `/tmp` (`postgres.yaml:14`, `redis.yaml:14`, `elasticsearch.yaml:14`) — data is node-local and lost on `/tmp` cleanup, despite `Retain`.
**Fix:** ship the pipeline as a ConfigMap; use real StorageClasses.

### K8S-002 — Privileged and root containers, host networking, cluster-wide RBAC
**Confidence:** HIGH (static) · `k8s/base/elasticsearch.yaml:60-61` (`privileged: true` initContainer), `:55-56` (`runAsUser: 0`); `k8s/base/beats.yaml:71-72,232-233` (`runAsUser: 0`), `:49,:209` (`hostNetwork: true`), `:121-151,:282-314` (cluster-wide get/list/watch on pods, nodes, namespaces, deployments)
No `securityContext` at all on postgres, redis, logstash, kibana, backend, frontend or migrate-job; no `runAsNonRoot`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem`, dropped capabilities, seccomp profile, PodSecurity admission or NetworkPolicy anywhere.
A compromise of either beats DaemonSet yields root on the host network with cluster-wide read.
**Fix:** drop `privileged` (use an init `sysctl` via a dedicated mechanism or node config); add restrictive securityContexts; scope RBAC; add NetworkPolicies.

### CFG-001 — 13 service ports published on `0.0.0.0`
**Confidence:** CONFIRMED (`docker compose config` on the repaired file) · `docker-compose.yml`
Published: `80, 514, 3000, 5000, 5044, 5432, 5601, 6379, 8000, 9200, 9300, 9600, 12201`. No `host_ip` binding anywhere. This exposes **Postgres (5432)** and **password-less Redis (6379)** — `redis:7-alpine` is started with no `requirepass` (`docker-compose.yml:34-36`) — plus Elasticsearch, Kibana and the backend to the host's whole network.
On AWS the documented security group opens only 80/22, which mitigates there; on a laptop or LAN this is direct exposure.
**Fix:** bind to `127.0.0.1` for everything except nginx; set a Redis password.

### CORS-001 — Conflicting CORS policy between nginx and the application
**Confidence:** HIGH (static) · `app/middleware.py:67-73` vs `nginx/nginx.conf:106-108`
The app sets `allow_origins=["http://localhost:3000","http://localhost:8080"]` with `allow_credentials=True` — hardcoded, with no config override, so a deployed origin never matches. nginx layers `Access-Control-Allow-Origin: *` on `/backend/`. Browsers reject `*` with credentialed requests, and duplicate headers are a protocol error.
**Fix:** drive origins from configuration; set the header in exactly one layer.

---

## LOW

### QA-001 — `pytest.ini` configuration is silently inert
**Confidence:** CONFIRMED · `pytest.ini:1`
Uses `[tool:pytest]`, valid only in `setup.cfg`. Verified: pytest reports `configfile: pytest.ini` (it anchors rootdir) but **`addopts = -v --tb=short` does not take effect** — output is non-verbose. Any future `--cov-fail-under` or `--strict-markers` would also be ignored, silently.
**Fix:** rename the section to `[pytest]`.

### QA-002 — TypeScript and ESLint errors are suppressed at build time
**Confidence:** CONFIRMED · `website/next.config.mjs:63-68`; `website/tsconfig.json:20` (`"strict": false`)
`npx tsc --noEmit` reports **13 errors**. Ten are unused-symbol (TS6133/TS6196). Three are genuine type-safety failures in `website/lib/store/todo-store.ts:45,58,73` — `apiCall` is invoked without a type parameter (`lib/api-client.ts:35`), so `T` widens to `{}` and `set({todos: data})` assigns a non-array-typed value; `state.todos.map(...)` would throw if the API ever returned a non-array. There is no runtime validation (zod is a dependency but unused here).
**Fix:** type `apiCall<Todo[]>`, validate responses, enable `strict`, remove the ignore flags.

### CONTRACT-001 — `id` type disagrees across all three layers
**Confidence:** CONFIRMED · `app/models/todo.py:10` (int) vs `website/lib/store/todo-store.ts:7` (`id: string`) vs `docs/API_DOCUMENTATION.md:247-269` (UUID string)
Runtime proves the backend returns an **integer**. **No live bug today** — both sides of `todo.id === id` (`todo-store.ts:74`) are numbers at runtime, so the comparison works by accident. But the declared types are wrong, and passing an id from a URL param (a string) would make the strict comparison silently fail. Recorded as a correctness hazard, not an active defect.
**Fix:** align the TypeScript type to `number` and correct the documentation.

### QA-003 — Dead code and unused configuration
**Confidence:** CONFIRMED (ruff + grep)
- `app/services/email_service.py:123-133` `cleanup_expired_tokens` — **never called**; `password_reset_tokens` grows without bound.
- `app/services/security_logger.py:91-165` `log_api_access_event` — never called.
- `app/services/alerting.py:40-59` `send_email_alert` — never called; `import smtplib  # Add this back` (`:1`) unused.
- `app/logging_config.py:46` — `hasattr(settings,'elasticsearch_url')` is always `True` for a declared field, so the `ConsoleRenderer` branch (`:48-49`) is unreachable.
- `app/exceptions.py:17-39` — five custom exception classes, **never raised**.
- `app/schemas/user.py:25-28` `UserLogin` imported (`users.py:6`) but unused; `app/schemas/password_reset.py:21-33` unused.
- `app/config.py:15` `elasticsearch_url` declared, never consumed by any ES client.
- `nginx/nginx.conf:16-17` `auth_limit`/`general_limit` zones declared, never applied.
- 14 unused imports in `app/` (ruff F401); 5 unused variables (F841) at `security_logger.py:156,213,279,335,393`.
- `app/main.py:57-64` uses deprecated `@app.on_event`; `app/api/todos.py:41,60,80,101,43,81` use pydantic-v1 `from_orm`/`.dict()` (581 deprecation warnings per test run).

### QA-004 — `test.db` is tracked in git
**Confidence:** CONFIRMED · `.gitignore:15` lists it, but it was committed first so the ignore has no effect.
**Impact: none to confidentiality** — the file is an **empty SQLite database with zero tables** (verified). Repository hygiene only. Commit `6720579` claims to have removed it; it did not.
**Fix:** `git rm --cached test.db`.

### DOC-001 — Operational identifiers leaked in documentation
**Confidence:** CONFIRMED · `docs/SECURITY_CREDENTIALS.md:18-19` publishes a real-looking generated `kibana_system` password; `:161` pastes a live ES cluster UUID and node id; `BROWSER_MONITORING_SUCCESS.md:25-29,104` leaks the operator's workstation LAN IP (`10.20.30.117`); `:90,198,203` leak live Kibana alert-rule document ids and internal index names.
**Fix:** redact; rotate the kibana_system password.

---

## INFO

### INFO-001 — Route-ordering hazard in the todos router
`app/api/todos.py:63` declares `/{todo_id}` before `:121` `/stats/summary`. The two-segment path does not collide, so **`/stats/summary` works correctly** (verified: 200). However `GET /api/v1/todos/stats` would 422 rather than 404. Cosmetic.

### INFO-002 — Trailing-slash behaviour differs from the documentation
`GET /api/v1/todos` → **307** redirect; `GET /api/v1/todos/` → 200. `docs/API_DOCUMENTATION.md:107,133` documents the non-slash form. The frontend correctly uses the trailing slash (`app/api/todos/route.ts:17,47`).

### INFO-003 — `root_path="/backend"` is hardcoded
`app/main.py:38` hardcodes the reverse-proxy prefix, so generated OpenAPI/docs URLs and logged paths carry `/backend` even when the app is run directly. Observed in logs during this audit (`"url": "http://127.0.0.1:8099/backend/health"` for a request to `/health`).

---

## Suspicions tested and DISPROVED

Recorded so they are not re-raised, and to bound the findings above.

1. **Secrets leaked in git history — NO.** `website/.env` appears in history (`ae094f7`, removed in `d379ad1`) but contained only `BACKEND_URL` and `NEXT_PUBLIC_APP_URL`. The root `.env` and `sentinel.pem` were **never committed**. Gitleaks' 97 raw hits triage to the known `elastic123` in docs/scripts (71 `curl-auth-user`), the k8s Secret (SEC-002), Kibana encryption keys, and one example JWT in `API_DOCUMENTATION.md:85` — no additional secret material.
2. **`test.db` exposes user data — NO.** Empty; zero tables.
3. **IDOR in the todos API — NO.** Verified at runtime: a second user's GET, PUT and DELETE against another user's todo all return 404, and the owner's record is untouched. `app/crud/todo.py` scopes every query by `owner_id`.
4. **python-jose algorithm confusion (PYSEC-2024-232) — NOT EXPLOITABLE.** `app/api/auth.py:36` passes an explicit `algorithms=[settings.algorithm]` list.
5. **Next.js AVIF Image-Optimizer RCE — NOT REACHABLE.** `next.config.mjs:11` sets `images.unoptimized: true`. Server-Action advisories also not reachable (no `"use server"` in the codebase).
6. **"The todo tests only pass because Redis is unreachable" — FALSE.** The suite was run with no Redis, with a live Redis, and three consecutive times against a warm cache: 10/10 passed every time. `test_get_todo_stats` never re-reads stats after a mutation, so it simply never exercises the stale-cache path (BUG-001). The defect is untested, not masked.
7. **Elasticsearch cannot boot below `vm.max_map_count=262144` — FALSE on this host.** ES 8.11.0 single-node started **green** at `65530`; the check is a WARN, not a hard bootstrap failure. The sysctl is also already documented at `docs/SETUP_AND_TROUBLESHOOTING.md:327`.
8. **Cross-user OTP redemption — NO.** Redeeming user A's OTP against user B returns `None`. OTPs are also genuinely single-use.
