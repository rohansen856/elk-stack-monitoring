# Performance and Reliability Audit

Only measurable or strongly-supported risks are listed. Code is not flagged merely for looking suboptimal.

## P1 — Blocking synchronous I/O inside async handlers (systemic)
**Severity: MEDIUM-HIGH · Confidence: HIGH**

FastAPI runs `async def` handlers on a single event loop. Every outbound integration in this codebase uses a **synchronous** client inside one:

| Call | Location | Blocks for |
|---|---|---|
| `redis` get/set/delete/keys | `app/cache.py:16,27,34,43` | a Redis round trip, on every todo request |
| `elasticsearch.index()` | `app/services/security_logger.py:74,156,213,279,334,393` | an ES round trip, **on every login** |
| `elasticsearch.search()` | `app/services/threat_detection.py` (8 methods) | an ES round trip per detector |
| `requests.post(timeout=10)` | `app/services/alerting.py:35` | **up to 10 s** per alert |
| `smtplib.SMTP(...)` + `sendmail` | `app/services/email_service.py:32-39` | **unbounded — no timeout set** |
| `redis.ping()` | `app/main.py:75` (`/health`) | a round trip per probe |

The worst case is `/forgot-password`: an unreachable or slow SMTP server blocks the **entire event loop** indefinitely, because `smtplib.SMTP` is constructed without a `timeout` argument. One request can stall every concurrent user. This is reachable unauthenticated and unthrottled (SEC-011).

**Fix:** `redis.asyncio`, `AsyncElasticsearch`, `httpx.AsyncClient`; move SMTP to a background queue; set explicit timeouts everywhere.

## P2 — Redis `KEYS` on every write
**Severity: MEDIUM · Confidence: HIGH** · `app/cache.py:41-49`, called from `app/api/todos.py:57,98,115`

`KEYS <pattern>` is O(N) over the **entire keyspace** and blocks the single-threaded Redis server while it runs. It executes on every todo create, update and delete. With a large cache this degrades every Redis client on the instance, not just this application.

**Fix:** `SCAN` with a cursor, or track each user's keys in a `SET` and delete by membership.

## P3 — Unbounded cache-key growth from user input
**Severity: MEDIUM · Confidence: HIGH** · `app/api/todos.py:25`

The raw `search` query parameter is interpolated into the cache key. An authenticated user can issue arbitrarily many distinct `search` values, each minting a new 60-second key. There is no cap on distinct keys and no rate limiting — a straightforward memory-exhaustion path against Redis.

**Fix:** hash the filter set into a fixed-width key component; bound cache cardinality per user.

## P4 — Connection leak on every health probe
**Severity: MEDIUM · Confidence: CONFIRMED** · `app/main.py:71`

```python
engine.connect()        # never closed, not a context manager
```
Each `/health` call checks out a pooled connection and never returns it. Kubernetes liveness **and** readiness probes both hit `/health` (`backend.yaml`) on a continuous interval, so the pool is exhausted on a predictable schedule, after which every database request blocks on pool checkout. Compounded by OPS-002: because `/health` returns 200 even when unhealthy, the probe will **never restart the pod** that is failing for exactly this reason.

**Fix:** `with engine.connect() as conn: ...`.

## P5 — No database connection-pool configuration
**Severity: MEDIUM · Confidence: HIGH** · `app/database.py:6`

`create_engine(settings.database_url)` uses defaults throughout — **no `pool_pre_ping`** (so stale connections after a Postgres restart or an idle-timeout surface as errors to users), no `pool_size`/`max_overflow` tuning, no `pool_recycle`, no statement timeout. `get_db` (`:12-17`) closes the session but never calls `rollback()` on exception, so a failed transaction can be returned to the pool mid-transaction.

**Fix:** `pool_pre_ping=True`, explicit sizing, `pool_recycle`, and rollback in the `finally` path.

## P6 — Missing and inefficient indexes
**Severity: MEDIUM · Confidence: HIGH**

- `password_reset_tokens.user_id` has **no index** (`app/models/password_reset.py:11`), yet `email_service.py:107-108` filters on it on every OTP verification — a sequential scan over a table that **grows forever** (P7).
- `password_reset_tokens.expires_at` has no index, used by the cleanup query.
- `todos` has single-column indexes but **no composite index** on `(owner_id, created_at)`, while `crud/todo.py:26` filters by `owner_id` and orders by `created_at DESC` on the primary list endpoint.
- `crud/todo.py:19-22` uses `ilike('%term%')` — a **leading-wildcard** match that cannot use a B-tree index. Full scan per search; no trigram index or full-text search configured.

## P7 — Unbounded table growth
**Severity: MEDIUM · Confidence: CONFIRMED** · `app/services/email_service.py:123-133`

`cleanup_expired_tokens` exists but is **never called** — no scheduler, no background task, no cron. Rows are also never deleted on successful redemption (only flagged `is_used`). Combined with unthrottled `/forgot-password` (SEC-011), an attacker can insert rows indefinitely — and each insert contends on the **globally unique** `token` index.

## P8 — Expensive unauthenticated operations
**Severity: MEDIUM · Confidence: CONFIRMED** · `app/api/security.py:38,110`

`/threats/scan` runs four Elasticsearch aggregations plus queued Slack and ES writes per call; `/hunt/comprehensive` runs four more. Both are unauthenticated (SEC-001) and unthrottled. `simulate/lateral-movement` performs **one ES write per element** of an unbounded `hosts` list (`:29,185-191`) — amplification from a single request.

Additionally `threat_detection.py:149` uses `{"wildcard": {"message": "*pattern*"}}` — a **leading-wildcard** query across the `security-*` index pattern, among the most expensive query shapes in Elasticsearch.

## P9 — Unbounded Prometheus label cardinality
**Severity: MEDIUM · Confidence: CONFIRMED** · `app/middleware.py:55,61`

`endpoint=request.url.path` uses the **raw** path, so `/api/v1/todos/1`, `/2`, `/3`… each create a new time series in both the counter and the histogram. Memory grows without bound in the process and in any scraping Prometheus. `/metrics` is unauthenticated (SEC-014), so an anonymous user can drive this deliberately by requesting arbitrary paths.

**Fix:** label with the matched route template (`request.scope["route"].path`).

## P10 — Silent truncation of hunt results
**Severity: LOW · Confidence: HIGH** · `app/services/threat_detection.py:367-381`

`hunt_privilege_escalation_ecs` issues a search with **no `size`**, so Elasticsearch returns the default 10 hits. Results are silently truncated with no indication to the caller — a detection tool that quietly drops findings.

## P11 — No backpressure, retries, or circuit breaking anywhere
**Severity: MEDIUM · Confidence: HIGH**

No retry logic, no exponential backoff, no circuit breaker, no bulkhead on any external call. Every failure is caught and swallowed (`return []`, `return None`, `return False`). The failure mode is therefore never a visible error — it is silent degradation (FUNC-001). There is no queue between the API and Elasticsearch, so a slow ES directly slows the API.

Conversely, there is also no retry **storm** risk, since nothing retries at all.

## P12 — Cache hits bypass response validation
**Severity: LOW · Confidence: HIGH** · `app/api/todos.py:30,74`

Cached payloads are returned directly, skipping `response_model` serialisation. After a schema change, stale cached entries (TTL 60-300 s) are served in the **old shape** while fresh responses use the new one — intermittent, hard-to-reproduce client errors during a deploy.

## Reliability summary

| Property | Status |
|---|---|
| Graceful degradation | Partially — failures are swallowed, but silently (anti-pattern) |
| Health signalling | **Broken** — `/health` always 200 (OPS-002) |
| Resource limits | Present in k8s; **absent entirely in docker-compose** |
| Connection pooling | Default, unconfigured, with a leak (P4, P5) |
| Backpressure / retries | None (P11) |
| Timeouts | Only on the Slack call; **SMTP has none** (P1) |
| Data growth control | None — no ILM, no cleanup (P7, G9) |
| Observability of failure | Logs only; no alerting (ALERT-001) |
