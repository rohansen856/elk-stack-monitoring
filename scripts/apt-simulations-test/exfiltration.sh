#!/bin/bash

# APT Simulation: Data Exfiltration
# MITRE ATT&CK: T1041 - Exfiltration Over C2 Channel

API_BASE="${API_BASE:-http://localhost:8000}"

echo "📤 APT Simulation: Data Exfiltration"
echo "===================================="
echo "Simulating large-scale data theft operations"
echo ""

# Internal source IPs (compromised hosts)
declare -a source_ips=(
    "192.168.1.50"
    "10.0.1.25"
    "172.16.1.100"
    "192.168.100.75"
    "10.10.10.200"
)

# External destination IPs (attacker C2 servers)
declare -a destination_ips=(
    "203.0.113.45"      # APT29 C2
    "198.51.100.88"     # Carbanak C2
    "185.199.108.154"   # Lazarus C2
    "151.101.193.140"   # Equation Group C2
    "192.0.2.99"        # APT1 C2
    "104.16.249.249"    # Cozy Bear C2
)

# Data types being exfiltrated
declare -a data_types=(
    "customer_database"
    "financial_records"
    "intellectual_property"
    "employee_data"
    "source_code"
    "email_archives"
    "security_configs"
    "business_plans"
)

echo "🚀 Starting data exfiltration simulation..."
start_time=$(date)

# Simulate multiple exfiltration sessions
for session in {1..5}; do
    source_ip="${source_ips[$((RANDOM % ${#source_ips[@]}))]}"
    dest_ip="${destination_ips[$((RANDOM % ${#destination_ips[@]}))]}"
    data_type="${data_types[$((RANDOM % ${#data_types[@]}))]}"

    # Generate realistic data volumes (100MB to 2GB)
    data_size_mb=$((100 + RANDOM % 1900))
    data_size_bytes=$((data_size_mb * 1024 * 1024))

    echo "  [Session $session/5] Exfiltrating $data_type"
    echo "    Source: $source_ip"
    echo "    Destination: $dest_ip"
    echo "    Volume: ${data_size_mb}MB (${data_size_bytes} bytes)"

    # Send data exfiltration event
    response=$(curl -s -X POST "$API_BASE/api/v1/security/simulate/data-exfiltration" \
        -H "Content-Type: application/json" \
        -d "{
            \"source_ip\": \"$source_ip\",
            \"destination_ip\": \"$dest_ip\",
            \"bytes_transferred\": $data_size_bytes,
            \"direction\": \"outbound\"
        }")

    if echo "$response" | grep -q "success"; then
        echo "    ✅ Exfiltration event logged successfully"
    else
        echo "    ❌ Failed to log exfiltration event"
    fi

    # Simulate multiple chunks for large transfers
    if [ $data_size_mb -gt 500 ]; then
        echo "    📦 Large transfer detected - simulating chunked transfer..."

        chunks=$((data_size_mb / 200))
        for chunk in $(seq 1 $chunks); do
            chunk_size=$((200 * 1024 * 1024))

            curl -s -X POST "$API_BASE/api/v1/security/simulate/data-exfiltration" \
                -H "Content-Type: application/json" \
                -d "{
                    \"source_ip\": \"$source_ip\",
                    \"destination_ip\": \"$dest_ip\",
                    \"bytes_transferred\": $chunk_size,
                    \"direction\": \"outbound\"
                }" > /dev/null

            sleep 0.5
        done
        echo "    ✅ Chunked transfer completed ($chunks chunks)"
    fi

    # Realistic delay between exfiltration sessions
    sleep $((10 + RANDOM % 20))
done

echo ""
echo "💾 Simulating additional data collection activities..."

# Simulate reconnaissance and data discovery
recon_activities=(
    "dir C:\\Users\\*\\Documents\\*.docx /S"
    "find /home -name '*.pdf' -type f"
    "Get-ChildItem -Recurse -Include *.xlsx | Select FullName"
    "grep -r 'password' /etc/*"
    "net view \\\\fileserver\\shared"
)

for activity in "${recon_activities[@]}"; do
    echo "  🔍 Data discovery: ${activity:0:40}..."

    # Log as PowerShell execution
    curl -s -X POST "$API_BASE/api/v1/security/simulate/powershell" \
        -H "Content-Type: application/json" \
        -d "{
            \"command\": \"$activity\",
            \"user\": \"data_hunter\",
            \"host\": \"${source_ips[0]}\",
            \"process_id\": $((2000 + RANDOM % 1000)),
            \"source_ip\": \"${source_ips[0]}\"
        }" > /dev/null

    sleep 1
done

end_time=$(date)

echo ""
echo "✅ Data exfiltration simulation completed!"
echo "📊 Attack Summary:"
echo "   Exfiltration Sessions: 5"
echo "   Source Hosts: ${#source_ips[@]}"
echo "   C2 Servers: ${#destination_ips[@]}"
echo "   Data Types: ${#data_types[@]}"
echo "   Recon Activities: ${#recon_activities[@]}"
echo "   Start Time: $start_time"
echo "   End Time: $end_time"
echo ""
echo "🔍 Check detection results:"
echo "   curl '$API_BASE/api/v1/security/threats/data-exfiltration'"
echo ""
echo "📊 View in Kibana:"
echo "   http://localhost:5601/app/discover#/?_g=(filters:!(),query:(language:kuery,query:'log_category:network_traffic'))"
echo ""
echo "💡 Expected Detections:"
echo "   • Large outbound data transfers (>100MB)"
echo "   • Multiple connections to external IPs"
echo "   • Data discovery PowerShell commands"
echo "   • Unusual network patterns"