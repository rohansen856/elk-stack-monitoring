# Documentation Gaps — important behaviour that is undocumented

Only behaviour another engineer, operator or security reviewer would genuinely need is listed. Per-function documentation is deliberately out of scope.

## Critical gaps

### G1 — The `/simulate/*` write endpoints are documented nowhere
`POST /api/v1/security/simulate/{powershell,privilege-escalation,lateral-movement,data-exfiltration}` write directly into Elasticsearch with caller-supplied identity fields, unauthenticated. No document mentions they exist. An operator cannot reason about the integrity of their own security indices without knowing this.
**Needs:** existence, exact payload schema, what index each writes to, the fact that they are unauthenticated today, and explicit guidance that they must not be exposed.

### G2 — Authentication model and its limits
Undocumented: that there are **no refresh tokens, no logout and no revocation**; that a token stays valid after a password reset; that the token carries only `sub` and `exp`; that `ACCESS_TOKEN_EXPIRE_MINUTES` is 30 in `.env` but **43200 (30 days)** in `k8s/base/configmap.yaml:11`; that a missing `Authorization` header yields **403** rather than 401; that inactive users receive **400**.

### G3 — The Elasticsearch credential split
Nothing documents that `security_logger` authenticates while `threat_detection` does not, nor the consequence (FUNC-001): with xpack enabled, all detection silently returns empty. This is the single most important operational fact about the system and it appears in no document — the docs assert the opposite.

### G4 — Detection failure modes
All eight detectors return `[]` on **any** exception. No document states that an empty result is ambiguous between "clean" and "broken", or how to distinguish them (currently: only by reading server logs for `"Error in ... detection"`).

### G5 — Password-reset semantics
Undocumented: 6-digit numeric OTP; 15-minute expiry; single-use; **multiple OTPs valid simultaneously**; OTP stored in cleartext; no attempt limit; the `token` column is globally unique so two users can collide; expired rows are never cleaned up (`cleanup_expired_tokens` is never called).

## Operational gaps

### G6 — Required environment variables
`app/config.py` requires `DATABASE_URL`, `REDIS_URL`, `SECRET_KEY` and **all six `EMAIL_*`** variables with no defaults; the application **crashes at import** without them. The documented names are wrong (D10). Undocumented entirely: `ELASTICSEARCH_PASSWORD` (the name actually read, defaulting to `elastic123`), and that `SLACK_WEBHOOK_URL` in `.env` is **never read by any code**. `extra="ignore"` (`config.py:34`) means typo'd variables are silently dropped — worth stating.

### G7 — Schema creation is migration-only
`Base.metadata.create_all` is never called in application code, so the schema exists only if `alembic upgrade head` has run (the compose `migrate` service does this). Undocumented: the migration **does not work on SQLite** (`DEFAULT now()`), so the documented `sqlite:///./test.db` path requires `create_all` instead — which is what the tests silently do.

### G8 — Logging pipeline is a data-exposure channel
Undocumented: the Logstash handler is attached to the **root** logger, so all third-party library logs ship too; transport is **plaintext TCP with no authentication**; emails, full request URLs with query strings, SQL exception text and rejected validation input are all shipped and indexed. Anyone performing a privacy or data-retention review needs this.

### G9 — Index inventory and retention
Six application indices are created (`security-auth-logs-*`, `-api-logs-*`, `-powershell-logs-*`, `-network-logs-*`, `-privilege-logs-*`, `-lateral-logs-*`) plus seven from Logstash. There is **no ILM policy, no retention policy and no index template** for the application-written indices, so they grow unbounded. `SECURITY.md:73-74` claims ILM exists; no such configuration is present.

### G10 — Cache behaviour
Undocumented: key schemes and TTLs (`todos:*` 60 s, `todo:*` 300 s, `stats:*` 120 s); that `stats` is **never invalidated** (BUG-001); that invalidation uses blocking `KEYS`; that cache hits bypass response-model validation; that Redis runs **without a password**.

### G11 — Port exposure
Undocumented: docker-compose publishes **13 ports on `0.0.0.0`**, including Postgres 5432, password-less Redis 6379, Elasticsearch 9200 and the backend 8000 — so the nginx rate limit and routing are trivially bypassable. The AWS guide's "only 80 and 22" security-group advice is the only thing mitigating this, and only on EC2.

### G12 — Kubernetes divergence
Undocumented: xpack security is **disabled** in k8s; `ingress.yaml` is **excluded** from `kustomization.yaml`; Logstash mounts a developer-specific `hostPath` that will not exist on any other machine (K8S-001); PVs are `hostPath` under `/tmp`; beats DaemonSets run as root with host networking and cluster-wide RBAC.

### G13 — Packetbeat captures request and response bodies
`send_request`/`send_response: true` on ports including 80 and 8080 means credentials in login bodies are captured and indexed. This has obvious privacy and compliance consequences and is documented nowhere.

## Development gaps

### G14 — No contribution-critical tooling is actually present
`CLAUDE.md` documents `black`, `flake8`, `mypy`, `pre-commit`; none is configured in the repository, and there is **no CI pipeline at all**. `website/package.json` defines a `lint` script with no `eslint` dependency. New contributors have no automated gate — which is how OPS-001 (a broken compose file) reached `master`.

### G15 — `npm ci` does not work
`website/README.md:24` documents `npm install`; `website/Dockerfile:9` quietly uses `npm i -f`. Undocumented: `npm ci` **fails** on a `vaul`/React-19 peer conflict, and four dependencies are pinned to `latest`, so builds are not reproducible.

### G16 — Test suite prerequisites
Undocumented: `pytest` cannot even import the application without a fully populated `.env`; there is no test env file or fixture; `pytest.ini` is inert (QA-001); `tests/test_security.py` is referenced by `CONTRIBUTING.md:235` but does not exist.

## Missing policy documents

### G17 — No vulnerability-disclosure policy
`README.md:236` points to `SECURITY.md` for responsible disclosure; `SECURITY.md` is an implementation status report with no reporting contact, scope or SLA.

### G18 — No LICENSE file
`README.md:242` references one; it does not exist. Legally significant for a public repository.

### G19 — No threat model or data-classification note
The system ingests credentials, command lines and host identifiers. Nothing documents what data is collected, where it is stored, who can read it, or for how long.
