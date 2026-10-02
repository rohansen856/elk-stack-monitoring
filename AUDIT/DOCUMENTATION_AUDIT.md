# Documentation vs Implementation Audit

15,809 lines of Markdown across 37 files were inventoried for concrete claims, then each claim was checked against the implementation — several against the **running** application.

Classification per the brief:
1. DOCUMENTATION IS OUTDATED · 2. DOCUMENTATION IS INCORRECT · 3. IMPLEMENTATION IS INCOMPLETE
4. IMPLEMENTATION DIFFERS FROM DOCUMENTATION · 5. DOCUMENTATION IS AMBIGUOUS
6. IMPLEMENTATION HAS UNDOCUMENTED BEHAVIOUR · 7. BOTH REQUIRE CLARIFICATION

---

## D1 — Login request format
**DOC:** `docs/API_DOCUMENTATION.md:71-88` — `POST /api/v1/users/login` with JSON `{"email":..., "password":...}`.
**IMPL:** `app/api/users.py:41` uses `OAuth2PasswordRequestForm` (form-encoded, field named `username`).
**RUNTIME:** JSON → **422**; form → **200**.
**CLASS:** 2 (incorrect). **CONFIDENCE:** CONFIRMED.

## D2 — DELETE response code
**DOC:** `docs/API_DOCUMENTATION.md:167-170` — `204 No Content`.
**IMPL:** `app/api/todos.py:118` returns a dict, no `status_code`.
**RUNTIME:** **200** with `{"message":"Todo deleted successfully"}`.
**CLASS:** 2. **CONFIDENCE:** CONFIRMED.

## D3 — Identifier type
**DOC:** `docs/API_DOCUMENTATION.md:247-269` — `User.id` / `Todo.id` are UUID strings.
**IMPL:** `Integer` primary keys (`models/user.py:10`, `models/todo.py:10`).
**RUNTIME:** `id` is an `int`.
**ALSO:** `website/lib/store/todo-store.ts:7` declares `id: string` — a third answer. `docs/DATABASE_ARCHITECTURE.md:34,58` says `SERIAL`, contradicting the API doc.
**CLASS:** 2 + 7. **CONFIDENCE:** CONFIRMED. See CONTRACT-001.

## D4 — Endpoints documented that do not exist
**DOC:** `POST /api/v1/security/alerts/test` (`API_DOCUMENTATION.md:232-242`); `GET /health/detailed` (`COMPONENT_INTERACTIONS.md:459-476`, with specific metrics `avg_response_time_ms: 45`, `requests_per_second: 150`, `error_rate_percent: 0.1`).
**RUNTIME:** both **404**.
**CLASS:** 2. **CONFIDENCE:** CONFIRMED.

## D5 — Security endpoints undocumented, and auth claim false
**DOC:** `API_DOCUMENTATION.md:351` — "All user endpoints (except registration/login) require valid JWT."
**IMPL:** 14 endpoints in `app/api/security.py` require nothing (SEC-001). Only 4 of them appear in `API_DOCUMENTATION.md`; the 10 `hunt/*` and `threats/scan` endpoints appear only in `CONTRIBUTING.md:93-98`. The 4 `/simulate/*` **write** endpoints are documented nowhere.
**CLASS:** 2 + 6. **CONFIDENCE:** CONFIRMED. **This is the most consequential documentation failure in the repository.**

## D6 — Rate limiting
**DOC:** `CLAUDE.md` (Production Configuration) — API 10 r/s burst 20; **auth (login/register) 5 r/s burst 5**; general 20 r/s, via nginx zones.
**IMPL:** `nginx/nginx.conf:15-17` declares all three; `:92` applies **only** `api_limit`. No application-layer limiting exists.
**RUNTIME:** 50 logins + 60 OTP guesses, zero 429.
**NOTE:** `docs/API_DOCUMENTATION.md:355-359` is honest here ("Consider implementing rate limiting") — it contradicts `CLAUDE.md`.
**CLASS:** 2 + 7. **CONFIDENCE:** CONFIRMED.

## D7 — Elasticsearch security posture
**DOC:** `docs/SECURITY_CREDENTIALS.md:5-8` — "Elasticsearch Security: ENABLED … All connections authenticated."
**IMPL:** true for docker-compose (`:49`); **false for Kubernetes** — `k8s/base/elasticsearch.yaml:71-72` and `kibana.yaml:12,43-44` set it to `"false"`.
**ALSO:** `CLAUDE.md`'s own Production Checklist lists enabling xpack as an **unchecked TODO**, contradicting `SECURITY_CREDENTIALS.md`.
**CLASS:** 2 + 7. **CONFIDENCE:** CONFIRMED (static).

## D8 — Password hashing and session mechanism
**DOC:** `docs/DATABASE_ARCHITECTURE.md:441-450` — passlib `CryptContext(schemes=["bcrypt"], deprecated="auto")`; `:456-470` — session tokens via `secrets.token_urlsafe(32)` stored in Redis with a 1800 s TTL.
**IMPL:** raw `bcrypt` (`crud/user.py:2,14-19`); **passlib is never imported anywhere**. There are **no Redis sessions** — auth is stateless JWT only. No `CacheManager` class (`:394`) exists.
**CLASS:** 2 (describes a system that was never built). **CONFIDENCE:** CONFIRMED.

## D9 — Database documentation omits a table and misstates types
**DOC:** `docs/DATABASE_ARCHITECTURE.md:29` — "two main tables".
**IMPL:** three — `users`, `todos`, `password_reset_tokens`.
**ALSO:** doc claims `title VARCHAR(200)` (impl: `String(255)`), `username VARCHAR(50)` and `email VARCHAR(255)` (impl: unbounded `String`), and `owner_id ... ON DELETE CASCADE` (impl: **no** `ondelete`; cascade is ORM-only, so raw SQL deletes orphan rows). `CLAUDE.md` calls `priority` an enum; it is a free-text `String(20)` with no CHECK constraint.
**CLASS:** 1 + 2. **CONFIDENCE:** CONFIRMED.

## D10 — Environment variable names
**DOC:** `docs/SETUP_AND_TROUBLESHOOTING.md:142-145` — `SMTP_SERVER`, `SMTP_PORT`, `EMAIL_USER`, `EMAIL_PASSWORD`.
**IMPL:** `app/config.py:26-31` requires `EMAIL_SMTP_SERVER`, `EMAIL_SMTP_PORT`, `EMAIL_SMTP_USERNAME`, `EMAIL_SMTP_PASSWORD`, `EMAIL_SENDER_ADDRESS`, `EMAIL_SENDER_NAME`.
**IMPACT:** following the documentation verbatim produces a **startup crash** — these fields are required with no defaults (verified: 9 missing-field `ValidationError`s).
**ALSO:** the doc's `ELASTICSEARCH_URL=http://elasticsearch:9200` omits credentials, contradicting `SECURITY_CREDENTIALS.md:91`; and `elasticsearch_url` is never read by any client regardless. `ELASTICSEARCH_PASSWORD` — the name `config.py:18` actually reads — is documented nowhere and absent from `.env`, so the hardcoded `"elastic123"` default is what runs.
**CLASS:** 2 + 3. **CONFIDENCE:** CONFIRMED.

## D11 — Setup commands and files that do not exist
**DOC vs disk:** `local-startup.sh` ("RECOMMENDED", `CLAUDE.md`) ✗ · root `aws-ec2-setup.sh` (`docs/AWS_DEPLOYMENT.md:35-36`) ✗ (only `scripts/`) · `scripts/setup-browser-monitoring.sh` (`docs/PACKETBEAT.md:7,157`) ✗ · `scripts/fetch-otx-threat-intel.sh` (`ALIENVAULT_OTX_SUMMARY.md:162`) ✗ · `tests/test_security.py` (`CONTRIBUTING.md:235`) ✗ · `kibana/dashboards/` (`SECURITY.md:258`) ✗ · `.env.production.example` (`CLAUDE.md`) ✗ · `AWS_EC2_TROUBLESHOOTING.md` ✗ · `QUICK_START_BROWSER_MONITORING.md` ✗ · `OTX_DETECTION_README.md` ✗ · `apt_monitoring_guide.md` ✗ · `docker-compose.prod.yml` (`CONTRIBUTING.md:442`) ✗ · `LICENSE` (`README.md:242`) ✗ · `docs/APT_SIMULATORS.md` ✗ **and it is in the mkdocs nav (`mkdocs.yaml:121`), which will break the docs build**.
**ALSO:** `docs/KUBERNETES_DEPLOYMENT.md:29` instructs `cd ps25238` — a stale directory name that also appears in `k8s/base/logstash.yaml:83` (K8S-001).
**CLASS:** 1. **CONFIDENCE:** CONFIRMED.

## D12 — The documented quick start does not work
**DOC:** `docker compose up -d` in `README.md:55`, `docs/index.md:45`, `SECURITY.md:234`, `docs/SETUP_AND_TROUBLESHOOTING.md:151`, `CLAUDE.md`.
**RUNTIME:** parse failure (OPS-001).
**CLASS:** 4. **CONFIDENCE:** CONFIRMED. The single highest-impact documentation-vs-reality gap for a new user.

## D13 — Unsubstantiated performance and efficacy claims
`SECURITY.md:314-318` asserts "Sub-second threat identification", "reduces noise by 70%", "Coverage: 100% of APT kill-chain stages", "Handles 10K+ events per second"; `:320-326` "production-ready for enterprise security operations". `BROWSER_MONITORING_SUCCESS.md:249-255` asserts "100% detection rate" and "8 security alerts generated". `docs/ALIENVAULT_OTX_SUMMARY.md:20` asserts an OTX rate-limit utilisation figure.
**IMPL:** no benchmark, load test or measurement exists anywhere in the repository. The detection these numbers describe is the code proven non-functional in FUNC-001, and the alerting is a placeholder (ALERT-001).
**CLASS:** 2. **CONFIDENCE:** CONFIRMED that no supporting artifact exists.

## D14 — `/health` response shape
Three incompatible versions: 3 keys (`API_DOCUMENTATION.md:33-37`), 4 keys incl. `elasticsearch` (`CONTRIBUTING.md:323-329`), and "(database, redis, elasticsearch)" (`CLAUDE.md`).
**IMPL/RUNTIME:** 3 keys — `status`, `database`, `redis`. No elasticsearch check.
**CLASS:** 5 + 2. **CONFIDENCE:** CONFIRMED.

## D15 — Frontend proxy mapping
`website/README.md:90-95` claims `/api/auth/login → /auth/login` and `/api/todos → /todos`; `docs/API_DOCUMENTATION.md:304-308` claims `→ /api/v1/users/login`. The implementation matches the **latter** (`website/app/api/auth/login/route.ts:16`).
`website/README.md:129` also states "JWT tokens stored in localStorage" — the implementation uses **cookies** (`lib/auth-cookies.ts`).
**CLASS:** 1 + 2. **CONFIDENCE:** CONFIRMED.

## D16 — Trailing slash
`docs/API_DOCUMENTATION.md:107,133` documents `/api/v1/todos`; **runtime returns 307** (redirect) for the non-slash form. `CONTRIBUTING.md:80-81` and the frontend use the slash form. Minor but a real client-integration trap.
**CLASS:** 5. **CONFIDENCE:** CONFIRMED.

## D17 — Removed Elasticsearch API in documentation
`CLAUDE.md` and `CONTRIBUTING.md:539` instruct `curl -X POST "localhost:9200/_optimize"` — an API removed in Elasticsearch 5.x. The project runs 8.11.0.
**CLASS:** 1. **CONFIDENCE:** CONFIRMED.

## D18 — Documents that are status reports, not documentation
`BROWSER_MONITORING_SUCCESS.md`, `SECURITY.md`, `docs/ALIENVAULT_OTX_SUMMARY.md`, `docs/THREAT_INTEL_IMPLEMENTATION_SUMMARY.md`, `docs/SECURITY_CREDENTIALS.md`, `docs/PACKETBEAT.md` (whose filename does not match its content — it is titled "Quick Start: Browser Traffic Monitoring" and duplicates `BROWSER_MONITORING_SUCCESS.md`).
These are point-in-time run logs with ✅/🎉 status banners, dated "What Was Accomplished" sections, pasted terminal output and invented metrics. They assert that features work; §D13 and FUNC-001 show the central ones do not.
`SECURITY.md` is titled "Security Implementation Summary" and contains **no vulnerability-disclosure policy**, although `README.md:236` directs users there for responsible disclosure.
**CLASS:** 2 + 7 — requires a human decision on whether to rewrite or delete.

## D19 — mkdocs site integrity
`mkdocs.yaml:121` references the non-existent `APT_SIMULATORS.md`. **15 existing documents are absent from the nav** and therefore unreachable in the built site: `ALIENVAULT_OTX_INTEGRATION`, `ALIENVAULT_OTX_SUMMARY`, `APT_ATTACK_DETECTION_QUERY`, `AWS_DEPLOYMENT`, `CALDERA_ATTACK_SIMULATION_GUIDE`, `KIBANA_OTX_DETECTION_RULES`, `KIBANA_WINDOWS_NETWORK_RULES`, `LATERAL_MOVEMENT_DETECTION`, `MIMIKATZ_CREDENTIAL_THEFT_DETECTION`, `MONITOR_WORKSTATION_TRAFFIC`, `OTX_SECURITY_RULES_SETUP`, `PACKETBEAT`, `THREAT_INTEL_IMPLEMENTATION_SUMMARY`, `THREAT_INTELLIGENCE_INTEGRATION`, `WANNACRY_NOTPETYA_DETECTION`. ~~`mkdocs.yaml:101-102` configures the `mike` version provider, but `docs/requirements.txt` does not install `mike`.~~ **RETRACTED 2026-10-07 — this finding was incorrect.** `mike>=2.0.0` is present at `docs/requirements.txt:7`, and was present at HEAD. Verified with `git show HEAD:docs/requirements.txt`. `docs/MASTER_GUIDE (1).pdf` (470 KB) has a filename containing a space and a `(1)` download suffix.
**CLASS:** 3. **CONFIDENCE:** CONFIRMED (file existence verified).

## D20 — Credentials published in documentation
`docs/SECURITY_CREDENTIALS.md:14-15,24,26,29,39,74,154,166,180` and ~18 other files publish `elastic:elastic123`; `:18-19` publishes a real-looking generated `kibana_system` password; `:161` pastes a live cluster UUID and node id; `docs/KIBANA.md:78-80` publishes Kibana encryption keys; `BROWSER_MONITORING_SUCCESS.md:25-29` leaks the operator's LAN IP and `:90,198,203` live Kibana alert-rule ids.
**CLASS:** 2 + 6. **CONFIDENCE:** CONFIRMED. See SEC-004, DOC-001.

---

## Summary

| Classification | Count |
|---|---|
| 1 — Outdated | 5 |
| 2 — Incorrect | 13 |
| 3 — Implementation incomplete | 3 |
| 4 — Implementation differs | 1 |
| 5 — Ambiguous | 3 |
| 6 — Undocumented behaviour | 3 |
| 7 — Requires human decision | 5 |
| **Distinct discrepancies** | **20** |

**Overall assessment: the documentation cannot be relied upon.** Where it was checkable, it was wrong more often than right, and it is wrong in the direction of overstating capability — claiming authentication, rate limiting, alerting, detection efficacy and encryption that the implementation does not provide. For an unfamiliar engineer the docs are actively misleading; several documented procedures (D10, D11, D12) fail outright.
