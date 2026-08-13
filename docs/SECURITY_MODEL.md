# Security Model

Behaviour an operator, security reviewer or integrator needs to know. Everything
here describes the code as it actually is; where behaviour changed during the
2026-10-07 remediation, the previous behaviour is noted so older deployments can
be recognised.

---

## Authentication

| Property | Value |
|---|---|
| Scheme | JWT bearer, HS256 |
| Claims | `sub` (email), `exp`, `iat`, `jti`, `pwd_fp` |
| Lifetime | `ACCESS_TOKEN_EXPIRE_MINUTES`, default **30 minutes** |
| Refresh tokens | **None.** Re-authenticate when the token expires |
| Logout | `POST /api/auth/logout` (frontend) clears the session cookie |
| Revocation | Via `pwd_fp` only - see below |

### Token invalidation on credential change

Every token carries `pwd_fp`, a truncated SHA-256 digest of the user's stored
password hash. It is re-checked on every request, so **changing a password
immediately invalidates every token issued before it**, including one changed
directly in the database.

There is no general-purpose revocation list: a token that is stolen and whose
password is *not* changed remains valid until `exp`. Keep the lifetime short.

> Before remediation there was no refresh, logout or revocation of any kind, and
> a token survived a password reset (AUDIT SEC-012).

### Password policy

- Minimum **12 characters**, maximum 128 (bcrypt truncates at 72 bytes).
- Hashed with bcrypt, cost 12.
- There is **no** email verification: `is_active` defaults to true and an
  account is usable immediately after registration.

### Session storage (frontend)

The JWT is held in an **httpOnly** cookie. Client JavaScript cannot read it.
Browser requests go to same-origin Next.js route handlers, which read the cookie
server-side and attach the `Authorization` header when calling the API, so the
token never reaches client code.

`middleware.ts` only checks that the cookie is *present*; it is a navigation
convenience, **not** a security boundary. The backend's JWT check is
authoritative.

---

## Authorization

There is **no role model**. Every authenticated user is equivalent; there is no
admin concept.

| Area | Rule |
|---|---|
| `/api/v1/todos/*` | Every query is scoped by `owner_id`; another user's todo returns 404 for read, update and delete |
| `/api/v1/security/*` | Requires authentication. No finer-grained permission |
| `/metrics` | Requires `METRICS_TOKEN` as a bearer token, or a valid user JWT |
| `/health` | Unauthenticated by design (probes) |

---

## The `/api/v1/security/simulate/*` endpoints

Four endpoints **write caller-supplied events directly into Elasticsearch**:

```
POST /api/v1/security/simulate/powershell
POST /api/v1/security/simulate/privilege-escalation
POST /api/v1/security/simulate/lateral-movement
POST /api/v1/security/simulate/data-exfiltration
```

They exist to generate demo and test telemetry. The event's `user`, `host`,
`command` and `source_ip` come from the request body, so anyone who can reach
them can **fabricate security events that the detectors then read back as
genuine**.

Controls:
- authentication is required;
- they return **404 when `ENVIRONMENT=production`**;
- `simulate/lateral-movement` accepts at most 50 hosts per request.

> Before remediation all 14 security endpoints, these four included, were
> reachable with no credentials at all (AUDIT SEC-001).

---

## Rate limiting

Two layers, because the backend port can be reached directly if it is published.

**nginx** (`nginx/nginx.conf`):

| Zone | Rate | Applied to |
|---|---|---|
| `auth_limit` | 5 r/s, burst 5 | `/backend/api/v1/users/{login,register,forgot-password,reset-password}` |
| `api_limit` | 10 r/s, burst 20 | everything else under `/backend/` |
| `general_limit` | 20 r/s, burst 40 | `/frontend`, `/api/` |

**Application** (`app/rate_limit.py`, slowapi, per client IP):

| Endpoint | Limit |
|---|---|
| `POST /api/v1/users/login` | 10/minute |
| `POST /api/v1/users/register` | 5/minute |
| `POST /api/v1/users/forgot-password` | 3/minute |
| `POST /api/v1/users/reset-password` | 10/minute |

Exceeding a limit returns **429**.

---

## Password reset (OTP)

| Property | Value |
|---|---|
| Generation | `secrets.choice` over digits - CSPRNG |
| Length | `OTP_LENGTH`, default 8 |
| Validity | `OTP_EXPIRE_MINUTES`, default 15 minutes |
| Storage | HMAC-SHA256 of the OTP keyed with `SECRET_KEY`; the code itself is never stored |
| Concurrency | Issuing a new OTP **invalidates all outstanding ones** - at most one is valid |
| Attempt limit | `OTP_MAX_ATTEMPTS`, default 5, then the OTP is burned and the endpoint returns **423 Locked** |
| Single use | Yes |
| Cross-account | An OTP is only valid for the account it was issued to |
| Cleanup | Expired rows are deleted hourly by a background task |

`POST /forgot-password` always returns the **same 200 response** whether or not
the address exists and whether or not delivery succeeded, so it cannot be used
to enumerate accounts.

> Before remediation the OTP was 6 digits from `random.choices` (Mersenne
> Twister), stored in cleartext, with unlimited attempts and multiple codes
> valid simultaneously; a known address returned 500 while an unknown one
> returned 200 (AUDIT SEC-003, SEC-007).

---

## Detection failure modes

This matters more than any individual detection rule.

`GET /api/v1/security/threats/*` and `/hunt/*` distinguish three cases:

| Situation | Response |
|---|---|
| Query ran, nothing matched | `200 {"threats": [], "count": 0}` |
| Index does not exist yet (nothing ingested) | `200 {"threats": [], "count": 0}` |
| Elasticsearch unreachable, or rejects our credentials | **`503 {"status": "degraded", ...}`** |

**An empty 200 means "we looked and found nothing". It never means "the query
failed".**

> Before remediation the detector built its Elasticsearch client with no
> credentials while the writer authenticated, so against a security-enabled
> cluster every query returned 401, was swallowed, and the endpoint answered
> `200 {"threats": []}` - indistinguishable from a clean result (AUDIT FUNC-001).

---

## Alerting

Slack alerting requires `SLACK_WEBHOOK_URL`. When it is unset the service logs a
warning **once** at first use and reports delivery failure; it does not silently
pretend to have sent anything.

> Before remediation the webhook defaulted to a placeholder URL, the configured
> value was never read, and failures were swallowed - alerts reached nobody
> (AUDIT ALERT-001).

---

## Logging and data handling

Application logs are shipped to Logstash over **plaintext TCP** and indexed into
Elasticsearch. Be aware of what that carries:

- email addresses on registration, login and password reset;
- full request URLs **including query strings** (so `?search=` content);
- source IPs and user agents;
- command lines in simulated/ingested security events.

Validation errors are sanitised: the rejected **value** is stripped from both the
API response and the log record, so a mistyped password or OTP is not written to
the SIEM. Database exception text is logged server-side but never returned.

Indices written by the application (daily):
`security-auth-logs-*`, `security-api-logs-*`, `security-powershell-logs-*`,
`security-network-logs-*`, `security-privilege-logs-*`, `security-lateral-logs-*`,
`security-alerts-*`.

**There is no index lifecycle or retention policy.** These grow until you add
one.

---

## Network exposure

`docker-compose.yml` publishes only **nginx** (80, 443) on all interfaces. Every
other service binds to `127.0.0.1`, so Postgres, Redis, Elasticsearch, Kibana and
the backend are not reachable from the network by default.

Redis requires a password (`REDIS_PASSWORD`). The stack **refuses to start**
if `REDIS_PASSWORD`, `ELASTIC_PASSWORD` or `KIBANA_SYSTEM_PASSWORD` is unset -
there are deliberately no default credentials.

> Before remediation 13 ports were published on `0.0.0.0`, Redis had no password,
> and `elastic123` was the hardcoded default throughout (AUDIT CFG-001, SEC-004).

---

## Transport security

nginx terminates TLS on 443 and redirects 80 → 443, with HSTS and a CSP. A
development certificate must be generated before first start:

```bash
mkdir -p nginx/certs
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout nginx/certs/server.key -out nginx/certs/server.crt \
  -days 365 -subj "/CN=localhost"
```

Use a real certificate in production, or terminate TLS in front of nginx
(AWS ALB + ACM, or Let's Encrypt).

Internal hops - Elasticsearch, Logstash, the beats - are **not** TLS-encrypted by
default. Keep them on a trusted network segment.

---

## Packetbeat

Packetbeat captures **metadata only**: `send_request`, `send_response` and
`send_certificates` are all disabled.

> Before remediation they were enabled on ports 80, 8080, 8002, 5000 and 9200,
> which captured full login request bodies (username and password),
> `Authorization` headers and reset OTPs, and shipped them unencrypted to
> Logstash to be indexed (AUDIT SEC-009).

---

## Known limitations

- No MFA.
- No email verification.
- No account lockout on repeated failed **logins** (rate limiting only).
- No audit trail for password changes beyond application logs.
- No RBAC.
- No ILM/retention on security indices.
- Internal ELK traffic is unencrypted.
- `python-jose` and `ecdsa` carry advisories with no upstream fix; the ECDSA
  path is not reachable because only HS256 is used.
