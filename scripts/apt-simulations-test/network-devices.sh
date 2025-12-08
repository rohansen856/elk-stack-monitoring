#!/bin/bash

# Network Device Syslog Simulation Script
# Simulates security events from firewalls, routers, and IDS/IPS devices
# Formats: Cisco ASA, Palo Alto, pfSense, Fortinet, Snort IDS

API_BASE="${API_BASE:-http://localhost:8000}"
LOGSTASH_HOST="${LOGSTASH_HOST:-localhost}"
LOGSTASH_SYSLOG_PORT="${LOGSTASH_SYSLOG_PORT:-514}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Network Device Security Log Simulation (Syslog)     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to send syslog message
send_syslog() {
    local facility=$1
    local severity=$2
    local device=$3
    local message=$4

    # Calculate syslog priority
    local priority=$((facility * 8 + severity))

    # Format timestamp
    local timestamp=$(date '+%b %d %H:%M:%S')

    # Construct syslog message
    local syslog_msg="<${priority}>${timestamp} ${device} ${message}"

    # Send via UDP to Logstash
    echo "$syslog_msg" | nc -u -w1 "$LOGSTASH_HOST" "$LOGSTASH_SYSLOG_PORT"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $device logged"
    else
        echo -e "${RED}✗${NC} Failed to send from $device"
    fi
}

# Scenario 1: Cisco ASA Firewall - Port Scan Detection
echo -e "${YELLOW}[1/6]${NC} Simulating Port Scan Attack (Cisco ASA)..."
attacker_ip="203.0.113.66"
target_ip="192.168.1.100"

for port in {21..25} {80..85} {443..448}; do
    send_syslog \
        23 \
        4 \
        "cisco-asa-01" \
        "%ASA-4-106023: Deny tcp src outside:${attacker_ip}/${port} dst inside:${target_ip}/${port} by access-group \"outside_in\""
    sleep 0.05
done

echo ""

# Scenario 2: Palo Alto - Suspicious Outbound Traffic (C2 Communication)
echo -e "${YELLOW}[2/6]${NC} Simulating C2 Communication (Palo Alto)..."
internal_ips=("192.168.1.50" "192.168.1.75" "192.168.1.88")
c2_servers=("malicious-domain.com" "evil-server.net" "badactor.org")

for internal_ip in "${internal_ips[@]}"; do
    for c2 in "${c2_servers[@]}"; do
        send_syslog \
            16 \
            3 \
            "palo-alto-fw" \
            "TRAFFIC,threat,0,2025/12/08 09:30:00,${internal_ip},45123,${c2},443,allow,ssl,tcp,Zone-Internal,Zone-External,permit,trojan,high,client-to-server"
        sleep 0.2
    done
done

echo ""

# Scenario 3: pfSense - Brute Force SSH Attack
echo -e "${YELLOW}[3/6]${NC} Simulating SSH Brute Force (pfSense)..."
attacker_ip="185.220.101.42"
firewall_ip="203.0.113.1"

for i in {1..15}; do
    send_syslog \
        4 \
        5 \
        "pfsense-01" \
        "sshd[12345]: Failed password for root from ${attacker_ip} port $((50000 + i)) ssh2"
    sleep 0.1
done

# Successful login after brute force
send_syslog \
    4 \
    6 \
    "pfsense-01" \
    "sshd[12345]: Accepted password for root from ${attacker_ip} port 50016 ssh2"

echo ""

# Scenario 4: Fortinet FortiGate - DDoS Attack Detection
echo -e "${YELLOW}[4/6]${NC} Simulating DDoS Attack (Fortinet FortiGate)..."
botnet_ips=("198.51.100.10" "198.51.100.20" "198.51.100.30" "198.51.100.40" "198.51.100.50")
target_server="192.168.10.50"

for ip in "${botnet_ips[@]}"; do
    for i in {1..20}; do
        send_syslog \
            23 \
            3 \
            "fortigate-fw" \
            "date=2025-12-08 time=09:32:00 devname=\"FortiGate-01\" logid=\"0000000013\" type=\"traffic\" subtype=\"forward\" level=\"warning\" srcip=${ip} srcport=$((1024 + RANDOM % 64000)) dstip=${target_server} dstport=80 proto=6 action=\"deny\" policyid=1 msg=\"DoS attack detected\""
        sleep 0.01
    done
done

echo ""

# Scenario 5: Snort IDS - Multiple Attack Signatures
echo -e "${YELLOW}[5/6]${NC} Simulating IDS Alerts (Snort)..."

# SQL Injection attempt
send_syslog \
    4 \
    2 \
    "snort-ids" \
    "[1:1234:5] WEB-ATTACKS SQL injection attempt [Classification: Web Application Attack] [Priority: 1] {TCP} 203.0.113.77:54321 -> 192.168.1.100:80"

# Buffer overflow attempt
send_syslog \
    4 \
    2 \
    "snort-ids" \
    "[1:5678:2] EXPLOIT buffer overflow attempt [Classification: Attempted Administrator Privilege Gain] [Priority: 1] {TCP} 203.0.113.77:54322 -> 192.168.1.100:445"

# Malware callback
send_syslog \
    4 \
    1 \
    "snort-ids" \
    "[1:9012:1] MALWARE-CNC Trojan.Generic outbound connection [Classification: A Network Trojan was detected] [Priority: 1] {TCP} 192.168.1.88:49152 -> 198.51.100.99:8080"

# Shellcode execution
send_syslog \
    4 \
    1 \
    "snort-ids" \
    "[1:3456:3] EXPLOIT-KIT Nuclear exploit kit landing page [Classification: A suspicious string was detected] [Priority: 1] {TCP} 203.0.113.77:54323 -> 192.168.1.100:80"

# Ransomware activity
send_syslog \
    4 \
    0 \
    "snort-ids" \
    "[1:7890:1] MALWARE-CNC Ransomware outbound connection detected [Classification: Misc Attack] [Priority: 1] {TCP} 192.168.1.75:51234 -> 185.220.101.88:443"

echo ""

# Scenario 6: Cisco Router - Unauthorized Configuration Changes
echo -e "${YELLOW}[6/6]${NC} Simulating Unauthorized Config Changes (Cisco Router)..."

send_syslog \
    23 \
    5 \
    "cisco-router-01" \
    "%SYS-5-CONFIG_I: Configured from console by unknown on vty0 (198.51.100.55)"

send_syslog \
    23 \
    4 \
    "cisco-router-01" \
    "%SEC_LOGIN-4-LOGIN_FAILED: Login failed for user admin from 198.51.100.55 vty0"

send_syslog \
    23 \
    4 \
    "cisco-router-01" \
    "%SEC_LOGIN-4-LOGIN_FAILED: Login failed for user cisco from 198.51.100.55 vty0"

send_syslog \
    23 \
    6 \
    "cisco-router-01" \
    "%SEC_LOGIN-5-LOGIN_SUCCESS: Login Success [user: admin] [Source: 198.51.100.55] [localport: 23] at 09:35:00 UTC"

send_syslog \
    23 \
    5 \
    "cisco-router-01" \
    "%SYS-5-CONFIG_I: Configured from console by admin on vty0 (198.51.100.55) - access-list 100 permit ip any any"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Network Device Security Events Simulation Complete!   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Summary:"
echo -e "  • ${GREEN}15${NC} port scan attempts (Cisco ASA)"
echo -e "  • ${GREEN}9${NC} C2 communication attempts (Palo Alto)"
echo -e "  • ${GREEN}16${NC} SSH brute force attempts (pfSense)"
echo -e "  • ${GREEN}100${NC} DDoS attack packets (Fortinet)"
echo -e "  • ${GREEN}5${NC} IDS alerts (Snort)"
echo -e "  • ${GREEN}5${NC} unauthorized config changes (Cisco Router)"
echo ""
echo -e "Total: ${GREEN}150${NC} network security events sent to Logstash"
echo ""
echo -e "Check logs in Elasticsearch: ${BLUE}security-network-*${NC}"
