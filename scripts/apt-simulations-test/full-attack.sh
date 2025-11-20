#!/bin/bash

# APT Simulation: Complete Kill Chain Attack
# MITRE ATT&CK: Full Kill Chain Simulation

API_BASE="${API_BASE:-http://localhost:8000}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🎯 APT Simulation: Complete Kill Chain Attack"
echo "============================================="
echo "Simulating a full Advanced Persistent Threat attack sequence"
echo "Following the MITRE ATT&CK framework stages:"
echo ""
echo "  1️⃣ Initial Access   - Brute Force Attack"
echo "  2️⃣ Execution        - Malicious PowerShell"
echo "  3️⃣ Persistence      - Account Creation & Registry"
echo "  4️⃣ Privilege Esc.   - Credential Escalation"
echo "  5️⃣ Lateral Movement - Network Reconnaissance"
echo "  6️⃣ Exfiltration     - Data Theft"
echo "  7️⃣ Impact           - Coverage Cleanup"
echo ""

# APT Campaign Configuration
APT_CAMPAIGN_ID="APT-SIM-$(date +%Y%m%d-%H%M%S)"
ATTACKER_GROUP="SIMULATION_APT"
CAMPAIGN_START=$(date)

echo "🏷️  Campaign ID: $APT_CAMPAIGN_ID"
echo "👥 Threat Group: $ATTACKER_GROUP"
echo "⏰ Campaign Start: $CAMPAIGN_START"
echo ""

# Logging function
log_stage() {
    local stage="$1"
    local status="$2"
    local details="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] $stage: $status - $details"
}

# Stage execution function
execute_stage() {
    local stage_number="$1"
    local stage_name="$2"
    local script_name="$3"
    local stage_args="$4"

    echo ""
    echo "======================================"
    echo "🎯 STAGE $stage_number: $stage_name"
    echo "======================================"

    log_stage "$stage_name" "STARTED" "Executing $script_name"

    if [ -f "$SCRIPT_DIR/$script_name" ]; then
        chmod +x "$SCRIPT_DIR/$script_name"

        if [ -n "$stage_args" ]; then
            eval "$SCRIPT_DIR/$script_name $stage_args"
        else
            "$SCRIPT_DIR/$script_name"
        fi

        local exit_code=$?

        if [ $exit_code -eq 0 ]; then
            log_stage "$stage_name" "COMPLETED" "Stage executed successfully"
            return 0
        else
            log_stage "$stage_name" "FAILED" "Stage failed with exit code $exit_code"
            return $exit_code
        fi
    else
        log_stage "$stage_name" "SKIPPED" "Script $script_name not found"
        return 1
    fi
}

# Pre-attack reconnaissance
echo "🔍 PRE-ATTACK: Reconnaissance & Target Validation"
echo "================================================="

log_stage "RECONNAISSANCE" "STARTED" "Validating target system"

# Check if API is accessible
if curl -s "$API_BASE/health" > /dev/null 2>&1; then
    log_stage "RECONNAISSANCE" "SUCCESS" "Target API accessible at $API_BASE"
else
    log_stage "RECONNAISSANCE" "FAILED" "Target API not accessible at $API_BASE"
    echo "❌ Target system not accessible. Aborting attack simulation."
    exit 1
fi

# Check if ELK stack is available
if curl -s "http://localhost:9200/_cluster/health" > /dev/null 2>&1; then
    log_stage "RECONNAISSANCE" "SUCCESS" "ELK stack available for attack monitoring"
else
    log_stage "RECONNAISSANCE" "WARNING" "ELK stack not accessible - detection analysis may be limited"
fi

sleep 2

# Execute full attack chain
echo ""
echo "🚨 INITIATING FULL APT ATTACK SIMULATION"
echo "========================================"

# Stage 1: Initial Access (Brute Force)
execute_stage "1" "INITIAL_ACCESS" "brute-force.sh" "ATTACK_COUNT=75"

# Brief pause between stages (realistic timing)
echo ""
echo "⏳ Pausing 30 seconds before next stage (realistic APT timing)..."
sleep 30

# Stage 2: Execution (PowerShell)
execute_stage "2" "EXECUTION" "powershell.sh"

echo ""
echo "⏳ Pausing 45 seconds before persistence establishment..."
sleep 45

# Stage 3: Persistence
execute_stage "3" "PERSISTENCE" "persistence.sh" "ACCOUNT_COUNT=15"

echo ""
echo "⏳ Pausing 60 seconds before privilege escalation..."
sleep 60

# Stage 4: Privilege Escalation & Lateral Movement
execute_stage "4" "LATERAL_MOVEMENT" "lateral.sh"

echo ""
echo "⏳ Pausing 90 seconds before data exfiltration..."
sleep 90

# Stage 5: Data Exfiltration
execute_stage "5" "EXFILTRATION" "exfiltration.sh"

# Post-attack cleanup simulation
echo ""
echo "🧹 POST-ATTACK: Coverage & Cleanup"
echo "=================================="

log_stage "CLEANUP" "STARTED" "Simulating log tampering and trace removal"

# Simulate log deletion attempts
cleanup_commands=(
    "wevtutil cl Security"
    "wevtutil cl System"
    "rm -rf /var/log/auth.log"
    "powershell Clear-EventLog -LogName Security"
    "del C:\\Windows\\System32\\winevt\\Logs\\*.evtx"
)

for command in "${cleanup_commands[@]}"; do
    log_stage "CLEANUP" "SIMULATED" "Attempting: $command"

    # Log as PowerShell execution
    curl -s -X POST "$API_BASE/api/v1/security/simulate/powershell" \
        -H "Content-Type: application/json" \
        -d "{
            \"command\": \"$command\",
            \"user\": \"cleanup_agent\",
            \"host\": \"target.corp.local\",
            \"process_id\": $((6000 + RANDOM % 1000)),
            \"source_ip\": \"192.168.1.99\"
        }" > /dev/null

    sleep 1
done

log_stage "CLEANUP" "COMPLETED" "Cleanup simulation finished"

# Campaign summary
CAMPAIGN_END=$(date)

echo ""
echo "🎉 APT ATTACK SIMULATION COMPLETED"
echo "================================="
echo ""
echo "📊 CAMPAIGN SUMMARY:"
echo "   Campaign ID: $APT_CAMPAIGN_ID"
echo "   Threat Group: $ATTACKER_GROUP"
echo "   Start Time: $CAMPAIGN_START"
echo "   End Time: $CAMPAIGN_END"
echo ""
echo "🎯 ATTACK STAGES EXECUTED:"
echo "   ✅ Initial Access (Brute Force)"
echo "   ✅ Execution (PowerShell)"
echo "   ✅ Persistence (Accounts & Registry)"
echo "   ✅ Lateral Movement"
echo "   ✅ Data Exfiltration"
echo "   ✅ Cleanup & Coverage"
echo ""
echo "🔍 COMPREHENSIVE DETECTION ANALYSIS:"
echo "   # Overall threat landscape"
echo "   curl '$API_BASE/api/v1/security/hunt/comprehensive'"
echo ""
echo "   # APT kill chain correlation"
echo "   curl '$API_BASE/api/v1/security/hunt/apt-kill-chain'"
echo ""
echo "   # Individual stage analysis"
echo "   curl '$API_BASE/api/v1/security/threats/scan'"
echo ""
echo "📊 KIBANA DASHBOARDS:"
echo "   # Main security dashboard"
echo "   http://localhost:5601/app/discover#/?_g=(filters:!(),query:(language:kuery,query:'*'))"
echo ""
echo "   # Timeline analysis"
echo "   http://localhost:5601/app/discover#/?_g=(time:(from:now-2h,to:now),query:(language:kuery,query:'log_category:*'))"
echo ""
echo "💡 EXPECTED DETECTIONS:"
echo "   🚨 Brute force attack (75+ failed logins)"
echo "   🚨 Suspicious PowerShell execution (multiple patterns)"
echo "   🚨 Rapid account creation (persistence)"
echo "   🚨 Lateral movement across multiple hosts"
echo "   🚨 Large-scale data exfiltration"
echo "   🚨 Log tampering attempts"
echo "   🚨 Complete APT kill chain correlation"
echo ""
echo "🎯 This simulation demonstrates a realistic APT attack"
echo "   that should trigger multiple detection rules and"
echo "   provide comprehensive threat hunting data for analysis."