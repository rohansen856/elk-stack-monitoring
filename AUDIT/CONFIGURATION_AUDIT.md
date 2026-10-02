# Configuration and Deployment Audit

Guiding question per the brief: where does *"secure in theory"* diverge from *"secure in the actual deployed configuration"*?

## The headline: the primary deployment does not start

```
$ docker compose up -d
failed to parse docker-compose.yml: line 284: mapping key "depends_on" already defined at line 266
```

Committed in HEAD (`88746ef`). The `packetbeat` service declares `depends_on` twice — at `:266` (with service conditions) and `:284` (`- logstash`). Compose v2 treats a duplicate mapping key as a hard error. Removing the second block in a scratch copy makes the file parse cleanly, so it is the only YAML blocker (OPS-001).

Because of this, the full stack could not be brought up during this audit; Elasticsearch was validated standalone instead. All multi-service findings below are therefore **static**.

## docker-compose.yml

### Port exposure — 13 ports on 0.0.0.0
`docker compose config` on the repaired file resolves these published ports with **no `host_ip` binding anywhere**:

`80, 514, 3000, 5000, 5044, 5432, 5601, 6379, 8000, 9200, 9300, 9600, 12201`

This includes **Postgres (5432)**, **Redis (6379)** and **Elasticsearch (9200)**. Consequences:
- Redis runs with **no `requirepass`** (`:34-36`) — anyone on the host's network has full read/write on the cache.
- The backend is published on 8000, so nginx's rate limiting, routing and headers are **entirely bypassable**.
- On AWS the documented security group (ports 80 and 22 only) mitigates this. On a laptop, LAN or any host without that group, it does not.

### Secrets in the compose file
`ELASTIC_PASSWORD=elastic123` (`:52`), the same password inside the healthcheck (`:72`), and three Kibana encryption keys inline (`:91-93`). The encryption-key values contain non-hex characters, so they appear fabricated despite being presented as hex keys.

### Development configuration in the production path
- `app` runs **`uvicorn --reload`** (`:321-330`) — the auto-reload dev server — and bind-mounts the entire source tree (`.:/app`, `:320`), overriding the built image. There is no production run mode.
- `ENVIRONMENT` defaults to `development` (`config.py:11`), which leaves `/docs` and `/redoc` **enabled**.
- `migrate` also bind-mounts `.:/app` (`:300`).

### Operational gaps
- **No resource limits of any kind** — no `deploy.resources`, `mem_limit` or `cpus` on any of the 12 services. Elasticsearch, Logstash and Kibana in one 512 MB-heap stack with no ceilings will contend for host memory; the README asks for 8 GB RAM but nothing enforces a split.
- Healthchecks are missing on `app`, `migrate`, `setup-elk`, `filebeat`, `metricbeat` and `packetbeat`.
- `filebeat` and `metricbeat` run **`user: root`** (`:211`, `:234`) with `/var/log`, `/proc` and `/sys/fs/cgroup` mounted.
- `packetbeat` runs `network_mode: host` with `NET_ADMIN` + `NET_RAW` as root (`:255-261`).
- `setup-elk` uses `sed -i` to rewrite `kibana/kibana.yml` **through a bind mount** (`:141`), so running the stack **mutates a tracked file in the working tree**.

## Dockerfiles

| | Backend `Dockerfile` | `website/Dockerfile` |
|---|---|---|
| Base | `python:3.11-slim` | `node:22-alpine` |
| Stages | 1 | 4 (proper multi-stage) |
| User | **root — no `USER`** | **`USER nextjs` (1001)** ✔ |
| Build tools in final image | `gcc` retained (`:5-7`) | no |
| Install | `pip install --no-cache-dir` ✔ | **`npm i -f`** (not `npm ci`) |
| Healthcheck | none | none (compose supplies one) |

The backend image is the weaker of the two: it runs as root, retains a compiler, and — because `.dockerignore` omits `.env`, `*.pem` and `test.db` — `COPY . .` (`:12`) **bakes the live `.env` and `sentinel.pem` into image layers** (SEC-005). The frontend Dockerfile is notably better constructed.

## nginx

Validated with `nginx -t` in a container: syntactically valid (the only error was DNS resolution of upstream service names, an artifact of testing outside the compose network).

- **No TLS.** `listen 80;` only (`:32`) — no `ssl_certificate`, no 443 server, no HTTP→HTTPS redirect, no HSTS.
- **Rate limiting is mostly dead config.** Three zones declared (`:15-17`); only `api_limit` is applied, to `/backend/` (`:92`). `auth_limit` (5 r/s, clearly intended for login) and `general_limit` are **never referenced by any `location`** — directly contradicting `CLAUDE.md`.
- **Kibana is proxied at `/monitoring` with no auth directive** (`:113`). In compose this is backstopped by Kibana's own xpack login; in Kubernetes xpack is **disabled**, so there is nothing at all (SEC-008).
- **CORS conflict:** `Access-Control-Allow-Origin: *` on `/backend/` (`:106`) collides with the app's credentialed, hardcoded-origin CORS (`middleware.py:67-73`). Browsers reject `*` with credentials (CORS-001).
- Header inconsistency: `X-Frame-Options: SAMEORIGIN` here (`:43`) vs `DENY` in `next.config.mjs:24`. No CSP in either.
- `server_tokens off` ✔; `client_max_body_size 100M` (`:36`) is generous for an API with no large uploads.

## Kubernetes (`k8s/base/`) — static review only, never applied

- **Security is OFF**: `elasticsearch.yaml:71-72` and `kibana.yaml:12,43-44` set `xpack.security.enabled: "false"`, so the committed `ELASTIC_PASSWORD`/`KIBANA_PASSWORD` are unused and the cluster is open in-namespace (SEC-008).
- **Committed Secret** with the JWT signing key (`configmap.yaml:36-45`) and a plaintext `DATABASE_URL` in the **ConfigMap** (`:16`) (SEC-002). Token lifetime here is **30 days** (`:11`).
- **`logstash.yaml:81-84` mounts `hostPath: /home/rcsen/Documents/sih25/ps25238/logstash/pipeline`** — a developer's absolute path that does not match this repository's own name. The pod cannot start anywhere else (K8S-001).
- **PVs are `hostPath` under `/tmp`** (`postgres.yaml:14`, `redis.yaml:14`, `elasticsearch.yaml:14`) with `Retain` — node-local and lost to `/tmp` cleanup. Not durable storage.
- **Privileged and root workloads**: `elasticsearch.yaml:60-61` (`privileged: true`), `:55-56` (`runAsUser: 0`); `beats.yaml:71-72,232-233` (root) with `hostNetwork: true` (`:49,:209`) and cluster-wide get/list/watch RBAC (`:121-151,:282-314`). **No `securityContext` at all** on postgres, redis, logstash, kibana, backend, frontend or migrate-job. No PodSecurity admission, no NetworkPolicy anywhere (K8S-002).
- **`ingress.yaml` is excluded** from `kustomization.yaml:18` ("Commented out due to ingress controller issues"), so the documented ingress and the three LoadBalancer services are not deployed — making `docs/KUBERNETES_DEPLOYMENT.md:211`'s "Ingress deployed with SSL termination" doubly wrong (it is neither deployed nor TLS-enabled: `:8-9` disable ssl-redirect and there is no `tls:` block).
- Resource requests/limits **are** present on every workload ✔, and HPAs are configured (backend 2→10, frontend 2→8) ✔. Beats have a memory limit but **no CPU limit**.
- `frontend.yaml:39,45` probes `/api/health`, but `next.config.mjs:3` sets `basePath: '/frontend'`, so the served path is `/frontend/api/health` — **the probe likely 404s**. Flagged as probable, not confirmed (never deployed).
- Images are `:latest` with `imagePullPolicy` unset (defaults to `Always`) but are local builds only — pulls will fail on a multi-node cluster.
- `scripts/kind-config.yaml:12-27` maps host ports to NodePorts 30000-30002, but **no NodePort service exists** — all services are ClusterIP.

## Scripts

- `scripts/aws-ec2-setup.sh:84` runs **`docker compose down -v`** — destroying all named volumes (Postgres, Redis, Elasticsearch data) **with no confirmation prompt**. On re-running the setup script against an existing deployment this is silent data loss.
- Hardcoded `elastic123` in `aws-ec2-setup.sh:129,132`, `import-otx-threat-intel.sh:15,42`, `populate-threat-intel-data.sh:7`, and as a fallback in `setup-threat-intel-indices.sh:21`.
- `aws-ec2-setup.sh:181-182` **prints credentials to stdout**.
- `import-otx-threat-intel.sh:29` writes to the predictable, world-readable path `/tmp/otx_data.json`, then reads it back at `:37` — a symlink/race hazard on a shared host.
- `k8s-cleanup.sh:51-56` applies a manifest from an **unpinned `main` branch URL**; it also operates on whatever kube-context is active with no context assertion before deleting a namespace and PVs.
- **`scripts/apt-simulations-test/brute-force.sh` and `persistence.sh` make real authenticated API calls** and create real accounts with weak passwords (`:75-90`). These were deliberately **not executed** during this audit.

## Configuration defaults that matter

| Setting | Default | Risk |
|---|---|---|
| `environment` | `development` | leaves `/docs`, `/redoc` exposed |
| `elasticsearch_password` | **`"elastic123"`** | no `.env` key of this name exists, so the hardcoded default is what runs |
| `access_token_expire_minutes` | 30 / **43200** in k8s | 30-day tokens with no revocation |
| `algorithm` | `HS256`, env-overridable | a bad env value is honoured by both sign and verify |
| `log_level` | `INFO` | `getattr(logging, value)` raises `AttributeError` on a typo |
| Redis | **no password** | published on 0.0.0.0 |
