# Kibana ES|QL Alerting Rules for Windows & Network Devices

## 🎯 Overview

This document contains **Kibana ES|QL alerting rules** for:
- **Windows Event Logs** (via syslog from Windows servers)
- **Network Devices** (Cisco ASA, Palo Alto, Fortinet, pfSense, Snort IDS, Cisco Routers)

All rules have been tested and verified to work with the simulation scripts.

---

## ⚠️ CRITICAL: Time Field Configuration

**FOR EVERY RULE BELOW:**
1. Paste the query into Kibana
2. **Select `@timestamp` from the "Select a time field" dropdown** (REQUIRED!)
3. Set the time window as specified
4. Save the rule

---

# 🪟 WINDOWS EVENT LOG RULES

## 🔥 **1. WINDOWS BRUTE FORCE DETECTION** ✅

### **Rule Name**: `Windows Failed Logon Attempts`
### **ES|QL Query**:
```sql
FROM security-windows-logs-*
| WHERE event.id == "4625"
| STATS failed_attempts = COUNT(*) BY syslog_server, user.name, `source.ip`
| WHERE failed_attempts >= 5
| EVAL threat_level = "HIGH", attack_type = "Windows Brute Force"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `10 minutes`

### **Description**: Detects 5+ failed logon attempts (Event ID 4625) indicating brute force attack on Windows servers

---

## 🔥 **2. WINDOWS PRIVILEGE ESCALATION** ✅

### **Rule Name**: `Windows User Added to Admin Group`
### **ES|QL Query**:
```sql
FROM security-windows-logs-*
| WHERE event.id IN ("4728", "4732", "4672")
| STATS escalation_count = COUNT(*) BY syslog_server, user.name
| WHERE escalation_count >= 1
| EVAL threat_level = "CRITICAL", attack_type = "Privilege Escalation"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `15 minutes`

### **Description**: Detects users being added to privileged groups or special privileges assigned (Event IDs 4728, 4732, 4672)

---

## 🔥 **3. WINDOWS LATERAL MOVEMENT (NTLM)** ✅

### **Rule Name**: `Windows NTLM Lateral Movement`
### **ES|QL Query**:
```sql
FROM security-windows-logs-*
| WHERE event.id == "4776"
| STATS unique_hosts = COUNT_DISTINCT(syslog_server) BY user.name, `source.ip`
| WHERE unique_hosts >= 3
| EVAL threat_level = "HIGH", attack_type = "Lateral Movement"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `20 minutes`

### **Description**: Detects NTLM authentication to 3+ different hosts (Event ID 4776) indicating lateral movement

---

## 🔥 **4. WINDOWS MALICIOUS SERVICE INSTALLATION** ✅

### **Rule Name**: `Suspicious Service Installed`
### **ES|QL Query**:
```sql
FROM security-windows-logs-*
| WHERE event.id == "7045"
| STATS service_installs = COUNT(*) BY syslog_server
| WHERE service_installs >= 1
| EVAL threat_level = "CRITICAL", attack_type = "Persistence Mechanism"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `10 minutes`

### **Description**: Detects new service installation (Event ID 7045) which is a common persistence mechanism

---

## 🔥 **5. WINDOWS SUSPICIOUS PROCESS EXECUTION** ✅

### **Rule Name**: `Malicious Process Command Line`
### **ES|QL Query**:
```sql
FROM security-windows-logs-*
| WHERE event.id == "4688"
| WHERE event_message RLIKE ".*(-enc|-EncodedCommand|mimikatz|psexec|wmic|net user|sekurlsa).*"
| STATS malicious_processes = COUNT(*) BY syslog_server, user.name
| WHERE malicious_processes >= 1
| EVAL threat_level = "CRITICAL", attack_type = "Malicious Execution"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `15 minutes`

### **Description**: Detects suspicious process executions (Event ID 4688) with malicious command line patterns

---

## 🔥 **6. WINDOWS NETWORK SHARE ACCESS (DATA EXFILTRATION)** ✅

### **Rule Name**: `Suspicious Network Share Access`
### **ES|QL Query**:
```sql
FROM security-windows-logs-*
| WHERE event.id == "5140"
| STATS share_access_count = COUNT(*) BY syslog_server, `source.ip`, user.name
| WHERE share_access_count >= 3
| EVAL threat_level = "MEDIUM", attack_type = "Data Access"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `10 minutes`

### **Description**: Detects multiple network share accesses (Event ID 5140) indicating possible data exfiltration

---

# 🛡️ NETWORK DEVICE RULES

## 🔥 **7. PORT SCAN DETECTION (CISCO ASA)** ✅

### **Rule Name**: `Port Scan Detected`
### **ES|QL Query**:
```sql
FROM security-firewall-logs-*
| WHERE syslog_server RLIKE ".*cisco-asa.*"
| WHERE message RLIKE ".*Deny.*"
| DISSECT message "%{} src %{}:%{source_ip}/%{} dst %{}"
| STATS blocked_attempts = COUNT(*) BY source_ip
| WHERE blocked_attempts >= 10
| EVAL threat_level = "HIGH", attack_type = "Port Scan"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `5 minutes`

### **Description**: Detects 10+ deny messages from same IP (port scan or network reconnaissance)

---

## 🔥 **8. C2 COMMUNICATION DETECTION (PALO ALTO)** ✅

### **Rule Name**: `Command & Control Traffic`
### **ES|QL Query**:
```sql
FROM security-firewall-logs-*
| WHERE device_vendor == "paloalto"
| WHERE threat_name RLIKE ".*trojan.*" OR threat_name RLIKE ".*malware.*"
| STATS c2_attempts = COUNT(*) BY `source.ip`
| WHERE c2_attempts >= 1
| EVAL threat_level = "CRITICAL", attack_type = "C2 Communication"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `10 minutes`

### **Description**: Detects command and control communication attempts blocked by Palo Alto firewall

---

## 🔥 **9. SSH BRUTE FORCE (NETWORK DEVICES)** ✅

### **Rule Name**: `SSH Brute Force on Network Device`
### **ES|QL Query**:
```sql
FROM security-auth-logs-*
| WHERE log_category == "authentication"
| WHERE message RLIKE ".*sshd.*Failed password.*"
| STATS ssh_failures = COUNT(*) BY `source.ip`, syslog_server
| WHERE ssh_failures >= 5
| EVAL threat_level = "HIGH", attack_type = "SSH Brute Force"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `10 minutes`

### **Description**: Detects 5+ failed SSH password attempts against network devices (firewalls, routers, switches)

---

## 🔥 **10. DDOS ATTACK DETECTION (FORTINET)** ✅

### **Rule Name**: `DDoS Attack Detected`
### **ES|QL Query**:
```sql
FROM security-firewall-logs-*
| WHERE device_vendor == "fortinet"
| WHERE message RLIKE ".*DoS.*"
| STATS attack_volume = COUNT(*) BY syslog_server
| WHERE attack_volume >= 10
| EVAL threat_level = "CRITICAL", attack_type = "DDoS Attack"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `5 minutes`

### **Description**: Detects 10+ DoS attack events from Fortinet FortiGate firewall

---

## 🔥 **11. IDS CRITICAL ALERTS (SNORT)** ✅

### **Rule Name**: `IDS Critical Threat Detected`
### **ES|QL Query**:
```sql
FROM security-ids-logs-*
| WHERE priority IN ("1", "2")
| STATS alert_count = COUNT(*) BY alert_name, `source.ip`
| WHERE alert_count >= 1
| EVAL threat_level = "CRITICAL", attack_type = "Intrusion Detected"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `10 minutes`

### **Description**: Detects priority 1 or 2 IDS alerts (critical threats like malware, exploit kits, ransomware)

---

## 🔥 **12. UNAUTHORIZED CONFIG CHANGES (CISCO ROUTER)** ✅

### **Rule Name**: `Network Device Config Modified`
### **ES|QL Query**:
```sql
FROM security-network-logs-*
| WHERE message RLIKE ".*CONFIG_I.*" OR message RLIKE ".*configured from.*"
| STATS config_changes = COUNT(*) BY syslog_server, `source.ip`
| WHERE config_changes >= 1
| EVAL threat_level = "HIGH", attack_type = "Config Change"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `15 minutes`

### **Description**: Detects configuration changes on network devices (routers, switches, firewalls)

---

## 🔥 **13. MULTI-DEVICE ATTACK CORRELATION** ✅

### **Rule Name**: `Cross-Platform Attack Detected`
### **ES|QL Query**:
```sql
FROM security-windows-logs-*, security-firewall-logs-*, security-ids-logs-*
| STATS
    unique_devices = COUNT_DISTINCT(syslog_server),
    total_events = COUNT(*)
    BY `source.ip`
| WHERE unique_devices >= 2 OR total_events >= 20
| EVAL threat_level = "CRITICAL", attack_type = "Multi-Vector Attack"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `30 minutes`

### **Description**: Detects attackers targeting multiple systems (Windows servers + network devices)

---

# 📊 Testing & Verification

## Run All Simulations

```bash
# 1. Run Windows security simulation
LOGSTASH_HOST=localhost ./scripts/apt-simulations-test/windows-security.sh

# 2. Run network device simulation
LOGSTASH_HOST=localhost ./scripts/apt-simulations-test/network-devices.sh

# 3. Wait 1 minute for Logstash processing

# 4. Verify indices
curl -u "elastic:elastic123" "http://localhost:9200/_cat/indices/security-*?v&s=index"

# Expected indices:
# - security-windows-logs-YYYY.MM.DD (29 events)
# - security-firewall-logs-YYYY.MM.DD (26+ events)
# - security-ids-logs-YYYY.MM.DD (5 events)
# - security-auth-logs-YYYY.MM.DD (16+ events for SSH)
# - security-network-logs-YYYY.MM.DD (5+ events for config changes)
```

## Verify Data

```bash
# Check Windows logs
curl -s -u "elastic:elastic123" \
  "http://localhost:9200/security-windows-logs-*/_search?size=1&pretty"

# Check firewall logs
curl -s -u "elastic:elastic123" \
  "http://localhost:9200/security-firewall-logs-*/_search?size=1&pretty"

# Check IDS logs
curl -s -u "elastic:elastic123" \
  "http://localhost:9200/security-ids-logs-*/_search?size=1&pretty"
```

---

# 🎯 Summary

## Total Rules Created: **13**

### Windows Rules (6):
1. ✅ Brute Force Detection
2. ✅ Privilege Escalation
3. ✅ Lateral Movement (NTLM)
4. ✅ Malicious Service Installation
5. ✅ Suspicious Process Execution
6. ✅ Network Share Access

### Network Device Rules (7):
7. ✅ Port Scan Detection (Cisco ASA)
8. ✅ C2 Communication (Palo Alto)
9. ✅ SSH Brute Force
10. ✅ DDoS Attack (Fortinet)
11. ✅ IDS Critical Alerts (Snort)
12. ✅ Unauthorized Config Changes (Cisco Router)
13. ✅ Multi-Device Attack Correlation

---

# 📧 Email Actions (Optional)

You can configure email notifications for any rule by adding an action after creating the rule:

1. Navigate to **Stack Management** → **Rules**
2. Select your rule
3. Click **"Add action"**
4. Choose **"Email"**
5. Configure:
   - **To**: `security@company.com`
   - **Subject**: `🚨 SECURITY ALERT: {{alert.name}} - {{context.rule.name}}`
   - **Body**:
   ```
   SECURITY ALERT TRIGGERED

   Rule: {{context.rule.name}}
   Severity: {{context.rule.tags}}
   Time: {{date}}

   Threat Details:
   {{context.alerts}}

   Please investigate immediately.
   ```

---

**Document Version**: 1.0
**Last Updated**: 2025-12-08
**Status**: All queries tested and verified ✅
