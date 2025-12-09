#!/bin/bash

# ===================================================================
# DETECTION RULES TEST SCRIPT
# ===================================================================
# Quick script to test all Kibana detection rules by sending events
# directly to Logstash TCP port 5000
# ===================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

LOGSTASH_HOST="${LOGSTASH_HOST:-localhost}"
LOGSTASH_PORT="${LOGSTASH_PORT:-5000}"
EVENT_COUNT=0

echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}  DETECTION RULES TEST${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""
echo -e "Target: ${CYAN}$LOGSTASH_HOST:$LOGSTASH_PORT${NC}"
echo ""

# Helper function to send events
send_event() {
    local description="$1"
    local event_json="$2"

    echo -en "${YELLOW}Testing:${NC} $description ... "
    echo "$event_json" | nc -w1 "$LOGSTASH_HOST" "$LOGSTASH_PORT" > /dev/null 2>&1
    ((EVENT_COUNT++))
    echo -e "${GREEN}✓${NC}"
    sleep 0.5
}

# Get current timestamp
get_timestamp() {
    date -u +'%Y-%m-%dT%H:%M:%S.000Z'
}

echo -e "${CYAN}[1/7]${NC} Testing APT29 C2 Communication Detection"
send_event "Connection to APT29 C2 (13.59.205.66)" \
'{
  "@timestamp": "'$(get_timestamp)'",
  "source": {"ip": "192.168.1.100", "port": 51234},
  "destination": {"ip": "13.59.205.66", "port": 443},
  "message": "Outbound connection to APT29 SolarWinds C2 server",
  "event_type": "network_connection"
}'

send_event "Connection to APT29 C2 (54.193.127.66)" \
'{
  "@timestamp": "'$(get_timestamp)'",
  "source": {"ip": "192.168.1.100", "port": 51235},
  "destination": {"ip": "54.193.127.66", "port": 8080},
  "message": "Outbound connection to APT29 infrastructure",
  "event_type": "network_connection"
}'

echo ""
echo -e "${CYAN}[2/7]${NC} Testing Malicious Domain Access Detection"
send_event "Access to avsvmcloud.com (APT29 C2)" \
'{
  "@timestamp": "'$(get_timestamp)'",
  "source": {"ip": "192.168.1.100"},
  "destination": {"ip": "1.2.3.4"},
  "message": "DNS query and HTTP GET to avsvmcloud.com - APT29 SolarWinds C2 domain",
  "event_type": "dns_query"
}'

send_event "Access to secure-paypal-login.com (Phishing)" \
'{
  "@timestamp": "'$(get_timestamp)'",
  "source": {"ip": "192.168.1.105"},
  "message": "HTTP POST to secure-paypal-login.com with credentials",
  "event_type": "http_request"
}'

send_event "Access to malware-download.xyz" \
'{
  "@timestamp": "'$(get_timestamp)'",
  "source": {"ip": "192.168.1.106"},
  "message": "HTTP GET to malware-download.xyz/payload.exe",
  "event_type": "http_request"
}'

echo ""
echo -e "${CYAN}[3/7]${NC} Testing Ransomware Hash Detection"
send_event "WannaCry hash detected (84c82835a5d21bbcf75a61706d8ab549)" \
'{
  "@timestamp": "'$(get_timestamp)'",
  "source": {"ip": "192.168.1.100"},
  "message": "File download: ransomware.exe MD5: 84c82835a5d21bbcf75a61706d8ab549 - WannaCry ransomware detected",
  "event_type": "file_download",
  "file": {"name": "ransomware.exe"}
}'

send_event "NotPetya hash detected (027cc450ef5f8c5f653329641ec1fed9)" \
'{
  "@timestamp": "'$(get_timestamp)'",
  "source": {"ip": "192.168.1.101"},
  "message": "File execution: petya.exe MD5: 027cc450ef5f8c5f653329641ec1fed9 - NotPetya ransomware",
  "event_type": "file_execution"
}'

echo ""
echo -e "${CYAN}[4/7]${NC} Testing Mimikatz Detection"
send_event "Mimikatz hash detected" \
'{
  "@timestamp": "'$(get_timestamp)'",
  "source": {"ip": "192.168.1.102"},
  "message": "Process started: mimikatz.exe MD5: 7c4fe364c1f3e3738a75a2b736b0c958",
  "event_type": "process_start",
  "process": {"name": "mimikatz.exe"}
}'

send_event "Mimikatz keyword in logs" \
'{
  "@timestamp": "'$(get_timestamp)'",
  "source": {"ip": "192.168.1.102"},
  "message": "Mimikatz detected accessing LSASS memory for credential dumping",
  "event_type": "security_alert"
}'

echo ""
echo -e "${CYAN}[5/7]${NC} Testing OTX Malicious IP Detection"
send_event "OTX IP: 143.198.92.82 (China-nexus APT)" \
'{
  "@timestamp": "'$(get_timestamp)'",
  "source": {"ip": "192.168.1.103"},
  "destination": {"ip": "143.198.92.82", "port": 443},
  "message": "Connection to China-nexus cyber threat group infrastructure",
  "event_type": "network_connection"
}'

echo ""
echo -e "${CYAN}[6/7]${NC} Testing OTX Malicious Domain Detection"
send_event "OTX Domain: biklkfd.com (Shanya Ransomware)" \
'{
  "@timestamp": "'$(get_timestamp)'",
  "source": {"ip": "192.168.1.104"},
  "message": "DNS query to biklkfd.com - Shanya Packer-as-a-Service malware distribution",
  "event_type": "dns_query"
}'

send_event "OTX Domain: badinigroup.com (Corporate Phishing)" \
'{
  "@timestamp": "'$(get_timestamp)'",
  "source": {"ip": "192.168.1.105"},
  "message": "HTTP request to badinigroup.com - Global corporate web threat campaign",
  "event_type": "http_request"
}'

echo ""
echo -e "${CYAN}[7/7]${NC} Testing OTX Malware Hash Detection"
send_event "OTX Hash: Shanya Packer (247890c8e1787f3836a9085244b70e83)" \
'{
  "@timestamp": "'$(get_timestamp)'",
  "source": {"ip": "192.168.1.106"},
  "message": "File hash 247890c8e1787f3836a9085244b70e83 detected - Shanya Packer ransomware",
  "event_type": "file_scan"
}'

echo ""
echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}  TEST COMPLETE${NC}"
echo -e "${GREEN}=================================================${NC}"
echo ""
echo -e "Total events sent: ${CYAN}${EVENT_COUNT}${NC}"
echo ""
echo -e "${YELLOW}Verification Steps:${NC}"
echo ""
echo -e "1. ${BLUE}Check Kibana Discover:${NC}"
echo -e "   http://localhost:5601/app/discover"
echo -e "   Filter: ${CYAN}@timestamp >= now-5m${NC}"
echo ""
echo -e "2. ${BLUE}Run ES|QL Query (APT29 C2):${NC}"
echo -e "   ${CYAN}FROM security-* | WHERE destination.ip IN (\"13.59.205.66\", \"54.193.127.66\") | KEEP @timestamp, source.ip, destination.ip, message${NC}"
echo ""
echo -e "3. ${BLUE}Check threat enrichment:${NC}"
echo -e "   curl -s -u elastic:elastic123 'http://localhost:9200/*/_search?q=13.59.205.66&size=1&pretty' | grep -A20 threat"
echo ""
echo -e "4. ${BLUE}Test detection rules in Kibana:${NC}"
echo -e "   Security → Rules → Run your detection queries"
echo ""
echo -e "${YELLOW}Expected Alerts:${NC}"
echo -e "  • ${GREEN}✓${NC} APT29 C2 Communication (Critical)"
echo -e "  • ${GREEN}✓${NC} Malicious Domain Access (High)"
echo -e "  • ${GREEN}✓${NC} Ransomware Hash Detection (Critical)"
echo -e "  • ${GREEN}✓${NC} Mimikatz Credential Theft (Critical)"
echo -e "  • ${GREEN}✓${NC} OTX Malicious IP (High)"
echo -e "  • ${GREEN}✓${NC} OTX Malicious Domain (High)"
echo -e "  • ${GREEN}✓${NC} OTX Malware Hash (Critical)"
echo ""
