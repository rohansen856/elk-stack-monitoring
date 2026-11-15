# Runtime Verification - 2026-11-17

Follow-up to the 2026-10-07 audit. The earlier remediation commits were
checked against a **running stack**, not just the source. Every defect below
was reproduced at runtime before it was fixed, and every fix was re-verified
the same way.

## Method

- Full `docker compose` stack (16 containers) on a single Linux host, plus
  local-only mocks for the third-party services:
  - **Mailpit** for SMTP. It requires STARTTLS, and the app trusts a throwaway
    CA, so the production TLS-verification code path runs unchanged.
  - **An HTTP sink** in place of the Slack webhook.
  - **A dummy OTX key.**
- **API suite:** 51 checks of the documented behaviour, all through nginx over
  HTTPS. It covers auth, todos, the BFF routes, password reset by email, the
  security endpoints, Logstash ingestion and alerting.
- **Browser suite:** 15 checks in headless Chromium (Playwright). It covers
  register/login/logout, todos, the full password-reset UI and Kibana behind
  `/monitoring`.
- **Other checks:**
  - pytest, ruff and bandit;
  - `tsc`, eslint and `next build`;
  - Logstash `--config.test_and_exit`;
  - the APT simulation scripts and the threat-intel scripts;
  - importing the Kibana rules and executing them.

**Baseline before the fixes: 38/51 API checks passing.**

## Defects confirmed at runtime, and fixed

### Detection pipeline (the product's core function)

| # | Defect | Evidence | Fix |
|---|---|---|---|
| 1 | High-risk alerts were never stored: `create_elasticsearch_alert` did not await the async `index()` call | `security-alerts-*` stayed at 0 docs after a scan reported 3 high-risk threats | `app/services/alerting.py` |
| 2 | The privilege-escalation hunt returned every event from the last hour | 499 of its 500 results were unrelated events | `minimum_should_match: 1` |
| 3 | PowerShell detection never matched `Invoke-Expression`, `IEX`, `DownloadString`, `EncodedCommand` or `-enc`. It used a case-sensitive wildcard on an analysed text field. | Only `noprofile` fired | Phrase matching in `threat_detection.py` |
| 4 | Every Logstash-parsed field was written as a literal dotted key (`"source.ip"`), so Windows events were never classified and syslog events got no GeoIP or threat-intel enrichment | The Windows doc had `event.id` as a top-level string key and no `event.action` | Bracket field references |
| 5 | Logstash events had no `src_ip`, so SSH, Windows and Cisco brute force was invisible to the detector | Brute-force results did not include the attacker IP | Copy `source.ip` to `src_ip` |
| 6 | All application logs were rejected by Elasticsearch: python-logstash sends `host` as a string, which conflicts with the ECS `host` object. The `type`-based branch was dead code. | 162 HTTP 400 `Could not index event` responses; zero app logs stored | Tag-based branch; `host` moved to `host.name` |
| 7 | Packetbeat traffic landed in `system-logs-*`, so data-exfiltration detection never saw real traffic | 0 Packetbeat docs in `security-network-logs-*` | Route Packetbeat via its tag; set `network.bytes_out` |
| 8 | `source.ip`, `destination.ip` and `src_ip` were dynamically mapped as `text`, so IP ranges compared as strings and aggregations failed | The `_mapping` API showed `text` | `sentinel-security-events` index template (setup-elk) |
| 9 | Enrichment copies (`security-threats-*`) and alerts (`security-alerts-*`) matched `security-*` and were counted twice | (design) | Detectors exclude derived indices |
| 10 | `threat-intel-test.sh` sent pretty-printed JSON to a `json_lines` input, so every line became a `_jsonparsefailure` | 416 parse failures; 0 threat-intel matches | One event per line; now 20 matches |
| 11 | The API-based APT simulation scripts called authenticated endpoints anonymously, so every request got 401 | (since the SEC-001 fix) | `scripts/apt-simulations-test/_auth.sh` |

### Client IP and rate limiting

| # | Defect | Evidence | Fix |
|---|---|---|---|
| 12 | Every nginx location set its own `proxy_set_header`. That silently dropped the inherited `X-Forwarded-For` and `X-Real-IP`. | Security events showed the nginx and frontend container IPs | Headers declared once, at `http` level |
| 13 | Uvicorn trusted forwarding headers only from 127.0.0.1, and the BFF did not forward the client address. Per-IP limits became site-wide: 3 forgot-password calls per minute for everyone. | (as above) | `FORWARDED_ALLOW_IPS`, `backendFetch()`, nginx overwrites XFF |

After the fix:
- One client gets ten 401s, then a 429.
- A forged `X-Forwarded-For` header is still rate-limited (429).
- A second client is unaffected.
- Security events record the real client IP.

### Frontend

| # | Defect | Fix |
|---|---|---|
| 14 | The reset form accepted exactly 6 digits while the backend issues 8, so no reset could ever complete | Code length follows `OTP_LENGTH`; the browser test completes a reset |
| 15 | FastAPI 422 `detail` arrays reached the UI as "[object Object]"; the UI used an 8-character password minimum against the backend's 12 | `errorDetail()`, `MIN_PASSWORD_LENGTH` |
| 16 | `/api/todos/stats` had no handler (HTTP 405) | Added the route |
| 17 | A stale session cookie was never cleared, causing a /login <-> /dashboard redirect loop | `/api/auth/me` clears the cookie on a 401 |
| 18 | Client `fetch()` calls ignored the basePath and worked only through an nginx rewrite. Proxy redirects also dropped the basePath and relied on an nginx `proxy_redirect`, which would have double-prefixed correct redirects. | `apiPath()`, `nextUrl.clone()`; both nginx workarounds removed |
| 19 | No `<Toaster/>` was mounted, failed mutations caused unhandled rejections, and logout raced the redirect | Fixed |
| 20 | `npm run lint` could not run (no ESLint 9 config) | Added `eslint.config.mjs`; lint added to CI |

### Infrastructure, CI and scripts

| # | Defect | Fix |
|---|---|---|
| 21 | `pip install -r requirements.txt && pytest` failed (no `fakeredis`); tests made real connections to `:9200` | `requirements-dev.txt`; fake ES client in `conftest.py` |
| 22 | Unpinned ruff 0.17 reported 182 new findings (CI red on an unchanged tree); bandit B104 failed CI | `ruff.toml` pinned; targeted `nosec` |
| 23 | setup-elk's mapping-less `filebeat` template shadowed Filebeat's ECS template, and a failed `kibana_system` password only warned | Template removed; setup-elk exits non-zero on failure |
| 24 | Two rubydebug stdout outputs wrote every event into unrotated Docker logs | Removed |
| 25 | Filebeat had two top-level `processors:` keys, so the first block was silently dropped | Merged |
| 26 | GELF was published over TCP only; the `db` healthcheck used a non-existent role; Metricbeat reported container metrics, not host metrics | Fixed |
| 27 | The OTX Kibana rules could not be imported: non-UUID ids, a wrong migration version, and no rule type | Fixed. All 54 rules import, and the 4 OTX rules execute. |
| 28 | The StrongPity rule used `LIKE` on `source.ip`, which fails once the field is correctly mapped as `ip` | `IS NOT NULL` |
| 29 | `setup-threat-intel-indices.sh` printed the Elasticsearch password | Prints the variable name instead |
| 30 | `aws-ec2-setup.sh`: its URL substitution was a no-op, it never bound nginx publicly, it aborted at step 6.5, and its health checks could never fail | Fixed |

### Disproved during the run

The proxy redirect looked like it already preserved the basePath. In fact, an
nginx `proxy_redirect` was masking the bug (see #18).

## Final verification

- API suite **51/51** and browser suite **15/15**. Both pass on a stack
  recreated from empty volumes (`docker compose down -v && up -d --build`).
- pytest **62 passed** (6 new regression tests); ruff and bandit clean.
- `tsc`, eslint and `next build` clean.
- Every intermediate Logstash pipeline in the commit history passes
  `--config.test_and_exit`.
- APT simulations produce 13 threats (12 high-risk) across brute force,
  exfiltration, PowerShell and kill-chain, and the hunts find lateral movement
  (3 users) and privilege escalation (4 events).
- Kibana rules: 51 of 54 execute cleanly after the simulations; 3 remain in
  error (see below).

## Still open (not changed in this pass)

- **No security views in the web UI.** Threat detection is reachable only
  through the API and Kibana. The README previously claimed otherwise and has
  been corrected.
- **No role-based access.** Any self-registered user can call
  `/api/v1/security/*`, and in non-production environments `/simulate/*` too.
- **Blocking calls in async handlers.** SQLAlchemy and bcrypt run
  synchronously inside async handlers (R2.1).
- **Migration drift.** The initial migration declares unbounded `VARCHAR`
  columns where the models specify lengths.
- **Three Kibana rules error, all from ES|QL type conflicts in the rules
  themselves.** They do not affect the API detectors.
  - `user.name` is `text` in Sentinel indices but `keyword` in Filebeat's ECS
    data stream.
  - A `COALESCE` mixes `text` and `keyword`.
  - `threat_name` exists only once Palo Alto events have been ingested.
- **Upgraded clusters keep old mappings until rollover.** Indices created
  before the new template keep `text` IP fields until the daily rollover, so
  aggregations over those shards fail partially until then.
- **Large first-start backfill.** Filebeat ingests the host's current log
  files on first start; on the test host that was ~865k syslog lines (~180 MB).
  `ignore_older` does not help, because it judges files by modification time.
- **Kibana's own CSP error.** Kibana 8.11 logs an inline-script CSP error in
  the browser console. It appears identically with nginx bypassed.
- **Root-owned certificates.** `cert-init` writes them into the working tree's
  `nginx/certs/`.
- **Secrets in git history.** Credentials from before 2026-10-07 are still in
  history (rotation was documented; history was not rewritten).
