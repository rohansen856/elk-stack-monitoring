#!/bin/bash

# Windows Security Event Log Simulation Script
# Simulates common Windows security events sent via syslog to Logstash
# Event IDs: https://www.ultimatewindowssecurity.com/securitylog/encyclopedia/

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
echo -e "${BLUE}║   Windows Security Event Log Simulation (via Syslog)  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Windows Event IDs for security monitoring
# 4624 = Successful logon
# 4625 = Failed logon (brute force indicator)
# 4720 = User account created
# 4722 = User account enabled
# 4728 = User added to security-enabled global group (privilege escalation)
# 4732 = User added to security-enabled local group
# 4688 = Process created (malware/powershell execution)
# 4672 = Special privileges assigned to new logon (admin access)
# 4768 = Kerberos TGT requested
# 4769 = Kerberos service ticket requested
# 4776 = NTLM authentication (lateral movement)
# 5140 = Network share accessed (data exfiltration)
# 7045 = Service installed (persistence mechanism)

# Attack scenarios
declare -a SCENARIOS=(
    "Brute Force Attack (Event ID 4625)"
    "Privilege Escalation (Event ID 4728)"
    "Lateral Movement via Pass-the-Hash (Event ID 4776)"
    "Malicious Service Installation (Event ID 7045)"
    "Suspicious Process Execution (Event ID 4688)"
    "Network Share Access - Data Exfiltration (Event ID 5140)"
)

# Function to send Windows event via syslog to Logstash
send_windows_event() {
    local event_id=$1
    local severity=$2
    local computer=$3
    local user=$4
    local source_ip=$5
    local message=$6
    local logon_type=${7:-""}
    local process_name=${8:-""}
    local target_user=${9:-""}

    # Calculate syslog priority (facility 10 = security/authorization, severity varies)
    local facility=10
    local priority=$((facility * 8 + severity))

    # Format timestamp in syslog format
    local timestamp=$(date '+%b %d %H:%M:%S')

    # Construct Windows Event Log message in syslog format
    local syslog_msg="<${priority}>${timestamp} ${computer} Microsoft-Windows-Security-Auditing: EventID=${event_id} User=${user} Source=${source_ip} ${message}"

    # Add optional fields
    if [ -n "$logon_type" ]; then
        syslog_msg="${syslog_msg} LogonType=${logon_type}"
    fi
    if [ -n "$process_name" ]; then
        syslog_msg="${syslog_msg} ProcessName=${process_name}"
    fi
    if [ -n "$target_user" ]; then
        syslog_msg="${syslog_msg} TargetUser=${target_user}"
    fi

    # Send via UDP to Logstash syslog input
    echo "$syslog_msg" | nc -u -w1 "$LOGSTASH_HOST" "$LOGSTASH_SYSLOG_PORT"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Event ID $event_id logged"
    else
        echo -e "${RED}✗${NC} Failed to send Event ID $event_id"
    fi
}

# Scenario 1: Brute Force Attack (Multiple failed logons)
echo -e "${YELLOW}[1/6]${NC} Simulating Brute Force Attack..."
attacker_ip="198.51.100.42"
target_computer="DC01.corp.local"
target_user="Administrator"

for i in {1..10}; do
    send_windows_event \
        "4625" \
        4 \
        "$target_computer" \
        "$target_user" \
        "$attacker_ip" \
        "Failed logon attempt. Failure Reason: Bad password." \
        "3" \
        "" \
        ""
    sleep 0.1
done

# Successful logon after brute force
send_windows_event \
    "4624" \
    6 \
    "$target_computer" \
    "$target_user" \
    "$attacker_ip" \
    "Successful logon after multiple failed attempts." \
    "3" \
    "explorer.exe" \
    ""

echo ""

# Scenario 2: Privilege Escalation
echo -e "${YELLOW}[2/6]${NC} Simulating Privilege Escalation..."
attacker_user="john.doe"
admin_group="Domain Admins"

send_windows_event \
    "4728" \
    4 \
    "$target_computer" \
    "SYSTEM" \
    "172.16.10.50" \
    "User added to privileged group. Member: ${attacker_user} Group: ${admin_group}" \
    "" \
    "" \
    "$attacker_user"

send_windows_event \
    "4672" \
    4 \
    "$target_computer" \
    "$attacker_user" \
    "172.16.10.50" \
    "Special privileges assigned to new logon. Privileges: SeDebugPrivilege, SeImpersonatePrivilege" \
    "3" \
    "" \
    ""

echo ""

# Scenario 3: Lateral Movement (Pass-the-Hash NTLM)
echo -e "${YELLOW}[3/6]${NC} Simulating Lateral Movement via NTLM..."
source_computer="WS001.corp.local"
target_computers=("SQL01.corp.local" "WEB01.corp.local" "FILE01.corp.local" "APP01.corp.local")

for target in "${target_computers[@]}"; do
    send_windows_event \
        "4776" \
        6 \
        "$target" \
        "$attacker_user" \
        "$attacker_ip" \
        "NTLM authentication successful. Package: NTLM. Source: ${source_computer}" \
        "" \
        "" \
        ""
    sleep 0.2
done

echo ""

# Scenario 4: Malicious Service Installation (Persistence)
echo -e "${YELLOW}[4/6]${NC} Simulating Malicious Service Installation..."
malicious_services=("WindowsUpdateService" "SystemHealthMonitor" "SecurityScanner")

for service in "${malicious_services[@]}"; do
    send_windows_event \
        "7045" \
        3 \
        "$target_computer" \
        "SYSTEM" \
        "$attacker_ip" \
        "Service installed. ServiceName: ${service} ServicePath: C:\\Windows\\Temp\\${service}.exe ServiceType: user mode" \
        "" \
        "${service}.exe" \
        ""
    sleep 0.2
done

echo ""

# Scenario 5: Suspicious Process Execution
echo -e "${YELLOW}[5/6]${NC} Simulating Suspicious Process Execution..."
suspicious_processes=(
    "powershell.exe -EncodedCommand JABzAD0ATgBlAHcALQBPAGIAagBlAGMAdAAgAEkATwAuAE0AZQBtAG8AcgB5AFMAdAByAGUAYQBtACgALABbAEMAbwBuAHYAZQByAHQAXQA6ADoARgByAG8AbQBCAGEAcwBlADYANABTAHQAcgBpAG4AZwAoACIASAA0AHMASQBBAEEAQQBBAEEAQQBBAEEAQQBLADEAVwBhADIALwBiAE0AQgBCADAANQAxAHcAagBEAEUAcwBaAFMAZgB5AFkASgBBAEUAQQBBAEQALwAvAC8ALwA4ACIAKQAKAA=="
    "cmd.exe /c net user hacker P@ssw0rd! /add"
    "mimikatz.exe privilege::debug sekurlsa::logonpasswords"
    "psexec.exe \\\\remote-host -u admin -p pass cmd.exe"
    "wmic.exe process call create 'powershell.exe -nop -w hidden'"
)

for ((i=0; i<${#suspicious_processes[@]}; i++)); do
    send_windows_event \
        "4688" \
        6 \
        "$target_computer" \
        "$attacker_user" \
        "$attacker_ip" \
        "Process created. CommandLine: ${suspicious_processes[$i]}" \
        "" \
        "$(echo ${suspicious_processes[$i]} | cut -d' ' -f1)" \
        ""
    sleep 0.3
done

echo ""

# Scenario 6: Network Share Access (Data Exfiltration)
echo -e "${YELLOW}[6/6]${NC} Simulating Network Share Access..."
sensitive_shares=("\\\\FILE01\\HR_Documents" "\\\\FILE01\\Finance" "\\\\FILE01\\Contracts" "\\\\DC01\\SYSVOL")

for share in "${sensitive_shares[@]}"; do
    send_windows_event \
        "5140" \
        6 \
        "FILE01.corp.local" \
        "$attacker_user" \
        "$attacker_ip" \
        "Network share accessed. ShareName: ${share} AccessMask: 0x1" \
        "" \
        "explorer.exe" \
        ""
    sleep 0.2
done

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Windows Security Events Simulation Complete!          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Summary:"
echo -e "  • ${GREEN}10${NC} failed logon attempts (Event ID 4625)"
echo -e "  • ${GREEN}1${NC} successful logon after brute force (Event ID 4624)"
echo -e "  • ${GREEN}2${NC} privilege escalation events (Event ID 4728, 4672)"
echo -e "  • ${GREEN}4${NC} lateral movement attempts (Event ID 4776)"
echo -e "  • ${GREEN}3${NC} malicious service installations (Event ID 7045)"
echo -e "  • ${GREEN}5${NC} suspicious process executions (Event ID 4688)"
echo -e "  • ${GREEN}4${NC} network share accesses (Event ID 5140)"
echo ""
echo -e "Total: ${GREEN}29${NC} Windows security events sent to Logstash"
echo ""
echo -e "Check logs in Elasticsearch: ${BLUE}security-windows-logs-*${NC}"
