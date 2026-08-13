# Security Policy

## Reporting a vulnerability

Please report security issues privately. **Do not open a public issue.**

- Open a [GitHub security advisory](https://github.com/rohansen856/elk-stack-monitoring/security/advisories/new), or
- Email the maintainer listed on the repository profile with the subject
  `SECURITY: elk-stack-monitoring`.

Include where you can:

- affected component and version or commit,
- reproduction steps or a proof of concept,
- impact you believe it has,
- any suggested remediation.

### What to expect

| Stage | Target |
|---|---|
| Acknowledgement | 3 business days |
| Initial assessment | 10 business days |
| Fix or mitigation plan for confirmed high/critical issues | 30 days |

We will credit reporters in the advisory unless you ask us not to.

## Scope

In scope: this repository's application code, container and Kubernetes
manifests, and deployment scripts.

Out of scope: findings that require a pre-compromised host, denial of service
through raw volumetric traffic, and issues in third-party dependencies that
already have a published advisory (report those upstream, though we welcome a
note so we can bump the pin).

## Supported versions

Only the `master` branch is supported. There are no maintained release branches.

## Known posture

This project began as a learning and demonstration system. A full forensic
audit was carried out on 2026-10-07; the findings, including what was verified
and what remains unverified, are recorded in [`AUDIT/`](AUDIT/). Please read
`AUDIT/AUDIT_SUMMARY.md` before deploying this anywhere that matters.

Operators must, at minimum:

- set every credential in `.env` (the stack refuses to start otherwise),
- terminate TLS in front of the application,
- keep the Elasticsearch and Kibana security settings enabled,
- restrict network access to Kibana.

Historical implementation notes previously kept in this file now live in
[`docs/SECURITY_IMPLEMENTATION_NOTES.md`](docs/SECURITY_IMPLEMENTATION_NOTES.md).
