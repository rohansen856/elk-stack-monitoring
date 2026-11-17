#!/usr/bin/env python3
"""Seed a week of ordinary behaviour so the anomaly model has a baseline.

The behavioural anomaly model (app/services/anomaly_detection.py) learns what
"normal" looks like from the ML_BASELINE_DAYS before the scoring window. A fresh
stack has no history, so it reports "insufficient_baseline" until enough data
exists. For demos and testing, this script writes synthetic office activity
(logins with the occasional typo, small file transfers, mostly working hours)
for a set of internal hosts into the security indices, with past timestamps.

Usage:
    export ELASTICSEARCH_PASSWORD=...        # from .env (ELASTIC_PASSWORD)
    python3 scripts/seed-ml-baseline.py [--days 7] [--hosts 20]
Then retrain:  POST /api/v1/security/ml/train

Stdlib only. Writes to security-auth-logs-* and security-network-logs-*,
tagged `seeded_baseline: true` so the data can be told apart or deleted.
"""
import argparse
import base64
import json
import os
import random
import sys
import urllib.request
from datetime import datetime, timedelta, timezone


def bulk(es_url, auth, lines):
    req = urllib.request.Request(
        f"{es_url}/_bulk?refresh=true",
        data=("\n".join(lines) + "\n").encode(),
        headers={"Content-Type": "application/x-ndjson", "Authorization": auth},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        body = json.load(resp)
    if body.get("errors"):
        first = next(i for i in body["items"] if "error" in next(iter(i.values())))
        sys.exit(f"bulk indexing reported errors, first: {json.dumps(first)[:400]}")
    return len(body["items"])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--days", type=int, default=7)
    ap.add_argument("--hosts", type=int, default=20)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    es_url = os.environ.get("ELASTICSEARCH_URL", "http://localhost:9200")
    password = os.environ.get("ELASTICSEARCH_PASSWORD")
    if not password:
        sys.exit("ELASTICSEARCH_PASSWORD must be set (the ELASTIC_PASSWORD value from .env)")
    user = os.environ.get("ELASTICSEARCH_USER", "elastic")
    auth = "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()

    rng = random.Random(args.seed)
    now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
    # Stop two hours short of now so the seeded data never lands in the
    # scoring window and is always treated as baseline.
    end = now - timedelta(hours=2)
    start = end - timedelta(days=args.days)

    hosts = [(f"10.20.{i // 250}.{i % 250 + 10}", f"user{i:02d}@corp.example", f"WKS-{i:03d}") for i in range(args.hosts)]
    lines, total = [], 0
    hour = start
    while hour < end:
        working = hour.weekday() < 5 and 7 <= hour.hour <= 19
        for ip, email, host in hosts:
            if rng.random() > (0.85 if working else 0.08):
                continue  # quiet hour for this machine
            day = hour.strftime("%Y.%m.%d")
            for _ in range(rng.randint(1, 4)):
                ts = hour + timedelta(seconds=rng.randint(0, 3599))
                outcome = "authentication_failure" if rng.random() < 0.08 else "authentication_success"
                lines.append(json.dumps({"index": {"_index": f"security-auth-logs-{day}"}}))
                lines.append(json.dumps({
                    "@timestamp": ts.isoformat(),
                    "event": {"action": outcome, "category": ["authentication"], "dataset": "security.authentication"},
                    "security_event": outcome,
                    "user": {"email": email},
                    "source": {"ip": ip}, "src_ip": ip,
                    "host": {"name": "sentinel-app"},
                    "log_category": "authentication",
                    "message": f"{outcome}: {email}",
                    "seeded_baseline": True,
                }))
            for _ in range(rng.randint(0, 3)):
                ts = hour + timedelta(seconds=rng.randint(0, 3599))
                size = int(rng.lognormvariate(12, 1.2))  # median ~160 KB
                lines.append(json.dumps({"index": {"_index": f"security-network-logs-{day}"}}))
                lines.append(json.dumps({
                    "@timestamp": ts.isoformat(),
                    "event": {"action": "network_connection", "category": ["network"]},
                    "source": {"ip": ip}, "src_ip": ip,
                    "destination": {"ip": f"10.30.0.{rng.randint(2, 12)}"},
                    "network": {"bytes": size, "bytes_out": size, "direction": "internal"},
                    "host": {"name": host},
                    "log_category": "network_traffic",
                    "message": f"Network transfer: {ip} ({size} bytes)",
                    "seeded_baseline": True,
                }))
            if len(lines) >= 4000:
                total += bulk(es_url, auth, lines)
                lines = []
        hour += timedelta(hours=1)
    if lines:
        total += bulk(es_url, auth, lines)

    print(f"Seeded {total} baseline events for {args.hosts} hosts from {start.isoformat()} to {end.isoformat()}.")
    print("Retrain the model: POST /api/v1/security/ml/train")


if __name__ == "__main__":
    main()
