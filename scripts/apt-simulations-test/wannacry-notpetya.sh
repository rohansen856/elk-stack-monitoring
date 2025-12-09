#!/bin/bash

##############################################################################
# WannaCry / NotPetya Ransomware Attack Simulation
#
# Simulates:
# - EternalBlue SMB exploitation (CVE-2017-0144)
# - Lateral movement via SMB
# - Shadow copy deletion (vssadmin)
# - Boot record tampering (bcdedit)
# - Backup deletion (wbadmin)
# - Service installation (persistence)
# - File encryption behavior
# - Ransomware C2 communication
#
# Detection Capabilities:
# - Windows Event ID 7045 (service installation)
# - Windows Event ID 4688 (process creation)
# - Windows Event ID 4624/4625 (lateral movement)
# - Network traffic to C2 domains
# - Suspicious command-line arguments
##############################################################################

set -e

# Configuration
LOGSTASH_HOST="${LOGSTASH_HOST:-localhost}"
LOGSTASH_SYSLOG_PORT=514

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Attack metadata
ATTACKER_IP="185.220.101.88"
INITIAL_VICTIM="WKS-001.corp.local"
RANSOMWARE_SERVICE="mssecsvc2.0"
C2_DOMAIN="iuqerfsodp9ifjaposdfjhgosurijfaewrwergwea.com"  # WannaCry kill-switch domain
BITCOIN_WALLET="13AM4VW2dhxYgXeQepoHkHSQuy6NgaEb94"

# Arrays for realistic variety
VICTIM_HOSTS=("WKS-001.corp.local" "WKS-002.corp.local" "WKS-003.corp.local" "SRV-FILE01.corp.local" "SRV-DB01.corp.local" "WKS-ADMIN.corp.local")
ETERNALBLUE_PORTS=(445 139)
RANSOMWARE_EXTENSIONS=(".WNCRY" ".WNCRYT" ".encrypted" ".locked")

##############################################################################
# Helper Functions
##############################################################################

send_windows_event() {
    local event_id=$1
    local severity=$2
    local computer=$3
    local user=$4
    local source_ip=$5
    local message=$6

    local facility=10  # Windows Event Log
    local priority=$((facility * 8 + severity))
    local timestamp=$(date '+%b %d %H:%M:%S')

    local syslog_msg="<${priority}>${timestamp} ${computer} Microsoft-Windows-Security-Auditing: EventID=${event_id} User=${user} Source=${source_ip} ${message}"

    echo "$syslog_msg" | nc -u -w1 "$LOGSTASH_HOST" "$LOGSTASH_SYSLOG_PORT"
}

send_network_log() {
    local device=$1
    local severity=$2
    local message=$3

    local facility=23  # Network device
    local priority=$((facility * 8 + severity))
    local timestamp=$(date '+%b %d %H:%M:%S')

    local syslog_msg="<${priority}>${timestamp} ${device} ${message}"

    echo "$syslog_msg" | nc -u -w1 "$LOGSTASH_HOST" "$LOGSTASH_SYSLOG_PORT"
}

##############################################################################
# Stage 1: Initial Infection (EternalBlue Exploitation)
##############################################################################

stage1_eternalblue_scan() {
    echo -e "${YELLOW}[Stage 1/7]${NC} EternalBlue SMB Port Scan..."

    for port in "${ETERNALBLUE_PORTS[@]}"; do
        for i in {1..5}; do
            local target_host="${VICTIM_HOSTS[$((i % ${#VICTIM_HOSTS[@]}))]}"

            # Firewall log: Port scan detection
            send_network_log "firewall-01" 4 "%ASA-4-106023: Deny tcp src outside:${ATTACKER_IP}/${port} dst inside:192.168.1.$((100 + i))/445 by access-group \"outside_in\" - EternalBlue Scan"

            echo -e "${GREEN}✓${NC} Port ${port} scan logged"
            sleep 0.2
        done
    done

    echo -e "${GREEN}✓${NC} Stage 1 complete: 10 EternalBlue scans detected"
}

##############################################################################
# Stage 2: Successful Exploitation + DoublePulsar Backdoor
##############################################################################

stage2_exploitation() {
    echo -e "${YELLOW}[Stage 2/7]${NC} EternalBlue Exploitation + DoublePulsar Installation..."

    # Event ID 4688: DoublePulsar backdoor process creation
    send_windows_event "4688" 2 "$INITIAL_VICTIM" "SYSTEM" "$ATTACKER_IP" \
        "ProcessName=C:\\Windows\\System32\\lsass.exe CommandLine=\"lsass.exe -m DoublePulsar\" ParentProcess=services.exe - DoublePulsar Implant"
    echo -e "${GREEN}✓${NC} DoublePulsar backdoor installed"
    sleep 0.3

    # Event ID 7045: Ransomware service installation
    send_windows_event "7045" 2 "$INITIAL_VICTIM" "SYSTEM" "$ATTACKER_IP" \
        "ServiceName=${RANSOMWARE_SERVICE} ServiceFile=C:\\Windows\\mssecsvc.exe ServiceType=UserMode - WannaCry Service"
    echo -e "${GREEN}✓${NC} WannaCry service installed"
    sleep 0.3

    # C2 Communication: Kill-switch check
    send_network_log "firewall-01" 2 "THREAT: DNS query to ${C2_DOMAIN} from ${INITIAL_VICTIM} - WannaCry Kill-Switch Check"
    echo -e "${GREEN}✓${NC} Kill-switch DNS query logged"

    echo -e "${GREEN}✓${NC} Stage 2 complete: System compromised"
}

##############################################################################
# Stage 3: Shadow Copy Deletion (Anti-Recovery)
##############################################################################

stage3_shadow_deletion() {
    echo -e "${YELLOW}[Stage 3/7]${NC} Shadow Copy Deletion (vssadmin)..."

    # Event ID 4688: vssadmin delete shadows
    send_windows_event "4688" 1 "$INITIAL_VICTIM" "SYSTEM" "127.0.0.1" \
        "ProcessName=C:\\Windows\\System32\\vssadmin.exe CommandLine=\"vssadmin.exe delete shadows /all /quiet\" - Shadow Copy Deletion"
    echo -e "${GREEN}✓${NC} Shadow copies deleted"
    sleep 0.3

    # Event ID 4688: bcdedit disable recovery
    send_windows_event "4688" 1 "$INITIAL_VICTIM" "SYSTEM" "127.0.0.1" \
        "ProcessName=C:\\Windows\\System32\\bcdedit.exe CommandLine=\"bcdedit.exe /set {default} recoveryenabled No\" - Boot Recovery Disabled"
    echo -e "${GREEN}✓${NC} Boot recovery disabled"
    sleep 0.3

    # Event ID 4688: wbadmin delete backup
    send_windows_event "4688" 1 "$INITIAL_VICTIM" "SYSTEM" "127.0.0.1" \
        "ProcessName=C:\\Windows\\System32\\wbadmin.exe CommandLine=\"wbadmin delete catalog -quiet\" - Backup Catalog Deleted"
    echo -e "${GREEN}✓${NC} Backup catalog deleted"

    echo -e "${GREEN}✓${NC} Stage 3 complete: Recovery disabled"
}

##############################################################################
# Stage 4: Lateral Movement (Worm Behavior)
##############################################################################

stage4_lateral_movement() {
    echo -e "${YELLOW}[Stage 4/7]${NC} Lateral Movement via SMB..."

    for i in {1..6}; do
        local target_host="${VICTIM_HOSTS[$i]}"

        # Event ID 4624: Successful logon (worm spreading)
        send_windows_event "4624" 3 "$target_host" "SYSTEM" "${VICTIM_HOSTS[0]}" \
            "LogonType=3 ProcessName=\\Device\\Mup\\${VICTIM_HOSTS[0]}\\IPC$ - WannaCry Worm Spread"

        # Event ID 4688: Ransomware process started on remote system
        send_windows_event "4688" 2 "$target_host" "SYSTEM" "${VICTIM_HOSTS[0]}" \
            "ProcessName=C:\\Windows\\tasksche.exe CommandLine=\"tasksche.exe /i\" - WannaCry Payload"

        # Event ID 7045: Service installation on remote system
        send_windows_event "7045" 2 "$target_host" "SYSTEM" "${VICTIM_HOSTS[0]}" \
            "ServiceName=${RANSOMWARE_SERVICE} ServiceFile=C:\\Windows\\mssecsvc.exe - WannaCry Service"

        echo -e "${GREEN}✓${NC} Infected: $target_host"
        sleep 0.4
    done

    echo -e "${GREEN}✓${NC} Stage 4 complete: 6 systems infected"
}

##############################################################################
# Stage 5: File Encryption
##############################################################################

stage5_encryption() {
    echo -e "${YELLOW}[Stage 5/7]${NC} File Encryption (Ransomware Payload)..."

    for host in "${VICTIM_HOSTS[@]}"; do
        # Event ID 4688: File encryption process
        send_windows_event "4688" 1 "$host" "SYSTEM" "127.0.0.1" \
            "ProcessName=C:\\Windows\\tasksche.exe CommandLine=\"tasksche.exe -m security -ky 0x[REDACTED]\" - WannaCry Encryption"

        # Event ID 5140: Network share access (spreading via shares)
        send_windows_event "5140" 3 "$host" "SYSTEM" "${VICTIM_HOSTS[0]}" \
            "ShareName=\\\\*\\C$ SharePath=C:\\Users\\*\\Documents - Ransomware File Access"

        echo -e "${GREEN}✓${NC} Encrypting: $host"
        sleep 0.3
    done

    echo -e "${GREEN}✓${NC} Stage 5 complete: Files encrypted"
}

##############################################################################
# Stage 6: Ransom Note Deployment
##############################################################################

stage6_ransom_note() {
    echo -e "${YELLOW}[Stage 6/7]${NC} Ransom Note Deployment..."

    for host in "${VICTIM_HOSTS[@]}"; do
        # Event ID 4688: Ransom note creation
        send_windows_event "4688" 3 "$host" "SYSTEM" "127.0.0.1" \
            "ProcessName=C:\\Windows\\System32\\cmd.exe CommandLine=\"cmd.exe /c echo @WanaDecryptor@.exe > @Please_Read_Me@.txt\" - Ransom Note"

        echo -e "${GREEN}✓${NC} Ransom note: $host"
        sleep 0.2
    done

    echo -e "${GREEN}✓${NC} Stage 6 complete: Ransom notes deployed"
}

##############################################################################
# Stage 7: C2 Communication + Bitcoin Payment Request
##############################################################################

stage7_c2_communication() {
    echo -e "${YELLOW}[Stage 7/7]${NC} C2 Communication + Payment Request..."

    for i in {1..5}; do
        local victim="${VICTIM_HOSTS[$((i % ${#VICTIM_HOSTS[@]}))]}"

        # Tor C2 beaconing
        send_network_log "firewall-01" 2 "THREAT: Connection to Tor node 185.220.101.$((80 + i)):9001 from ${victim} - WannaCry C2 Beacon"

        # Bitcoin payment check
        send_network_log "firewall-01" 2 "THREAT: HTTPS connection to blockchain.info from ${victim} - Bitcoin Wallet Check: ${BITCOIN_WALLET}"

        echo -e "${GREEN}✓${NC} C2 beacon $i"
        sleep 0.3
    done

    echo -e "${GREEN}✓${NC} Stage 7 complete: C2 active, payment requested"
}

##############################################################################
# Main Execution
##############################################################################

main() {
    echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║        WannaCry / NotPetya Simulation Starting        ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Attack Timeline:"
    echo "  [Stage 1] EternalBlue SMB port scanning"
    echo "  [Stage 2] Exploitation + DoublePulsar backdoor"
    echo "  [Stage 3] Shadow copy deletion (anti-recovery)"
    echo "  [Stage 4] Lateral movement (worm behavior)"
    echo "  [Stage 5] File encryption"
    echo "  [Stage 6] Ransom note deployment"
    echo "  [Stage 7] C2 communication + payment request"
    echo ""

    stage1_eternalblue_scan
    echo ""
    stage2_exploitation
    echo ""
    stage3_shadow_deletion
    echo ""
    stage4_lateral_movement
    echo ""
    stage5_encryption
    echo ""
    stage6_ransom_note
    echo ""
    stage7_c2_communication
    echo ""

    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  WannaCry / NotPetya Simulation Complete!             ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Summary:"
    echo "  • ${GREEN}10${NC} EternalBlue port scans"
    echo "  • ${GREEN}1${NC} DoublePulsar backdoor installation"
    echo "  • ${GREEN}1${NC} Ransomware service installed"
    echo "  • ${GREEN}3${NC} Anti-recovery commands (vssadmin, bcdedit, wbadmin)"
    echo "  • ${GREEN}6${NC} systems infected via lateral movement"
    echo "  • ${GREEN}6${NC} encryption processes"
    echo "  • ${GREEN}6${NC} ransom notes deployed"
    echo "  • ${GREEN}10${NC} C2 communication attempts"
    echo ""
    echo "Total: ${GREEN}43${NC} ransomware attack events sent to Logstash"
    echo ""
    echo "Check logs in Elasticsearch: ${GREEN}security-*${NC}"
    echo ""
}

main
