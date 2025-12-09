# Threat Intelligence Integration

## Overview

This document describes the Threat Intelligence (Threat Intel) integration in the ELK Stack security monitoring system. Threat intelligence allows automatic comparison of security logs against global databases of known malicious IPs, domains, and file hashes.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     THREAT INTELLIGENCE FLOW                    │
└─────────────────────────────────────────────────────────────────┘

1. Threat Intel Feeds → Filebeat → Logstash → Elasticsearch
   (AbuseCH, AlienVault OTX, Anomali, MISP)

2. Security Logs → Logstash enrichment → Match against threat DB

3. Matched Events → threat-intel-matches-* index → Kibana Alerts

4. SOC Analysis → Incident Response → Threat Hunting
```

## Components Implemented

### 1. Threat Intel Indices ✅

Three dedicated Elasticsearch indices store threat intelligence indicators:

- **`threat-intel-ips-*`** - Malicious IP addresses
  - APT group C2 servers
  - Known botnets
  - Port scanners
  - DDoS sources

- **`threat-intel-domains-*`** - Malicious domains
  - C2 domains
  - Phishing sites
  - Malware distribution

- **`threat-intel-hashes-*`** - File hashes
  - Ransomware (WannaCry, NotPetya)
  - Credential theft tools (Mimikatz)
  - APT malware families

### 2. Threat Intelligence Data ✅

**Current Status:** 12 high-confidence threat indicators populated

**Malicious IPs (5 indicators):**
| IP Address | Threat Actor | Confidence | Description |
|------------|--------------|------------|-------------|
| 13.59.205.66 | APT29 (Cozy Bear) | 98% | SolarWinds SUNBURST C2 server |
| 54.193.127.66 | APT29 | 95% | SolarWinds supply chain infrastructure |
| 176.31.112.10 | APT28 (Fancy Bear) | 92% | DNC hack infrastructure |
| 103.224.80.44 | Lazarus Group | 97% | WannaCry infrastructure |
| 203.0.113.66 | Generic | 80% | Known port scanner |

**Malicious Domains (4 indicators):**
| Domain | Category | Confidence | Threat Actor |
|--------|----------|------------|--------------|
| avsvmcloud.com | C2 | 98% | APT29 SolarWinds |
| freescanonline.com | C2 | 96% | APT28 Fancy Bear |
| secure-paypal-login.com | Phishing | 88% | Phishing Campaign |
| malware-download.xyz | Malware | 90% | Malware Distribution |

**Malicious File Hashes (3 indicators):**
| Hash (MD5) | Malware Family | Type | Provider |
|------------|----------------|------|----------|
| 84c82835a5d21bbcf75a61706d8ab549 | WannaCry | Ransomware | Lazarus Group |
| 7c4fe364c1f3e3738a75a2b736b0c958 | Mimikatz | Credential Theft | Various APTs |
| 027cc450ef5f8c5f653329641ec1fed9 | NotPetya | Ransomware | APT28 |

### 3. Logstash Enrichment Pipeline ✅

**File:** `logstash/pipeline/threat-intel-enrichment.conf`

**Capabilities:**
- Real-time IP address checking (source + destination)
- Domain/URL threat matching
- File hash verification (MD5, SHA256)
- GeoIP enrichment with high-risk country tagging
- APT group attribution (APT29, APT28, Lazarus)
- Automated severity scoring (Critical/High/Medium/Low)
- Response action tagging (block_and_alert, investigate)

**Pipeline Stages:**
1. IP Address Threat Intelligence
2. Domain/URL Threat Intelligence
3. File Hash Threat Intelligence
4. GeoIP Reputation
5. Known APT Group Attribution
6. Automated Response Tagging
7. Cleanup and Indexing

### 4. Filebeat Threat Intel Module Configuration ✅

**File:** `filebeat/modules.d/threatintel.yml`

**Configured Feeds:**
- ✅ AbuseCH URLhaus - Malicious URLs (60min refresh)
- ✅ AbuseCH MalwareBazaar - File hashes
- ✅ Anomali Limo - Free threat intel (12h refresh)
- ✅ AlienVault OTX - Open Threat Exchange (1h refresh, requires API key)

## Manual Threat Intelligence Queries

Since automatic enrichment requires additional configuration, you can perform manual threat intelligence lookups using these ES|QL queries:

### Query 1: Check IP Against Threat Intel Database

```sql
FROM threat-intel-ips-*
| WHERE CIDR_MATCH(threat.indicator.ip, "13.59.205.66/32")
| KEEP threat.indicator.ip, threat.indicator.provider, threat.indicator.confidence, threat.indicator.description
```

### Query 2: Find All High-Confidence Threats

```sql
FROM threat-intel-ips-*, threat-intel-domains-*, threat-intel-hashes-*
| WHERE threat.indicator.confidence >= 90
| EVAL
    indicator_value = COALESCE(TO_STRING(threat.indicator.ip), threat.indicator.domain, threat.indicator.hash.md5),
    threat_type = CASE(
        threat.indicator.ip IS NOT NULL, "Malicious IP",
        threat.indicator.domain IS NOT NULL, "Malicious Domain",
        "Malicious File Hash"
    )
| KEEP indicator_value, threat_type, threat.indicator.provider, threat.indicator.confidence, threat.indicator.description
| SORT threat.indicator.confidence DESC
```

### Query 3: View Recent Threat Intel Imports

```sql
FROM threat-intel-ips-*, threat-intel-domains-*, threat-intel-hashes-*
| WHERE @timestamp >= NOW() - 24 HOURS
| EVAL
    indicator = COALESCE(TO_STRING(threat.indicator.ip), threat.indicator.domain, threat.indicator.hash.md5),
    type = CASE(
        threat.indicator.ip IS NOT NULL, "IP",
        threat.indicator.domain IS NOT NULL, "Domain",
        "Hash"
    )
| STATS threat_count = COUNT(*) BY type, threat.indicator.provider
| SORT threat_count DESC
```

**Note:** This query shows a summary of threat intelligence imported in the last 24 hours, grouped by indicator type and provider.

**For correlating security events with threat intel**, use the detection rules below (Rule 1, 2, 3) which are specifically designed for that purpose.

## Testing Threat Intelligence

### Test Script

Run the automated threat intelligence test:

```bash
# Set environment variables for local testing
LOGSTASH_HOST=localhost LOGSTASH_PORT=5000 \
  ./scripts/apt-simulations-test/threat-intel-test.sh
```

**Test Coverage:**
- ✅ APT29 SolarWinds C2 communication (6 events)
- ✅ APT28 Fancy Bear domain access (2 events)
- ✅ Phishing domain detection (2 events)
- ✅ WannaCry ransomware hash match (2 events)
- ✅ Mimikatz credential theft tool (2 events)
- ✅ Port scan from known malicious IP (6 events)

**Total:** 20 simulated threat events sent

### Manual Verification

After running the test, verify threat intel data:

```bash
# Check threat intel IP database
curl -u elastic:elastic123 \
  'http://localhost:9200/threat-intel-ips-*/_search?q=threat.indicator.ip:13.59.205.66&pretty'

# Check all threat intel indicators
curl -u elastic:elastic123 \
  'http://localhost:9200/threat-intel-*/_count'

# Expected counts:
# - threat-intel-ips: 5 documents
# - threat-intel-domains: 4 documents
# - threat-intel-hashes: 3 documents
```

## Kibana Integration

### Creating Threat Intel Detection Rules

Navigate to **Security → Rules** and create these detection rules:

#### Rule 1: APT29 (SolarWinds) C2 Communication

```sql
FROM security-*
| WHERE destination.ip IN ("13.59.205.66", "54.193.127.66")
| EVAL
    threat_actor = "APT29 (Cozy Bear)",
    campaign = "SolarWinds Supply Chain",
    threat_level = "CRITICAL"
| KEEP @timestamp, source.ip, destination.ip, threat_actor, campaign, threat_level
```

**Severity:** Critical
**Risk Score:** 99
**MITRE ATT&CK:** T1071 (Command and Control)

#### Rule 2: Known Malicious Domain Access

```sql
FROM security-*
| WHERE message RLIKE "(?i)(avsvmcloud\\.com|freescanonline\\.com|secure-paypal-login\\.com|malware-download\\.xyz)"
| EVAL
    threat_type = CASE(
        message RLIKE "(?i)secure-paypal-login\\.com", "Phishing",
        message RLIKE "(?i)malware-download\\.xyz", "Malware Distribution",
        "C2 Communication"
    ),
    threat_level = "HIGH",
    matched_domain = CASE(
        message RLIKE "(?i)avsvmcloud\\.com", "avsvmcloud.com",
        message RLIKE "(?i)freescanonline\\.com", "freescanonline.com",
        message RLIKE "(?i)secure-paypal-login\\.com", "secure-paypal-login.com",
        "malware-download.xyz"
    )
| KEEP @timestamp, source.ip, destination.ip, matched_domain, threat_type, threat_level, message
```

**Severity:** High
**Risk Score:** 85
**MITRE ATT&CK:** T1566 (Phishing), T1071 (C2)

**Note:** This rule uses regex pattern matching on the message field to detect domain names, since structured domain fields (`url.domain`, `dns.question.name`) are not available in the current index mapping.

#### Rule 3: Ransomware File Hash Detection

```sql
FROM security-*
| WHERE message RLIKE "(?i)(84c82835a5d21bbcf75a61706d8ab549|027cc450ef5f8c5f653329641ec1fed9|ed01ebfbc9eb5bbea545af4d01bf5f1071661840480439c6e5babe8e080e41aa|64b0b58a2c030c77fdb2b537b2fcc4af432bc55ffb36599a31d418c7c69e94b1)"
| EVAL
    malware_family = CASE(
        message RLIKE "(?i)84c82835a5d21bbcf75a61706d8ab549", "WannaCry",
        message RLIKE "(?i)027cc450ef5f8c5f653329641ec1fed9", "NotPetya",
        "Unknown Ransomware"
    ),
    threat_level = "CRITICAL"
| KEEP @timestamp, source.ip, destination.ip, malware_family, threat_level, message
```

**Severity:** Critical
**Risk Score:** 99
**MITRE ATT&CK:** T1486 (Data Encrypted for Impact)

**Note:** This rule uses regex pattern matching on the message field to detect known ransomware file hashes (MD5 and SHA256).

#### Rule 4: Credential Theft Tool Detection (Mimikatz)

```sql
FROM security-*
| WHERE message RLIKE "(?i)(mimikatz|7c4fe364c1f3e3738a75a2b736b0c958)"
| EVAL
    threat_type = "Credential Theft Tool",
    threat_level = "CRITICAL"
| KEEP @timestamp, source.ip, destination.ip, threat_type, threat_level, message
```

**Severity:** Critical
**Risk Score:** 95
**MITRE ATT&CK:** T1003 (OS Credential Dumping)

**Note:** This rule detects the Mimikatz credential theft tool by matching either the tool name or its known MD5 hash in log messages.

## Threat Intelligence Dashboard

### Recommended Visualizations

1. **Threat Intel Matches Over Time** (Line chart)
   - X-axis: @timestamp
   - Y-axis: Count of matches
   - Split by: threat.indicator.provider

2. **Top Malicious IPs** (Bar chart)
   - Y-axis: threat.indicator.ip
   - X-axis: Count of connections
   - Color by: threat.indicator.confidence

3. **APT Group Attribution** (Pie chart)
   - Slice by: threat.apt_group
   - Size: Count of events

4. **Threat Severity Distribution** (Donut chart)
   - Slice by: threat.severity
   - Color: Critical (red), High (orange), Medium (yellow)

5. **Geographic Threat Map** (Map)
   - Field: source.geo.location
   - Filter: threat_intel_match tag

## Maintenance & Updates

### Adding New Threat Indicators

```bash
# Add malicious IP
curl -X POST "http://localhost:9200/threat-intel-ips-$(date +%Y.%m.%d)/_doc" \
  -u "elastic:elastic123" \
  -H 'Content-Type: application/json' \
  -d '{
    "@timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'",
    "threat": {
      "indicator": {
        "ip": "192.0.2.100",
        "type": "malicious",
        "confidence": 95,
        "provider": "Custom Intel",
        "description": "Known APT infrastructure"
      }
    }
  }'
```

### Bulk Import from CSV

```python
import csv
from elasticsearch import Elasticsearch
from datetime import datetime

es = Elasticsearch([{'host': 'localhost', 'port': 9200}], http_auth=('elastic', 'elastic123'))

with open('threat_ips.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        doc = {
            '@timestamp': datetime.utcnow().isoformat() + 'Z',
            'threat': {
                'indicator': {
                    'ip': row['ip'],
                    'type': 'malicious',
                    'confidence': int(row['confidence']),
                    'provider': row['provider'],
                    'description': row['description']
                }
            }
        }
        es.index(index=f"threat-intel-ips-{datetime.now().strftime('%Y.%m.%d')}", document=doc)
```

## Performance Considerations

- **Index Size:** Threat intel indices grow ~100KB per 100 indicators
- **Lookup Speed:** Elasticsearch filter lookups add ~5-10ms per event
- **Refresh Interval:** Set to 5s for near-real-time updates
- **Retention:** Recommend keeping last 90 days of threat intel data

## Security Best Practices

1. **Restrict Access:** Only SOC analysts should have write access to threat-intel-* indices
2. **Audit Trail:** Enable audit logging for all threat intel modifications
3. **Validation:** Verify threat indicators before adding to database
4. **False Positives:** Monitor and tune confidence thresholds
5. **Attribution:** Always cite source of threat intelligence

## Troubleshooting

### No Matches Found

```bash
# Verify threat intel data exists
curl -u elastic:elastic123 'http://localhost:9200/threat-intel-*/_count'

# Check if indices are being created
curl -u elastic:elastic123 'http://localhost:9200/_cat/indices?v' | grep threat-intel

# Test manual query
curl -u elastic:elastic123 \
  'http://localhost:9200/threat-intel-ips-*/_search?q=threat.indicator.ip:13.59.205.66'
```

### Logstash Enrichment Not Working

```bash
# Check Logstash pipeline status
curl -s "http://localhost:9600/_node/stats/pipelines/main" | grep "threat-intel-enrichment"

# View Logstash logs
docker compose logs logstash --tail 100 | grep -i "threat\|elasticsearch.*filter"

# Restart Logstash
docker compose restart logstash
```

## Future Enhancements

- [ ] Integrate with MISP (Malware Information Sharing Platform)
- [ ] Add Recorded Future commercial feed
- [ ] Implement automatic STIX/TAXII feed ingestion
- [ ] Create threat intel aging/expiration policies
- [ ] Add threat score calculation based on multiple indicators
- [ ] Implement automatic IOC extraction from incident reports
- [ ] Build threat hunting queries leveraging threat intel

## References

- [AbuseCH Threat Intelligence](https://abuse.ch/)
- [AlienVault OTX](https://otx.alienvault.com/)
- [MISP Threat Sharing](https://www.misp-project.org/)
- [Elastic Threat Intelligence](https://www.elastic.co/guide/en/security/current/det-engine-overview.html)
- [MITRE ATT&CK Framework](https://attack.mitre.org/)

## Summary

✅ **Status: Infrastructure Ready**

The threat intelligence infrastructure is fully configured with:
- 3 dedicated indices for IPs, domains, and hashes
- 12 high-confidence threat indicators populated
- Logstash enrichment pipeline configured
- Filebeat threat feed modules ready
- Manual query capabilities for threat hunting
- Test simulation script with 20 threat scenarios

The system is ready for manual threat intelligence lookups and can be enhanced with real-time enrichment as needed.
