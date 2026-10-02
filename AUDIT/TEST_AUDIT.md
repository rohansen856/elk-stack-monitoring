# Test Audit

## Inventory

18 tests, 276 LOC, across 3 files + `conftest.py`. **All 18 pass** (verified: `18 passed in 10.54s`).

| File | Tests | What is asserted |
|---|---|---|
| `tests/test_health.py` | 2 | `/health` → 200 and that keys exist; `/metrics` → 200 + content-type |
| `tests/test_auth.py` | 6 | register, duplicate email, login, bad credentials, `/me`, invalid token |
| `tests/test_todos.py` | 10 | CRUD, stats, filter, search, unauthorized (403), one cross-tenant GET |

## Coverage of the application

| Module | LOC | Covered |
|---|---|---|
| `app/api/todos.py` | 144 | good |
| `app/api/users.py` | 129 | register/login/me only — **reset flow untested** |
| `app/api/auth.py` | 52 | happy path + one invalid token |
| **`app/api/security.py`** | **224** | **0%** |
| **`app/services/threat_detection.py`** | **405** | **0%** |
| **`app/services/security_logger.py`** | **409** | **0%** |
| **`app/services/email_service.py`** | **132** | **0%** |
| **`app/services/alerting.py`** | **81** | **0%** |
| `app/exceptions.py` | 106 | 0% |
| `app/middleware.py` | 73 | indirectly only |
| `app/cache.py` | 58 | never exercised (see below) |

**1,251 LOC — 54% of the application — has zero test coverage**, and it is precisely the security-relevant half.

## Defects the suite does not catch

Every one of these is a confirmed finding that the green suite misses:

- **SEC-001** — 14 unauthenticated endpoints. No test asserts that *any* security endpoint requires auth.
- **SEC-003** — OTP generation, expiry, reuse, brute force: the whole reset flow is untested.
- **SEC-007** — the 500-vs-200 enumeration oracle.
- **SEC-012** — token validity after a password change.
- **FUNC-001** — detector behaviour against a secured ES.
- **BUG-001** — the stale stats cache (see below).
- **OPS-002** — `test_health.py:5` asserts only that `status` and `database` **keys exist**, never their values. Because `/health` returns 200 when unhealthy, **this test passes with Postgres and Redis both down** — verified during this audit.

## Tests that are misleading

**`test_health.py:5`** — the clearest example of a test that cannot fail for the reason it exists. It would pass against a completely broken deployment.

**`test_todos.py:129` (`test_unauthorized_access`)** asserts **403**, documenting the non-standard `HTTPBearer` behaviour rather than questioning it. It covers only `POST /todos/`; no equivalent exists for the security router, which is where the real gap is.

**`test_todos.py:79` (`test_get_todo_stats`)** — a hypothesis that it "only passes because Redis is unreachable" was **tested and disproved**: it passes with no Redis, with a live Redis, and across three consecutive runs against a warm cache. The reason is simpler — it creates todos and *then* reads stats once, so it never re-reads after a mutation and never exercises the invalidation path. **The cache is never meaningfully tested at all**: because `conftest.py` provides no Redis, the cache-hit branches (`todos.py:28-30,72-74`) never execute under test.

## Structural problems

- **`pytest.ini:1` uses `[tool:pytest]`**, valid only in `setup.cfg`. Verified: pytest names it as `configfile` (it anchors rootdir) but **`addopts = -v --tb=short` is not applied**. Any future `--cov-fail-under` or `--strict-markers` would be ignored silently — a trap for whoever adds coverage gates.
- **The suite cannot run on a clean checkout.** Importing `app.main` instantiates `Settings()` at import time, so 9 required variables must be present. There is no test env file, no `monkeypatch.setenv`, no `.env.test`. This audit had to construct one.
- **`conftest.py:9` uses a file-backed `sqlite:///./test.db`** in the repository root rather than `tmp_path` or in-memory — which is how `test.db` came to be committed (QA-004).
- **Tests validate models, not migrations.** `conftest.py:27` calls `create_all`. The Alembic migration was verified to **fail on SQLite**, so it is not merely untested — it is untestable on the configured test backend (DATA-001).
- **`pytest-asyncio` is installed but no test is async** and no `asyncio_mode` is set. None of the `async` service code is directly tested.
- **No CI** — nothing runs these tests automatically.
- `tests/test_security.py` is referenced by `CONTRIBUTING.md:235` but does not exist.

## Priority test gaps

1. Authorization matrix for **every** route — especially asserting that `/api/v1/security/*` requires authentication.
2. Full password-reset flow: wrong OTP, expired OTP, reused OTP, cross-user OTP, attempt limiting.
3. Cross-tenant **writes** — PUT and DELETE against another user's todo (currently only GET is covered; both were verified correct manually during this audit, so these tests would lock in existing good behaviour).
4. JWT edge cases: expired, tampered signature, missing `sub`, token for a deleted user, token after password change.
5. `/health` returning a **non-200** status when a dependency is down.
6. Cache invalidation, including the `stats` path (BUG-001).
7. Detector behaviour when Elasticsearch is unreachable or returns 401 — assert the endpoint does **not** report success.
8. A migration test that runs `alembic upgrade head` against Postgres and compares the result to `Base.metadata`.
