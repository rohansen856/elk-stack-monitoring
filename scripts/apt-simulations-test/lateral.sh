#!/bin/bash

# APT Simulation: Lateral Movement
# MITRE ATT&CK: T1021 - Remote Services, T1078 - Valid Accounts

API_BASE="${API_BASE:-http://localhost:8000}"

echo "🔄 APT Simulation: Lateral Movement"
echo "==================================="
echo "Simulating compromised account moving across network"
echo ""

# Compromised account scenarios
declare -a compromised_accounts=(
    "john.doe"
    "sarah.admin"
    "backup.service"
    "helpdesk.user"
    "dbadmin"
    "webservice"
)

# Network infrastructure hosts
declare -a network_hosts=(
    "DC01.corp.local"
    "DC02.corp.local"
    "SQL01.corp.local"
    "SQL02.corp.local"
    "WEB01.corp.local"
    "WEB02.corp.local"
    "FILE01.corp.local"
    "FILE02.corp.local"
    "EXCH01.corp.local"
    "BACKUP01.corp.local"
    "PROXY01.corp.local"
    "VPN01.corp.local"
    "PRINT01.corp.local"
    "MGMT01.corp.local"
    "SCAN01.corp.local"
)

# Source IP addresses (attacker-controlled infrastructure)
declare -a source_ips=(
    "192.168.100.50"
    "10.10.10.100"
    "172.16.50.25"
    "203.0.113.77"
    "198.51.100.99"
)

echo "🚀 Starting lateral movement simulation..."
start_time=$(date)

# Select a compromised account for this attack
compromised_user="${compromised_accounts[$((RANDOM % ${#compromised_accounts[@]}))]}"
source_ip="${source_ips[$((RANDOM % ${#source_ips[@]}))]}"

echo "👤 Compromised Account: $compromised_user"
echo "🌐 Source IP: $source_ip"
echo ""

# Simulate lateral movement across multiple hosts
target_hosts=()
num_targets=$((5 + RANDOM % 8)) # 5-12 hosts

# Select random hosts for lateral movement
for i in $(seq 1 $num_targets); do
    host="${network_hosts[$((RANDOM % ${#network_hosts[@]}))]}"

    # Avoid duplicates
    if [[ ! " ${target_hosts[@]} " =~ " ${host} " ]]; then
        target_hosts+=("$host")
    fi
done

echo "🎯 Target hosts: ${target_hosts[@]}"
echo ""

# Simulate network logons to each target
for i in "${!target_hosts[@]}"; do
    host="${target_hosts[$i]}"

    echo "  [$(($i + 1))/${#target_hosts[@]}] Lateral movement to $host"
    echo "    Account: $compromised_user"
    echo "    Source: $source_ip"
    echo "    Logon Type: 3 (Network)"

    # Send lateral movement event
    response=$(curl -s -X POST "$API_BASE/api/v1/security/simulate/lateral-movement" \
        -H "Content-Type: application/json" \
        -d "{
            \"user\": \"$compromised_user\",
            \"hosts\": [\"$host\"],
            \"source_ip\": \"$source_ip\"
        }")

    if echo "$response" | grep -q "success"; then
        echo "    ✅ Network logon logged successfully"
    else
        echo "    ❌ Failed to log network logon"
    fi

    # Realistic timing between lateral movements
    sleep $((2 + RANDOM % 5))
done

# Simulate additional privilege escalation attempts during lateral movement
echo ""
echo "🔐 Simulating privilege escalation attempts..."

privilege_commands=(
    "runas /user:Administrator cmd.exe"
    "runas /netonly /user:domain\\admin powershell.exe"
    "sudo su -"
    "sudo -u root /bin/bash"
    "runas /user:CORP\\Domain_Admin cmd.exe"
)

for i in {1..3}; do
    host="${target_hosts[$((RANDOM % ${#target_hosts[@]}))]}"
    command="${privilege_commands[$((RANDOM % ${#privilege_commands[@]}))]}"
    process_name=$(echo "$command" | awk '{print $1}')

    echo "  [$i/3] Privilege escalation on $host"
    echo "    Command: $command"

    curl -s -X POST "$API_BASE/api/v1/security/simulate/privilege-escalation" \
        -H "Content-Type: application/json" \
        -d "{
            \"command\": \"$command\",
            \"user\": \"$compromised_user\",
            \"host\": \"$host\",
            \"process\": \"$process_name\",
            \"source_ip\": \"$source_ip\"
        }" > /dev/null

    echo "    ✅ Privilege escalation logged"
    sleep 2
done

end_time=$(date)

echo ""
echo "✅ Lateral movement simulation completed!"
echo "📊 Attack Summary:"
echo "   Compromised Account: $compromised_user"
echo "   Source IP: $source_ip"
echo "   Hosts Accessed: ${#target_hosts[@]}"
echo "   Privilege Escalations: 3"
echo "   Start Time: $start_time"
echo "   End Time: $end_time"
echo ""
echo "🔍 Check detection results:"
echo "   curl '$API_BASE/api/v1/security/hunt/lateral-movement'"
echo "   curl '$API_BASE/api/v1/security/hunt/privilege-escalation'"
echo ""
echo "📊 View in Kibana:"
echo "   http://localhost:5601/app/discover#/?_g=(filters:!(),query:(language:kuery,query:'log_category:lateral_movement OR log_category:privilege_escalation'))"