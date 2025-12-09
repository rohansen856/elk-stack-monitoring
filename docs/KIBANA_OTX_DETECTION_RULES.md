# Kibana Detection Rules for AlienVault OTX

This document provides working ES|QL queries for creating Kibana detection rules that trigger on AlienVault OTX threat intelligence matches.

## Rule 1: OTX Malicious IP Detection (194.11.246.101)

**Detection Logic**: Triggers when any connection is made to the specific OTX malicious IP with threat intelligence enrichment.

**ES|QL Query**:
```esql
FROM security-*
| WHERE destination.ip == "194.11.246.101"
  AND threat.intel.dest_ip.provider == "AlienVault OTX"
  AND @timestamp >= NOW() - 5 MINUTES
| EVAL
    threat_description = threat.intel.dest_ip.description,
    confidence = threat.intel.dest_ip.confidence,
    threat_type = threat.intel.dest_ip.type
| KEEP @timestamp, source.ip, destination.ip, threat_description, confidence, threat_type, message
```

**Kibana Rule Configuration**:
- **Name**: `OTX Malicious IP Detection - 194.11.246.101`
- **Index Pattern**: `security-*`
- **Rule Type**: ES|QL Query
- **Run Every**: 1 minute
- **Look Back**: 5 minutes
- **Threshold**: Count > 0
- **Severity**: Critical
- **Risk Score**: 95
- **Tags**: `OTX`, `Threat-Intel`, `C2`, `Malicious-IP`

**Expected Result**: Alert triggers when events match the IP and have OTX enrichment.

---

## Rule 2: All OTX Malicious IPs (Generic)

**Detection Logic**: Triggers on ANY connection to IPs flagged by AlienVault OTX with high confidence.

**ES|QL Query**:
```esql
FROM security-*
| WHERE threat.intel.dest_ip.provider == "AlienVault OTX"
  AND threat.intel.dest_ip.confidence >= 85
  AND @timestamp >= NOW() - 5 MINUTES
| EVAL
    threat_description = threat.intel.dest_ip.description,
    confidence = threat.intel.dest_ip.confidence,
    threat_level = CASE(
        threat.intel.dest_ip.confidence >= 95, "CRITICAL",
        threat.intel.dest_ip.confidence >= 90, "HIGH",
        "MEDIUM"
    )
| STATS
    connection_count = COUNT(*),
    unique_sources = COUNT_DISTINCT(source.ip),
    first_seen = MIN(@timestamp),
    last_seen = MAX(@timestamp)
  BY destination.ip, threat_description, confidence
| WHERE connection_count >= 1
| SORT confidence DESC, connection_count DESC
```

**Kibana Rule Configuration**:
- **Name**: `OTX High-Confidence Malicious IP Connections`
- **Index Pattern**: `security-*`
- **Rule Type**: ES|QL Query
- **Run Every**: 1 minute
- **Look Back**: 5 minutes
- **Threshold**: Count > 0
- **Severity**: High
- **Risk Score**: 85
- **Tags**: `OTX`, `Threat-Intel`, `Auto-Detection`

---

## Rule 3: OTX Malicious Domain Access

**Detection Logic**: Detects access to domains flagged by OTX based on message content.

**ES|QL Query**:
```esql
FROM security-*
| WHERE threat.intel.dest_domain.provider == "AlienVault OTX"
  AND @timestamp >= NOW() - 5 MINUTES
| EVAL
    threat_description = threat.intel.dest_domain.description,
    confidence = threat.intel.dest_domain.confidence,
    threat_level = CASE(
        threat.intel.dest_domain.confidence >= 90, "CRITICAL",
        "HIGH"
    )
| KEEP @timestamp, source.ip, destination.ip, threat_description, confidence, threat_level, message
```

**Kibana Rule Configuration**:
- **Name**: `OTX Malicious Domain Detection`
- **Index Pattern**: `security-*`
- **Rule Type**: ES|QL Query
- **Run Every**: 1 minute
- **Look Back**: 5 minutes
- **Threshold**: Count > 0
- **Severity**: High
- **Risk Score**: 80
- **Tags**: `OTX`, `Malicious-Domain`, `C2`, `Phishing`

---

## Rule 4: OTX Malware Hash Detection

**Detection Logic**: Triggers when known malicious file hashes from OTX are detected.

**ES|QL Query**:
```esql
FROM security-*
| WHERE threat.intel.file_hash.provider == "AlienVault OTX"
  AND @timestamp >= NOW() - 5 MINUTES
| EVAL
    malware_family = threat.intel.file_hash.description,
    confidence = threat.intel.file_hash.confidence,
    hash_value = threat.intel.file_hash.hash
| KEEP @timestamp, source.ip, malware_family, confidence, hash_value, message
```

**Kibana Rule Configuration**:
- **Name**: `OTX Malware Hash Detection`
- **Index Pattern**: `security-*`
- **Rule Type**: ES|QL Query
- **Run Every**: 1 minute
- **Look Back**: 5 minutes
- **Threshold**: Count > 0
- **Severity**: Critical
- **Risk Score**: 99
- **Tags**: `OTX`, `Malware`, `Ransomware`, `File-Hash`

---

## Testing Your Detection Rules

### Step 1: Send Test Events

Use the automated test script:

```bash
./scripts/test-detection-rules.sh
```

Or send manual test events:

```bash
# Test OTX IP detection
printf '{"@timestamp":"%s","source":{"ip":"192.168.1.100","port":54321},"destination":{"ip":"194.11.246.101","port":443},"message":"Connection to OTX malicious IP","event_type":"network_connection","severity":"critical"}\n' "$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')" | nc -w1 localhost 5000
```

### Step 2: Verify Event Enrichment

Wait 3-5 seconds for Logstash processing, then check:

```bash
# Verify event was enriched with OTX data
curl -s -u elastic:elastic123 "http://localhost:9200/security-*/_search?pretty&size=1" \
  -H 'Content-Type: application/json' -d '{
  "query": {
    "bool": {
      "must": [
        {"term": {"destination.ip": "194.11.246.101"}},
        {"exists": {"field": "threat.intel.dest_ip.provider"}},
        {"range": {"@timestamp": {"gte": "now-10m"}}}
      ]
    }
  },
  "sort": [{"@timestamp": "desc"}]
}' | grep -A20 "threat"
```

**Expected output**:
```json
"threat": {
  "intel": {
    "dest_ip": {
      "type": "malicious",
      "provider": "AlienVault OTX",
      "description": "Snakes by the riverbank",
      "confidence": 90
    }
  },
  "matched_value": "194.11.246.101",
  "matched_field": "destination.ip",
  "enriched": "true"
}
```

### Step 3: Check Detection Rule Execution

```bash
# Wait for rule to run (typically 1-2 minutes)
sleep 120

# Check if alert was generated
curl -s -u elastic:elastic123 "http://localhost:9200/.internal.alerts-*/_search?pretty" \
  -H 'Content-Type: application/json' -d '{
  "query": {
    "bool": {
      "must": [
        {"wildcard": {"kibana.alert.rule.name": "*OTX*"}},
        {"range": {"@timestamp": {"gte": "now-5m"}}}
      ]
    }
  },
  "size": 5,
  "sort": [{"@timestamp": "desc"}],
  "_source": ["kibana.alert.rule.name", "@timestamp", "kibana.alert.reason"]
}'
```

### Step 4: View Alerts in Kibana

1. **Open Kibana**: http://localhost:5601/app/security/alerts
2. **Filter by**:
   - Time range: Last 15 minutes
   - Rule name contains: "OTX"
3. **Expected fields**:
   - `kibana.alert.rule.name`: Your OTX rule name
   - `destination.ip`: 194.11.246.101
   - `kibana.alert.reason`: Alert details
   - `kibana.alert.severity`: Critical/High

---

## Troubleshooting

### Issue 1: Rule Not Triggering

**Check rule is enabled**:
```bash
curl -s -u elastic:elastic123 "http://localhost:9200/.kibana*/_search" \
  -H 'Content-Type: application/json' -d '{
  "query": {
    "bool": {
      "must": [
        {"term": {"type": "alert"}},
        {"match": {"alert.name": "OTX Malicious IP Detection"}}
      ]
    }
  },
  "_source": ["alert.enabled", "alert.executionStatus"]
}'
```

**Verify rule schedule**:
- Rule must be running at least every 5 minutes
- Look-back window must be >= run interval to avoid gaps

### Issue 2: Events Not Enriched

**Check Logstash enrichment pipeline**:
```bash
# View Logstash logs for enrichment
docker compose logs logstash --tail 50 | grep -i "threat\|enrich"

# Verify threat-intel indices exist
curl -s -u elastic:elastic123 "http://localhost:9200/_cat/indices?v" | grep threat-intel
```

**Expected indices**:
- `threat-intel-ips-*` - Contains OTX malicious IPs
- `threat-intel-domains-*` - Contains OTX malicious domains
- `threat-intel-hashes-*` - Contains OTX malware hashes

### Issue 3: Wrong Field Names

**Inspect actual event structure**:
```bash
curl -s -u elastic:elastic123 "http://localhost:9200/security-*/_search?size=1&q=194.11.246.101&pretty" \
  | grep -A50 "_source"
```

Match your ES|QL query field names to the actual indexed document structure.

---

## Best Practices

1. **Use specific index patterns**: `security-threats-*` instead of `security-*` for better performance
2. **Set appropriate look-back windows**: 5-15 minutes for real-time detection
3. **Adjust confidence thresholds**: Start at 85+ for OTX data
4. **Enable alert actions**: Configure email/Slack notifications for critical alerts
5. **Regular testing**: Run `./scripts/test-detection-rules.sh` weekly to ensure rules work
6. **Monitor rule execution**: Check `.kibana*` index for rule `executionStatus`

---

## Summary

✅ **Your OTX integration is working correctly!**

The threat intelligence enrichment pipeline is:
1. ✅ Receiving events via Logstash TCP (port 5000)
2. ✅ Enriching them with OTX threat data
3. ✅ Indexing to `security-threats-*` indices
4. ✅ Making them searchable via ES|QL

Now you just need to create the Kibana detection rules using the queries above to generate alerts when these enriched events appear.
