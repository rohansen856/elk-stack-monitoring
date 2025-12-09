# APT Attack Detection Query - Fixed Version

## Original Query Issues
The original query referenced fields that don't exist in our security indices:
- `user.privileges` → Not present
- `security.is_suspicious` → Not present
- `security.is_exfiltration` → Not present
- `network.bytes_out` → Not present consistently

## Corrected Query for Real-Time APT Detection

### Query 1: Administrator Activity with High-Risk Events

```sql
FROM security-*
| WHERE @timestamp >= NOW() - 1 HOUR
| WHERE user.name RLIKE ".*[Aa]dmin.*" OR user.name == "SYSTEM" OR user.name == "root"
| WHERE log_category IN ("privilege_escalation", "lateral_movement", "windows_security", "powershell_execution")
| STATS
    event_count = COUNT(*),
    unique_servers = COUNT_DISTINCT(syslog_server),
    unique_ips = COUNT_DISTINCT(`source.ip`),
    first_seen = MIN(@timestamp),
    last_seen = MAX(@timestamp)
  BY user.name, log_category, `source.ip`
| WHERE event_count >= 3 OR unique_servers >= 2
| EVAL threat_level = CASE(
    unique_servers >= 3, "CRITICAL",
    event_count >= 10, "HIGH",
    "MEDIUM"
  )
| SORT event_count DESC, unique_servers DESC
| LIMIT 100
```

**What it detects:**
- Administrator accounts performing suspicious multi-server activity
- Privilege escalation attempts
- Lateral movement by admin users
- PowerShell execution by privileged accounts

**Time Window:** Last 1 hour
**Thresholds:** 3+ events OR 2+ servers accessed

---

### Query 2: Data Exfiltration Detection (File Share Access)

```sql
FROM security-windows-logs-*
| WHERE @timestamp >= NOW() - 1 HOUR
| WHERE event.id == "5140"
| STATS
    share_accesses = COUNT(*),
    unique_shares = COUNT_DISTINCT(syslog_server),
    first_access = MIN(@timestamp),
    last_access = MAX(@timestamp)
  BY user.name, `source.ip`
| WHERE share_accesses >= 10 OR unique_shares >= 3
| EVAL threat_level = CASE(
    share_accesses >= 50, "CRITICAL",
    share_accesses >= 20, "HIGH",
    "MEDIUM"
  )
| SORT share_accesses DESC
| LIMIT 50
```

**What it detects:**
- Mass file access (potential data exfiltration)
- Users accessing many network shares
- Automated file enumeration

**Event ID 5140:** Network share access
**Thresholds:** 10+ accesses OR 3+ unique shares

---

### Query 3: Credential Theft Detection (NTLM Activity)

```sql
FROM security-windows-logs-*
| WHERE @timestamp >= NOW() - 1 HOUR
| WHERE event.id == "4776"
| STATS
    auth_attempts = COUNT(*),
    unique_targets = COUNT_DISTINCT(syslog_server)
  BY user.name, `source.ip`
| WHERE unique_targets >= 5 OR auth_attempts >= 20
| EVAL
    threat_level = "HIGH",
    attack_type = "Credential Theft / Pass-the-Hash"
| SORT unique_targets DESC, auth_attempts DESC
| LIMIT 50
```

**What it detects:**
- Pass-the-Hash attacks
- Credential spraying
- NTLM relay attacks

**Event ID 4776:** NTLM authentication
**Mimics:** Mimikatz-style credential theft

---

### Query 4: Ransomware Behavior Detection (Service Installation + Process Execution)

```sql
FROM security-windows-logs-*
| WHERE @timestamp >= NOW() - 1 HOUR
| WHERE event.id IN ("7045", "4688")
| WHERE message RLIKE ".*(powershell|cmd|wmic|vssadmin|bcdedit|wbadmin).*"
| STATS
    suspicious_events = COUNT(*),
    event_types = COUNT_DISTINCT(event.id)
  BY syslog_server, user.name
| WHERE suspicious_events >= 5
| EVAL
    threat_level = "CRITICAL",
    attack_type = "Ransomware Behavior"
| SORT suspicious_events DESC
| LIMIT 50
```

**What it detects:**
- Service installations (persistence)
- Shadow copy deletion (vssadmin)
- Boot configuration tampering (bcdedit)
- Backup deletion (wbadmin)

**Similar to:** WannaCry, NotPetya, REvil

---

### Query 5: Network-Based C2 Communication

```sql
FROM security-firewall-logs-*, security-ids-logs-*
| WHERE @timestamp >= NOW() - 1 HOUR
| WHERE message RLIKE ".*(trojan|malware|C2|command.*control|botnet).*"
| STATS
    c2_attempts = COUNT(*),
    unique_destinations = COUNT_DISTINCT(syslog_server)
  BY `source.ip`
| WHERE c2_attempts >= 5
| EVAL
    threat_level = "CRITICAL",
    attack_type = "C2 Communication"
| SORT c2_attempts DESC
| LIMIT 50
```

**What it detects:**
- Command and Control beaconing
- Trojan/malware connections
- Botnet activity

**Similar to:** SolarWinds SUNBURST, DarkSide C2

---

### Query 6: Multi-Stage APT Kill Chain Correlation

```sql
FROM security-*
| WHERE @timestamp >= NOW() - 6 HOURS
| STATS
    unique_attack_types = COUNT_DISTINCT(log_category),
    total_events = COUNT(*)
  BY `source.ip`, user.name
| WHERE unique_attack_types >= 3 OR total_events >= 50
| EVAL
    threat_level = CASE(
        unique_attack_types >= 5, "CRITICAL",
        unique_attack_types >= 3, "HIGH",
        "MEDIUM"
    ),
    attack_type = "APT Kill Chain"
| SORT unique_attack_types DESC, total_events DESC
| LIMIT 20
```

**What it detects:**
- Multi-stage attacks (reconnaissance → exploitation → lateral movement → exfiltration)
- Coordinated attacks across multiple systems
- APT-style persistence and privilege escalation chains
- Attackers using 3+ different attack categories

**Similar to:** APT29 (SolarWinds), APT28 (Fancy Bear), Lazarus Group

**Note**: Removed `attack_stages = VALUES(log_category)` as the VALUES() function is not available in ES|QL. Use COUNT_DISTINCT to identify multi-stage attacks.

---

## Testing the Queries

Test each query individually in Kibana:

```bash
# Navigate to Kibana
http://localhost/monitoring/

# Go to: Dev Tools → Console
# Paste the query and execute

# Or via curl:
curl -u "elastic:elastic123" -X POST "http://localhost:9200/_query?format=txt" \
  -H "Content-Type: application/json" \
  -d '{"query": "YOUR_QUERY_HERE"}'
```

---

## Field Mapping Reference

| Query Field | Actual Field in Index | Description |
|-------------|----------------------|-------------|
| `user.privileges` ❌ | `user.name` ✅ | Use pattern matching for admin detection |
| `security.is_suspicious` ❌ | `log_category` ✅ | Use category filtering |
| `network.bytes_out` ❌ | Event count ✅ | Use event frequency as proxy |
| `host.name` ✅ | `syslog_server` ✅ | Server/hostname |
| `source.ip` ✅ | `source.ip` ✅ | Source IP (use backticks) |

---

## Recommended Kibana Alert Rules

Create these as Kibana alerting rules with:
- **Check every:** 5 minutes
- **Time window:** 1 hour
- **Actions:** Email/Slack notification
- **Severity:** Critical for queries 4, 5, 6

---

## Next Steps

1. ✅ Test each query in Kibana Dev Tools
2. ⏭️ Create Kibana alerting rules
3. ⏭️ Implement attack simulations to generate test data
4. ⏭️ Validate detection accuracy
