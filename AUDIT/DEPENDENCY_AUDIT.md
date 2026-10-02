# Dependency and Supply-Chain Audit

Scanners used: `pip-audit` (Python), `npm audit --package-lock-only` (Node), `gitleaks` (secrets). **Scanner output was not taken at face value** — every high-severity item was checked against actual usage before being reported.

## Python — `requirements.txt`

**50 known vulnerabilities across 9 packages.** Triaged by reachability:

### Reachable, pre-authentication (highest priority)
| Package | Pinned | Advisories | Reachability |
|---|---|---|---|
| `python-multipart` | 0.0.6 | 8 (incl. PYSEC-2024-38 ReDoS) | **Confirmed reachable.** Parses the login form — `OAuth2PasswordRequestForm` at `app/api/users.py:41`, an unauthenticated endpoint. Fixed in 0.0.7+ / 0.0.31 |
| `starlette` | 0.27.0 | 10 | **Confirmed reachable.** Same multipart path plus all request handling. Fixed in 0.40.0+ |
| `fastapi` | 0.104.1 | PYSEC-2024-38 | Same multipart DoS. Fixed in 0.109.1 |

An unauthenticated attacker can reach these by posting to `/api/v1/users/login`. Combined with the complete absence of rate limiting (SEC-011), a DoS requires no special effort.

### Reachable, post-authentication
| Package | Pinned | Advisory | Assessment |
|---|---|---|---|
| `python-jose` | 3.3.0 | PYSEC-2024-233 | JWT decode DoS via a crafted token. `jwt.decode` runs on **every** authenticated request (`auth.py:36`). Fixed in 3.4.0 |
| `python-jose` | 3.3.0 | PYSEC-2025-185 | No fix version published |

### Investigated and found NOT exploitable here
| Package | Advisory | Why not |
|---|---|---|
| `python-jose` | PYSEC-2024-232 — algorithm confusion | `app/api/auth.py:36` passes an explicit `algorithms=[settings.algorithm]` list, so the attacker cannot select the verification algorithm. **Disproved.** |
| `ecdsa` | PYSEC-2026-1325 (Minerva timing) | Transitive via `python-jose[cryptography]`; the application uses **HS256 only**, so no ECDSA path executes. No fix version exists upstream. |
| `requests` | 3 advisories | Used only by `alerting.py:35`, which posts to a hardcoded placeholder URL that resolves to nothing (ALERT-001). Reachability is effectively nil **today** — but becomes real the moment alerting is fixed, so it should still be upgraded. |
| `pytest`, `python-dotenv` | 3 advisories | Development-time only; not in the runtime path. |
| `anyio` | 2 advisories | Transitive under starlette; upgrading starlette addresses it. |

### Dependency-declaration defects
- **`passlib[bcrypt]==1.7.4` is declared but never imported.** `grep -rn passlib app/` returns nothing. It is dead weight — and `docs/DATABASE_ARCHITECTURE.md:441-450` documents the system as if passlib were in use (D8).
- **`bcrypt` is imported (`app/crud/user.py:2`) but is not a declared direct dependency.** It is present only as a `passlib` extra. Removing `passlib` — the obvious cleanup — would **break password hashing**. This is a live trap.
- `elasticsearch==8.11.0` is used with the deprecated `body=` keyword throughout `threat_detection.py` (7 sites), which is removed in later 8.x clients — upgrading will break these calls.
- `python-logstash==0.4.8` was last released in 2016 and is unmaintained; it provides the plaintext, unauthenticated TCP transport discussed in G8.

### Version targeting is inconsistent
`.python-version` pins **3.12.6**, `Dockerfile:1` uses **python:3.11-slim**, and the host used for this audit runs **3.14.6**. `datetime.utcnow()` (used in `auth.py` and `email_service.py`) is deprecated from 3.12 onward.

## Node — `website/`

**8 vulnerabilities: 1 critical, 6 high, 1 moderate.**

| Package | Severity | Assessment |
|---|---|---|
| `next@16.0.3` | **critical** | 35 advisories. **Reachable:** GHSA-9qr9-h5gf-34mp, critical RCE in the React flight protocol — the App Router RSC path is in active use. Also several middleware/proxy-bypass advisories that touch `middleware.ts`, though their impact is limited because that middleware is only a UX gate (the backend JWT check is authoritative). |
| `next` (image optimizer) | critical | **NOT reachable — verified.** `next.config.mjs:11` sets `images.unoptimized: true`, disabling the Image Optimization API, which neutralises the AVIF RCE (GHSA-2xp9-vwfh-vxw4) and the optimizer DoS advisories. |
| `next` (Server Actions) | high/moderate | **NOT reachable — verified.** `grep -rn "use server"` across `app/`, `components/`, `lib/` returns nothing. |
| `next` (Windows RCE) | critical | Not applicable — containers are `node:22-alpine`. |
| `sharp`, `postcss`, `source-map-js`, `nanoid`, `browserslist`, `lodash` | high | Transitive under `next`; `lodash` carries a `_.template` code-injection advisory — the application does not call `_.template`, so reachability is low. |

### Supply-chain integrity problems
- **`npm ci` fails outright:**
  ```
  ERESOLVE could not resolve
  While resolving: vaul@0.9.9
  Found: react@19.2.0
  peer react@"^16.8 || ^17.0 || ^18.0" from vaul@0.9.9
  ```
  `website/Dockerfile:9` works around this with **`npm i -f --production=false`**, which overrides peer resolution and ships `vaul` against an unsupported React major. This is undeclared technical risk in the production image.
- **Four dependencies are pinned to the floating tag `latest`** — `@vercel/analytics` (`:40`), `immer` (`:47`), `use-sync-external-store` (`:61`), `zustand` (`:64`). Two builds of the same commit can produce different dependency trees. Combined with `npm i -f` (which does not honour the lockfile), **the production image is not reproducible** and a compromised upstream release would be pulled automatically.
- `website/package.json` declares a `lint` script but **no `eslint` dependency**.
- No `website/.dockerignore`, so `COPY . .` in the builder stage would include `website/.env` if present.

## Secrets scanning

`gitleaks detect` over all 102 commits: **97 raw hits**, triaged to:
- **71 `curl-auth-user`** — `curl -u elastic:elastic123` in documentation and scripts. Real credentials, but all the same known value (SEC-004).
- **19 `generic-api-key`** — Kibana encryption keys (`docker-compose.yml:91-93`, `k8s/base/kibana.yaml:13-15`, `docs/KIBANA.md:78-80`), `kibana/kibana.yml:6`, the k8s `SECRET_KEY`, and `docs/SECURITY_CREDENTIALS.md:19`.
- **2 `kubernetes-secret-yaml`** — `k8s/base/configmap.yaml:36` (SEC-002), independently corroborating that finding.
- **5 `curl-auth-header`** — `Authorization: Bearer <placeholder>` examples in `README.md`. **False positives.**
- One example JWT in `docs/API_DOCUMENTATION.md:85`. **False positive.**

**Verified clean:** the root `.env` and `sentinel.pem` were **never committed**; the historical `website/.env` (`ae094f7`) contained only non-secret URLs.

## Recommendations, in order

1. Upgrade `python-multipart`, `starlette` and `fastapi` — unauthenticated DoS reachable today.
2. Upgrade `python-jose` to 3.4.0.
3. Upgrade `next` to a release patching the flight-protocol RCE.
4. Add `bcrypt` as an explicit dependency, then remove the unused `passlib`. **In that order** — the reverse breaks authentication.
5. Resolve the `vaul`/React-19 conflict and restore `npm ci`; replace all four `latest` pins with exact versions.
6. Add `pip-audit` and `npm audit` to a CI pipeline — there is currently no CI at all.
