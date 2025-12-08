# 🚨 Kibana ES|QL Alerting Rules

This document contains **ES|QL queries** that match the actual data field structure for Kibana's **Stack Management > Rules** interface. ([Rules Page](http://localhost:5601/app/management/insightsAndAlerting/triggersActions/rules))

---

## 🔧 **QUICK START - Before Creating Rules**

### **Step 0: Generate Test Data First!** 🚨

Before creating any rules, you MUST have authentication data in Elasticsearch. The indices will be empty until you generate some events.

**Run APT Simulation Scripts (Complete Test)**
```bash
# Generate full attack simulation data
./scripts/apt-simulations-test/full-attack.sh

# This creates data in ALL security indices:
# - security-auth-logs-*
# - security-powershell-logs-*
# - security-privilege-logs-*
# - security-lateral-logs-*
# - security-network-logs-*
```

**Verify Data Exists:**
```bash
# Check if indices were created
curl -u "elastic:elastic123" "http://localhost:9200/_cat/indices/security-auth-*?v"

# Should show indices with docs.count > 0
```

---

### **Common Error: "Time field is required"** ❌

**Problem**: After pasting the ES|QL query, you see a red error: "Time field is required."

**Solution**:
1. Look for the dropdown that says **"Select a field"** below your query
2. Click it and select **`@timestamp`**
3. The error will disappear ✅

**Why**: ES|QL rules need to know which field contains the timestamp for the time window. All our security logs use `@timestamp`.

---

## 📋 **Rule Creation Checklist**

For EVERY rule you create:
- Paste ES|QL query
- **Select `@timestamp` as time field** ⚠️ (MOST COMMON MISTAKE!)
- Set time window (5m, 10m, 15m, etc.)
- Add alert action (optional)
- Click Save

---

## ✅ **WORKING RULES**

---

## 🔥 **1. BRUTE FORCE ATTACK DETECTION** ✅

### **Rule Name**: `Brute Force Login Attempts`
### **ES|QL Query**:
```sql
FROM security-auth-logs-*
| WHERE event.action == "authentication_failure" AND event.outcome == "failure"
| STATS failed_attempts = COUNT(*) BY source.ip, user.email
| WHERE failed_attempts >= 3
| EVAL threat_level = "HIGH", attack_type = "Brute Force"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `5 minutes`
### **Description**: Detects 3+ failed login attempts from same IP or user (lowered threshold for testing)

---

## 🔥 **2. HIGH VOLUME AUTHENTICATION ATTEMPTS** ✅

### **Rule Name**: `High Volume Authentication Activity`
### **ES|QL Query**:
```sql
FROM security-auth-logs-*
| STATS auth_count = COUNT(*) BY source.ip, user.email
| WHERE auth_count >= 10
| EVAL threat_level = "MEDIUM", attack_type = "High Volume Auth"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `5 minutes`

### **Description**: Detects 10+ authentication attempts from same IP/user combination

---

## 🔥 **3. POWERSHELL ATTACK DETECTION** ✅

### **Rule Name**: `PowerShell Encoded Commands`
### **ES|QL Query**:
```sql
FROM security-powershell-logs-*
| WHERE event.action == "process_start"
| WHERE process.command_line RLIKE ".*(-enc|-EncodedCommand|base64).*"
| STATS attack_count = COUNT(*) BY source.ip, user.name
| WHERE attack_count >= 1
| EVAL threat_level = "CRITICAL", attack_type = "PowerShell LOLBINS"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `2 minutes`

### **Description**: Detects any encoded PowerShell execution

---

## 🔥 **4. PRIVILEGE ESCALATION DETECTION** ✅

### **Rule Name**: `Privilege Escalation Attempts`
### **ES|QL Query**:
```sql
FROM security-privilege-logs-*
| WHERE event.action == "privilege_use"
| STATS escalation_attempts = COUNT(*) BY user.name, host.name
| WHERE escalation_attempts >= 1
| EVAL threat_level = "HIGH", attack_type = "Privilege Escalation"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `5 minutes`

### **Description**: Detects privilege escalation attempts (lowered threshold for testing)

---

## 🔥 **5. LATERAL MOVEMENT DETECTION** ✅

### **Rule Name**: `Network Lateral Movement`
### **ES|QL Query**:
```sql
FROM security-lateral-logs-*
| WHERE event.action == "authentication_success"
| STATS unique_hosts = COUNT_DISTINCT(host.name) BY source.ip, user.name
| WHERE unique_hosts >= 2
| EVAL threat_level = "HIGH", attack_type = "Lateral Movement"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `15 minutes`

### **Description**: Detects successful authentication to 2+ different hosts from same source

---

## 🔥 **6. NETWORK ANOMALY DETECTION** ✅

### **Rule Name**: `Suspicious Network Activity`
### **ES|QL Query**:
```sql
FROM security-network-logs-*
| WHERE network.bytes_out > 1048576
| STATS total_bytes = SUM(network.bytes_out) BY source.ip, destination.ip
| EVAL total_data_mb = total_bytes / 1048576
| WHERE total_data_mb > 5
| EVAL threat_level = "MEDIUM", attack_type = "Large Data Transfer"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `10 minutes`

### **Description**: Detects large data transfers (>5MB total)

---

## 🔥 **7. HIGH FREQUENCY AUTHENTICATION** ✅

### **Rule Name**: `Rapid Authentication Attempts`
### **ES|QL Query**:
```sql
FROM security-auth-logs-*
| WHERE event.action RLIKE ".*(authentication|login).*"
| STATS auth_count = COUNT(*) BY source.ip
| WHERE auth_count >= 20
| EVAL threat_level = "MEDIUM", attack_type = "High Frequency Auth"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `5 minutes`
### **Description**: Detects 20+ authentication attempts from single IP

---

## 🔥 **8. SECURITY ALERTS CORRELATION** ⚠️

### **Rule Name**: `Multiple Security Event Types`
### **ES|QL Query**:
```sql
FROM security-auth-logs-*, security-powershell-logs-*, security-network-logs-*
| STATS
    unique_actions = COUNT_DISTINCT(event.action),
    total_events = COUNT(*)
    BY source.ip
| WHERE unique_actions >= 2 OR total_events >= 15
| EVAL threat_level = "HIGH", attack_type = "Multi-Vector Activity"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `30 minutes`
### **Description**: Detects multiple alert types or high volume from same source (Option 1) OR detects activity across multiple security indices (Option 2)

---

## 🔥 **9. SUSPICIOUS IP BEHAVIOR** ✅

### **Rule Name**: `Abnormal Source IP Activity`
### **ES|QL Query**:
```sql
FROM security-auth-logs-*
| STATS
    unique_users = COUNT_DISTINCT(user.email),
    unique_actions = COUNT_DISTINCT(event.action),
    total_events = COUNT(*)
    BY source.ip
| WHERE (unique_users >= 3) OR (unique_actions >= 5) OR (total_events >= 20)
| EVAL threat_level = "MEDIUM", attack_type = "Suspicious IP Behavior"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `15 minutes`
### **Description**: Detects IPs with suspicious patterns (many users, actions, or events)

---

## 🔥 **10. COMBINED THREAT DETECTION** ✅

### **Rule Name**: `Multi-Stage Attack Detection`
### **ES|QL Query**:
```sql
FROM security-auth-logs-*, security-powershell-logs-*, security-privilege-logs-*
| WHERE event.action IN (
    "authentication_failure",
    "authentication_success",
    "process_start",
    "privilege_use"
)
| STATS
    attack_stages = COUNT_DISTINCT(event.action),
    total_events = COUNT(*)
    BY source.ip
| WHERE attack_stages >= 3
| EVAL threat_level = "CRITICAL", attack_type = "Multi-Stage APT"
```

### **⚠️ IMPORTANT - Time Field Configuration**:
- **Time Field**: Select `@timestamp` from the dropdown (REQUIRED)
- **Time Window**: `30 minutes`
### **Description**: Detects 3+ different attack stages from same source IP

---

## **Email Action Setup Steps:**

1. In the Actions section (what I see in our screenshot):

- Click "Add action"
- Select our Gmail connector from the dropdown

2. Configure the Email Action:

### **To:**
- Enter our email address

### **Subject**:
```
🚨 SECURITY ALERT - {{rule.name}} - {{context.threat_level}}
```

### **Body**:
```html
🚨 SECURITY ALERT TRIGGERED

- Rule Name: {{rule.name}}
- Threat Level: {{context.threat_level}}
- Attack Type: {{context.attack_type}}
- Detection Time: {{context.date}}
- Events Detected: {{context.hits}} events

🔍 Investigation Required:

- Check source IP reputation
- Review user account activity
- Analyze attack timeline
- Implement containment if needed
```

3. Save the Rule

- After adding the email action, click "Save" to create the rule.

4. Repeat for All 10 Rules

---

## 🧪 **Testing Instructions**

1. **Generate Test Attacks**:
   ```bash
   ./scripts/apt-simulations-test/full-attack.sh
   ```

2. **Test Individual Query** in Kibana Discover:
   ```sql
   FROM security-auth-logs-* | WHERE event.action == "authentication_failure" | LIMIT 10
   ```

3. **Create Rule** - Step-by-Step:
   - Go to **Stack Management > Rules**
   - Click **Create rule**
   - Select **Elasticsearch query**
   - Click **ES|QL** tab
   - Paste query in the text area
   - **⚠️ CRITICAL**: In "Select a time field" dropdown, choose **`@timestamp`** (this field is REQUIRED!)
   - Set time window (e.g., "5 minutes")
   - Configure actions (email, webhook, etc.)
   - Click **Save**

---

## ⚠️ **Important Notes**

- **Lower Thresholds**: Thresholds are set low for testing/demo purposes
- **Field Names**: These queries use the actual field names in our data
- **Index Patterns**: Match our existing security indices
- **Time Windows**: Adjusted for demo - increase for production

---

## ✅ **Validated Queries**

All queries in this file:
- ✅ Use correct field names from our data
- ✅ Reference existing indices
- ✅ Have been tested for syntax errors
- ✅ Include proper ES|QL syntax
- ✅ Ready for copy-paste into Kibana
