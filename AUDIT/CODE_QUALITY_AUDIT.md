# Code Quality and Maintainability Audit

Separated per the brief into **A. defects**, **B. maintainability**, **C. style**. Style items are listed only where they carry engineering cost.

## A. Actual defects

| ID | Defect | Location |
|---|---|---|
| BUG-001 | `stats:user:{id}` never invalidated → stale statistics (reproduced) | `app/api/todos.py:57,97-98,114-115` |
| OPS-002 | `/health` returns 200 when unhealthy; `engine.connect()` leaks a connection | `app/main.py:67-84` |
| FUNC-001 | Detector ES client has no credentials; all errors swallowed → `[]` | `app/services/threat_detection.py:11` + 8 handlers |
| ALERT-001 | Slack webhook is a placeholder; no caller passes a real one | `app/services/alerting.py:17` |
| SEC-003 | `random` used for a security credential | `app/services/email_service.py:16` |
| — | `hasattr()` on a declared pydantic field is always `True` → dead branch | `app/logging_config.py:46-49` |
| — | `request.client.host` dereferenced without a `None` guard inside middleware | `app/middleware.py:27` |
| — | Prometheus label uses the raw path → unbounded cardinality | `app/middleware.py:55,61` |
| — | `threat['threat_type']` indexed with `[]` not `.get()` → `KeyError` | `app/services/alerting.py:20,25,36,46,53,78` |
| — | `title` unbounded in schema vs `String(255)` column → 500 on long input | `app/schemas/todo.py` vs `app/models/todo.py:11` |
| — | OTP `token` column is **globally** unique → cross-user collision raises `IntegrityError` → 500 | `app/models/password_reset.py:12` |
| — | Reset marks the OTP used and updates the password in **two** transactions; a failure between them burns the OTP without changing the password | `email_service.py:117` + `users.py:124` |
| — | Naive `datetime.utcnow()` written into `DateTime(timezone=True)` columns | `email_service.py:56,111`; `auth.py:18,20` |
| — | Cache-hit paths return raw deserialized data, bypassing `response_model` validation | `app/api/todos.py:30,74` |
| QA-002 | 3 genuine type errors suppressed by `ignoreBuildErrors` | `website/lib/store/todo-store.ts:45,58,73` |

Ruff reports 27 issues; 5 `F841` unused-variable at `security_logger.py:156,213,279,335,393` are assigned `result` values never checked — the ES write result is discarded, which is why a failed write still reports `{"status":"success"}`.

**Ruff false positives (do not "fix"):** the two `E712` hits (`crud/todo.py:73`, `email_service.py:110`) use `== True` / `== False` inside **SQLAlchemy filter expressions**, where `not x` would break the generated SQL. The three `F401` model imports in `main.py:14-16` are required to register mappers on `Base.metadata`.

## B. Maintainability concerns

- **Test coverage is the dominant risk.** 276 test LOC for 2,303 app LOC; `app/services/` (1,027 LOC) and `app/api/security.py` (224 LOC) are entirely untested. See `TEST_AUDIT.md`.
- **No dependency-injection seam** for Redis/ES/SMTP clients (A4) — the primary reason the services are untestable.
- **Repetition:** `security_logger.py` repeats one try/index/except shape six times; `threat_detection.py` repeats a query/parse/except shape eight times.
- **Magic numbers** throughout `threat_detection.py` (risk scores 7/9/10/8 at `:164,189,247,296,397`; thresholds at `:58,79,179,345`) and `security.py:52,58` — all undocumented and unconfigurable.
- **Deprecated APIs:** `@app.on_event` (`main.py:57-64`), pydantic-v1 `from_orm`/`.dict()` (6 sites) producing **581 deprecation warnings per test run**, `datetime.utcnow()`, the `body=` kwarg to `elasticsearch` 8.x (`threat_detection.py:41,104,156,237,284,336,384`).
- **Dead code** — see QA-003; 14 unused imports.
- **`.python-version` says 3.12.6**, `Dockerfile` uses `python:3.11-slim`, the host runs 3.14.6. Three different targets.
- **`website/tsconfig.json:20` sets `"strict": false`**, so null-safety is off across 9,089 LOC of TypeScript.
- **No linter or formatter is enforced.** `CLAUDE.md` documents `black`, `flake8`, `mypy` and `pre-commit`; there is no `.pre-commit-config.yaml`, no CI workflow, and no `.flake8`/`pyproject.toml` config in the repository. `website/package.json` has a `lint` script but **no `eslint` dependency**.
- **No CI at all** — no `.github/workflows`. Nothing would have caught the broken `docker-compose.yml` (OPS-001) or the failing `npm ci` (DEP-003).

## C. Style (noted, not actioned)

Inconsistent import ordering; a few over-long functions in `threat_detection.py`; trailing whitespace after `security.py:47`; `# Add this back` left in `alerting.py:1`. None of these carry material cost.

## Notable positives

- `app/crud/todo.py` is clean, consistent and correctly scoped — the best code in the repository.
- Structured logging with request-id correlation is properly implemented.
- Pydantic schemas cleanly separate request/response shapes, and `UserResponse` correctly omits `hashed_password`.
- The Alembic migration faithfully reproduces the models (verified column-by-column — no drift).
