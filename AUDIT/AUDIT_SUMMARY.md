# Audit Summary — elk-stack-monitoring ("Sentinel")

**Audit date:** 2026-10-07
**Repository:** `github.com/rohansen856/elk-stack-monitoring` (public), branch `master`, HEAD `88746ef`, 104 commits
**Auditor method:** static source inspection + dependency scanning + **live runtime reproduction** against an isolated instance of the application and a security-enabled Elasticsearch 8.11.0.

> This report does **not** declare the repository secure or production ready.
> It states what was verified, what was disproved, and what remains unverified.

---

## 1. What the system actually is

Despite the "security monitoring platform" framing, the implementation is a **small FastAPI to-do/auth CRUD application** (2,303 LOC) with a **bolted-on, largely non-functional threat-detection surface**, plus a Next.js UI (~9,089 LOC) and a large volume of ELK/beats configuration.

| Layer | Reality |
|---|---|
| Backend | FastAPI; 3 routers — `users` (5 endpoints), `todos` (6), `security` (14) |
| Auth | JWT HS256, 30-min access token, **no refresh, no logout, no revocation** |
| Data | PostgreSQL via SQLAlchemy + Alembic (1 migration); Redis cache |
| Frontend | Next.js 16 App Router, BFF route handlers proxying to the backend |
| ELK | ES + Logstash + Kibana + Filebeat/Metricbeat/Packetbeat/Winlogbeat |
| Deploy | docker-compose (12 services), Kubernetes manifests, nginx, AWS EC2 script |
| Docs | **15,809 lines of Markdown — ~7x the backend code** |
| Tests | **276 lines, 18 tests**, covering only users/todos/health |

**Documentation-to-code ratio and test coverage are the two clearest signals of the repository's true maturity.**

---

## 2. Headline findings

### The product's core function does not work (CONFIRMED at runtime)

`app/services/threat_detection.py:11` constructs its Elasticsearch client with **no credentials**, while `app/services/security_logger.py:14-16` uses `basic_auth`. Against a security-enabled cluster — which is exactly what `docker-compose.yml:49` configures — every detection query fails:

```
AuthenticationException(401, 'security_exception',
  'missing authentication credentials for REST request [/security-*/_search]')
```

All eight detection methods catch broadly and `return []`, so the API answers:

```
GET /api/v1/security/threats/scan -> 200 {"total_threats":0,"high_risk_threats":0,"threats":[]}
```

**"No threats found" is byte-identical to "detection is completely broken."** Events are still written (the logger path is authenticated), so the system looks alive while detecting nothing. See `FINDINGS.md` → **FUNC-001**.

### Every security endpoint is unauthenticated (CONFIRMED at runtime)

All 14 endpoints in `app/api/security.py` lack any `Depends(...)`. Measured against a running instance with no `Authorization` header:

```
GET /api/v1/security/threats/*  -> 200   (10 endpoints)
GET /api/v1/security/hunt/*     -> 200
POST /api/v1/security/simulate/* -> 200  (4 endpoints, WRITE to Elasticsearch)
---- contrast ----
GET /api/v1/todos/              -> 403
GET /api/v1/users/me            -> 403
```

The four `POST /simulate/*` endpoints let an anonymous caller write **attacker-controlled** `user`, `host`, `command` and `source_ip` into the SIEM — forging audit trails that the detectors then read back as ground truth. See **SEC-001**.

### Full account takeover via password reset (CONFIRMED at runtime)

Three defects compose into a practical ATO chain:
1. The OTP is generated with `random.choices` — Mersenne Twister, **not** `secrets` (`email_service.py:16`).
2. **No rate limiting exists anywhere in the application.** 50 failed logins and 60 OTP guesses were issued back-to-back; every one was processed (no `429`, no lockout).
3. Each `/forgot-password` call mints an **additional** valid OTP without invalidating prior ones — 5 calls were measured producing **5 simultaneously valid OTPs**.

Measured throughput was 66.7 req/s single-connection on loopback. The 10^6 keyspace is exhaustible **inside the OTP's own 15-minute validity window** with modest parallelism. See **SEC-003**.

### A JWT signing key is committed to a public repository

`k8s/base/configmap.yaml:42` commits a base64 `Secret` containing `SECRET_KEY`, consumed by `backend.yaml` and `migrate-job.yaml`. Anyone can forge a valid token for any Kubernetes deployment of this stack. Present since commit `2bdbbba`. See **SEC-002**.

### The documented setup command is broken

`docker compose up -d` — the primary quick-start in `README.md:55`, `docs/index.md:45`, `SECURITY.md:234`, `docs/SETUP_AND_TROUBLESHOOTING.md:151` and `CLAUDE.md` — **fails outright**:

```
failed to parse docker-compose.yml: line 284: mapping key "depends_on" already defined at line 266
```

The duplicate key is **committed in HEAD** (`88746ef`, the most recent commit). Nobody cloning this repository can start the stack. See **OPS-001**.

---

## 3. Findings by severity

| Severity | Count |
|---|---|
| CRITICAL | 5 |
| HIGH | 11 |
| MEDIUM | 14 |
| LOW | 6 |
| INFO | 3 |
| **Total** | **39** |

Confidence: **32 CONFIRMED**, **7 HIGH** (static, not executed). Of the CONFIRMED set, **20 were reproduced against a live running instance** (the remainder are confirmed by direct file evidence such as a committed secret or a scanner result validated by hand). Suspicions **tested and disproved: 8** — recorded in `FINDINGS.md` §Disproved so they are not re-raised.

---

## 4. Documentation vs implementation

The documentation is **systematically unreliable**. Verified against the running API:

| Documented claim | Reality |
|---|---|
| `POST /users/login` takes JSON `{email,password}` (`API_DOCUMENTATION.md:71-88`) | Form-encoded only; JSON → **422** |
| `DELETE /todos/{id}` → `204 No Content` (`:167-170`) | **200** with a JSON body |
| `id` is a UUID string (`:247-269`) | **integer** |
| `POST /api/v1/security/alerts/test` (`:232-242`) | **404 — does not exist** |
| `GET /health/detailed` (`COMPONENT_INTERACTIONS.md:459`) | **404 — does not exist** |
| Auth endpoints are rate limited (`CLAUDE.md`) | `auth_limit` zone declared, **never applied**; no app-layer limiting |
| ES security "ENABLED" everywhere (`SECURITY_CREDENTIALS.md:5`) | **Disabled** in all Kubernetes manifests |
| `passlib` CryptContext + `secrets.token_urlsafe` sessions (`DATABASE_ARCHITECTURE.md:441-470`) | Neither exists; raw `bcrypt`, no Redis sessions |

**14 doc-referenced files do not exist**, including `docs/APT_SIMULATORS.md` which is in the mkdocs nav (`mkdocs.yaml:121`) and will break the docs build. **15 existing docs are unreachable** from the nav.

Six documents are AI-style status reports asserting success with **invented metrics** — "70% false positive reduction", "10K+ events/second", "100% detection rate" (`SECURITY.md:314-318`, `BROWSER_MONITORING_SUCCESS.md:249-255`). These metrics have no supporting implementation; the detection they describe is the same code proven non-functional above.

`SECURITY.md` is a status report, **not a vulnerability-disclosure policy**, despite `README.md:236` directing users there for responsible disclosure.

---

## 5. Testing

18 tests, all passing — but they conceal more than they verify:

- **`app/api/security.py`: 0% coverage** — all 14 unauthenticated endpoints untested.
- **`app/services/` (1,027 LOC): 0% coverage** — no test of OTP generation, expiry, reuse, or any detector.
- **The entire password-reset flow is untested.**
- Cross-tenant **writes** (PUT/DELETE) untested; only GET is covered.
- No expired/tampered-token tests.
- `pytest.ini` uses `[tool:pytest]`, valid only in `setup.cfg` — **`addopts` is silently ignored** (verified: `-v` does not take effect).
- Tests use `Base.metadata.create_all`, so **the Alembic migration is never exercised**. It was verified to **fail on SQLite** (`DEFAULT now()` is Postgres-only).

---

## 6. Dependencies

- **Python: 50 known vulnerabilities across 9 packages.** Reachable-and-unauthenticated: `python-multipart 0.0.6` / `starlette 0.27.0` multipart ReDoS/DoS on the login form parser.
- **npm: 8 vulnerabilities (1 critical, 6 high).** `next@16.0.3` carries a critical React-flight-protocol RCE.
- **`npm ci` fails** — `vaul@0.9.9` requires React ≤18 against React 19. `website/Dockerfile:9` masks this with `npm i -f`, shipping a component against an unsupported React major. Four dependencies are pinned to the floating tag `latest`, so **builds are not reproducible**.

---

## 7. What was NOT verified

Stated plainly, as required:

- **Kubernetes manifests were never applied** — no cluster. All k8s findings are static.
- **AWS EC2 deployment was never executed.**
- **Windows/Winlogbeat and Packetbeat capture paths were never run** — no Windows host, and Packetbeat requires host networking plus `NET_ADMIN`/`NET_RAW`. The Packetbeat body-capture finding (**SEC-009**) is read from configuration, not observed.
- **The full 12-service compose stack was never brought up** — the compose file does not parse (OPS-001). Elasticsearch was validated standalone instead.
- **Logstash pipelines were not executed**; credential findings there are static.
- No penetration testing was performed against any third-party or production system. All reproduction was local and isolated.

---

## 8. Top remediation priorities

1. **Rotate every exposed credential** (see `REMEDIATION_PLAN.md` Phase 0) — the committed k8s `SECRET_KEY`, and the live Gmail app password, Slack webhook and OTX API key present in the working-tree `.env`.
2. **Add authentication to `app/api/security.py`** and remove or gate the `/simulate/*` write endpoints.
3. **Fix the Elasticsearch credential split** in `threat_detection.py` and make detection failures loud instead of returning `[]`.
4. **Replace `random` with `secrets` for OTPs** and add rate limiting plus lockout on login and password reset.
5. **Fix `docker-compose.yml`** so the documented setup works at all.
6. **Reconcile the documentation with reality** — or delete the status-report documents that assert capabilities the code does not have.

Full detail: `FINDINGS.md`, `FINDINGS.json`, `REMEDIATION_PLAN.md`.
