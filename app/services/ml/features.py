"""Behaviour features for the anomaly model.

One sample = one source IP during one hour. Each sample summarises what that
address did in that hour across every security event index, using a single
Elasticsearch composite aggregation (paged), so no raw events are pulled into
the API process.
"""
import math
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from app.services.threat_detection import (
    ACTIONS_PRIVILEGE,
    ACTIONS_PROCESS_START,
    EVENT_INDICES,
)

# Order matters: it is the column order of the model's feature matrix.
FEATURE_NAMES = [
    "events",
    "auth_failures",
    "auth_successes",
    "failure_ratio",
    "distinct_users",
    "distinct_hosts",
    "distinct_destinations",
    "bytes_out",
    "process_events",
    "privilege_events",
    "max_rule_risk",
    "hour_sin",
    "hour_cos",
]

# Features reported back to analysts when they deviate from the baseline.
# Hour-of-day helps the model learn when activity is normal, but "hour_cos is
# 2.3 MADs off" is not a useful explanation.
EXPLAINABLE_FEATURES = FEATURE_NAMES[:-2]

COMPOSITE_PAGE_SIZE = 1000
MAX_PAGES = 50  # 50k entity-hours per window is ample for a single stack


@dataclass
class BehaviourSample:
    entity: str          # source IP
    window_start: str    # ISO-8601 start of the hour bucket (UTC)
    raw: Dict[str, float]
    vector: List[float]  # model input, in FEATURE_NAMES order


def build_query(start: datetime, end: datetime, after: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    composite: Dict[str, Any] = {
        "size": COMPOSITE_PAGE_SIZE,
        "sources": [
            {"entity": {"terms": {"field": "source.ip"}}},
            {"hour": {"date_histogram": {"field": "@timestamp", "fixed_interval": "1h"}}},
        ],
    }
    if after:
        composite["after"] = after
    return {
        "size": 0,
        "query": {
            "bool": {
                "filter": [
                    {"range": {"@timestamp": {"gte": start, "lt": end}}},
                    {"exists": {"field": "source.ip"}},
                ]
            }
        },
        "aggs": {
            "by_entity_hour": {
                "composite": composite,
                "aggs": {
                    "failures": {"filter": {"term": {"security_event.keyword": "authentication_failure"}}},
                    "successes": {"filter": {"term": {"security_event.keyword": "authentication_success"}}},
                    "users": {"cardinality": {"field": "user.name.keyword"}},
                    "emails": {"cardinality": {"field": "user.email.keyword"}},
                    "hosts": {"cardinality": {"field": "host.name.keyword"}},
                    "destinations": {"cardinality": {"field": "destination.ip"}},
                    "bytes_out": {"sum": {"field": "network.bytes_out"}},
                    "process": {
                        "filter": {
                            "bool": {
                                "should": [
                                    {"term": {"log_category.keyword": "powershell_execution"}},
                                    {"terms": {"event.action.keyword": ACTIONS_PROCESS_START}},
                                ],
                                "minimum_should_match": 1,
                            }
                        }
                    },
                    "privilege": {"filter": {"terms": {"event.action.keyword": ACTIONS_PRIVILEGE}}},
                    "max_risk": {"max": {"field": "risk_score"}},
                },
            }
        },
    }


def _value(bucket: Dict[str, Any], name: str) -> float:
    agg = bucket.get(name) or {}
    v = agg.get("value")
    if v is None:
        v = agg.get("doc_count", 0)
    return float(v or 0)


def sample_from_bucket(bucket: Dict[str, Any]) -> BehaviourSample:
    key = bucket["key"]
    hour_start = datetime.fromtimestamp(key["hour"] / 1000, tz=timezone.utc)

    failures = _value(bucket, "failures")
    successes = _value(bucket, "successes")
    raw = {
        "events": float(bucket.get("doc_count", 0)),
        "auth_failures": failures,
        "auth_successes": successes,
        "failure_ratio": failures / (failures + successes) if failures + successes else 0.0,
        "distinct_users": _value(bucket, "users") + _value(bucket, "emails"),
        "distinct_hosts": _value(bucket, "hosts"),
        "distinct_destinations": _value(bucket, "destinations"),
        "bytes_out": _value(bucket, "bytes_out"),
        "process_events": _value(bucket, "process"),
        "privilege_events": _value(bucket, "privilege"),
        "max_rule_risk": _value(bucket, "max_risk"),
        "hour_sin": math.sin(2 * math.pi * hour_start.hour / 24),
        "hour_cos": math.cos(2 * math.pi * hour_start.hour / 24),
    }

    # Counts are heavy-tailed (a scan produces thousands of events, normal use
    # a handful), so they enter the model on a log scale.
    vector = []
    for name in FEATURE_NAMES:
        v = raw[name]
        if name in ("failure_ratio", "hour_sin", "hour_cos"):
            vector.append(v)
        elif name == "max_rule_risk":
            vector.append(v / 10.0)
        else:
            vector.append(math.log1p(max(v, 0.0)))

    return BehaviourSample(
        entity=str(key["entity"]),
        window_start=hour_start.isoformat(),
        raw=raw,
        vector=vector,
    )


async def collect_samples(es, start: datetime, end: datetime) -> List[BehaviourSample]:
    """Page through the composite aggregation for [start, end)."""
    samples: List[BehaviourSample] = []
    after = None
    for _ in range(MAX_PAGES):
        result = await es.search(index=EVENT_INDICES, body=build_query(start, end, after))
        agg = (result.get("aggregations") or {}).get("by_entity_hour") or {}
        buckets = agg.get("buckets") or []
        samples.extend(sample_from_bucket(b) for b in buckets)
        after = agg.get("after_key")
        if not after or len(buckets) < COMPOSITE_PAGE_SIZE:
            break
    return samples
