#!/bin/bash

##############################################################################
# Mimikatz-Style Credential Theft Attack Simulation
#
# Simulates:
# - LSASS memory dumping (credential extraction)
# - Pass-the-Hash (PtH) attacks
# - Pass-the-Ticket (PtT) Kerberos attacks
# - Golden Ticket attacks
# - DCSync attacks (AD replication abuse)
# - Credential spraying
# - Hash cracking attempts
#
# Covers APT Attacks:
# - Equifax Breach (credential theft)
# - DNC Hack (spear-phishing → credential theft)
# - Operation Aurora (credential dumping)
# - RSA SecurID (credential compromise)
#
# Detection Capabilities:
# - Windows Event ID 4624 (logon events with NTLM/Kerberos)
# - Windows Event ID 4625 (failed logon attempts)
# - Windows Event ID 4768 (Kerberos TGT request)
# - Windows Event ID 4769 (Kerberos service ticket)
# - Windows Event ID 4776 (NTLM authentication)
# - Windows Event ID 4688 (process creation - mimikatz.exe)
# - Windows Event ID 4673 (sensitive privilege use)
# - Windows Event ID 4672 (special privileges assigned)
##############################################################################

set -e

# Configuration
LOGSTASH_HOST="${LOGSTASH_HOST:-localhost}"
LOGSTASH_SYSLOG_PORT=514

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Attack metadata
ATTACKER_IP="185.220.102.55"
ATTACKER_USER="attacker"
DC_SERVER="DC01.corp.local"
TARGET_USERS=("Administrator" "john.doe" "sarah.admin" "dbadmin" "svc_sql" "backup_admin")
WORKSTATIONS=("WKS-ADMIN.corp.local" "WKS-HR01.corp.local" "WKS-IT02.corp.local" "WKS-FIN01.corp.local")

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

##############################################################################
# Stage 1: LSASS Memory Dumping (Mimikatz)
##############################################################################

stage1_lsass_dumping() {
    echo -e "${YELLOW}[Stage 1/7]${NC} LSASS Memory Dumping (Credential Extraction)..."

    # Event ID 4688: Mimikatz process execution
    send_windows_event "4688" 1 "${WORKSTATIONS[0]}" "$ATTACKER_USER" "$ATTACKER_IP" \
        "ProcessName=C:\\Users\\$ATTACKER_USER\\Downloads\\mimikatz.exe CommandLine=\"mimikatz.exe privilege::debug sekurlsa::logonpasswords\" ParentProcess=cmd.exe - Mimikatz Execution"
    echo -e "${GREEN}✓${NC} Mimikatz executed"
    sleep 0.3

    # Event ID 4673: Sensitive privilege use (SeDebugPrivilege)
    send_windows_event "4673" 1 "${WORKSTATIONS[0]}" "$ATTACKER_USER" "$ATTACKER_IP" \
        "PrivilegeName=SeDebugPrivilege ProcessName=C:\\Users\\$ATTACKER_USER\\Downloads\\mimikatz.exe - Debug Privilege Enabled"
    echo -e "${GREEN}✓${NC} Debug privilege enabled"
    sleep 0.3

    # Event ID 4656: LSASS handle opened
    send_windows_event "4656" 1 "${WORKSTATIONS[0]}" "$ATTACKER_USER" "$ATTACKER_IP" \
        "ObjectType=Process ObjectName=lsass.exe AccessMask=0x1410 ProcessName=mimikatz.exe - LSASS Memory Access"
    echo -e "${GREEN}✓${NC} LSASS memory accessed"
    sleep 0.3

    # Alternative: Process dump using built-in tools
    send_windows_event "4688" 2 "${WORKSTATIONS[0]}" "$ATTACKER_USER" "$ATTACKER_IP" \
        "ProcessName=C:\\Windows\\System32\\taskmgr.exe CommandLine=\"taskmgr.exe /dump lsass.exe\" - LSASS Process Dump"
    echo -e "${GREEN}✓${NC} LSASS dumped via TaskManager"

    echo -e "${GREEN}✓${NC} Stage 1 complete: 4 credential extraction events"
}

##############################################################################
# Stage 2: Pass-the-Hash (PtH) Attacks
##############################################################################

stage2_pass_the_hash() {
    echo -e "${YELLOW}[Stage 2/7]${NC} Pass-the-Hash (PtH) Authentication..."

    for i in {0..3}; do
        local target_user="${TARGET_USERS[$i]}"
        local target_host="${WORKSTATIONS[$((i % ${#WORKSTATIONS[@]}))]}"

        # Event ID 4776: NTLM authentication with stolen hash
        send_windows_event "4776" 3 "$DC_SERVER" "$target_user" "$ATTACKER_IP" \
            "AuthenticationPackage=NTLM Workstation=${WORKSTATIONS[0]} Status=0xC0000064 - PtH Attack Detected"
        echo -e "${GREEN}✓${NC} PtH attempt: $target_user → $target_host"
        sleep 0.4

        # Event ID 4624: Successful network logon with NTLM (Type 3)
        send_windows_event "4624" 3 "$target_host" "$target_user" "$ATTACKER_IP" \
            "LogonType=3 AuthenticationPackage=NTLM LogonGuid={00000000-0000-0000-0000-000000000000} - Pass-the-Hash Logon"
        echo -e "${GREEN}✓${NC} PtH successful: $target_user on $target_host"
        sleep 0.3
    done

    echo -e "${GREEN}✓${NC} Stage 2 complete: 8 Pass-the-Hash events (4 attacks)"
}

##############################################################################
# Stage 3: Kerberos Ticket Attacks (Pass-the-Ticket)
##############################################################################

stage3_pass_the_ticket() {
    echo -e "${YELLOW}[Stage 3/7]${NC} Pass-the-Ticket (Kerberos Attacks)..."

    for i in {0..2}; do
        local target_user="${TARGET_USERS[$i]}"

        # Event ID 4768: Kerberos TGT request with unusual encryption
        send_windows_event "4768" 3 "$DC_SERVER" "$target_user" "$ATTACKER_IP" \
            "TicketEncryptionType=0x17 TicketOptions=0x40810010 IpAddress=$ATTACKER_IP PreAuthType=0 - Suspicious TGT Request"
        echo -e "${GREEN}✓${NC} TGT requested: $target_user"
        sleep 0.3

        # Event ID 4769: Kerberos service ticket request
        send_windows_event "4769" 3 "$DC_SERVER" "$target_user" "$ATTACKER_IP" \
            "ServiceName=cifs/${WORKSTATIONS[0]} TicketEncryptionType=0x17 IpAddress=$ATTACKER_IP - Service Ticket Request"
        echo -e "${GREEN}✓${NC} Service ticket: cifs/${WORKSTATIONS[0]}"
        sleep 0.3
    done

    echo -e "${GREEN}✓${NC} Stage 3 complete: 6 Kerberos ticket events"
}

##############################################################################
# Stage 4: Golden Ticket Attack (Persistence)
##############################################################################

stage4_golden_ticket() {
    echo -e "${YELLOW}[Stage 4/7]${NC} Golden Ticket Attack (Domain Persistence)..."

    # Event ID 4624: Logon with suspicious Kerberos ticket
    send_windows_event "4624" 1 "$DC_SERVER" "krbtgt" "$ATTACKER_IP" \
        "LogonType=3 AuthenticationPackage=Kerberos TicketLifetime=10years LogonGuid={00000000-0000-0000-0000-000000000000} - Golden Ticket Logon"
    echo -e "${GREEN}✓${NC} Golden ticket created (krbtgt hash)"
    sleep 0.3

    # Event ID 4768: TGT request with lifetime anomaly
    send_windows_event "4768" 1 "$DC_SERVER" "Administrator" "$ATTACKER_IP" \
        "TicketEncryptionType=0x12 TicketLifetime=87600h IpAddress=$ATTACKER_IP Status=0x0 - Golden Ticket TGT"
    echo -e "${GREEN}✓${NC} Golden ticket TGT (lifetime: 10 years)"
    sleep 0.3

    # Event ID 4672: Special privileges assigned to attacker
    send_windows_event "4672" 1 "${WORKSTATIONS[0]}" "$ATTACKER_USER" "$ATTACKER_IP" \
        "PrivilegeList=SeDebugPrivilege SeImpersonatePrivilege SeTcbPrivilege - Golden Ticket Privileges"
    echo -e "${GREEN}✓${NC} Domain admin privileges obtained"

    echo -e "${GREEN}✓${NC} Stage 4 complete: 3 Golden Ticket events"
}

##############################################################################
# Stage 5: DCSync Attack (AD Database Replication)
##############################################################################

stage5_dcsync() {
    echo -e "${YELLOW}[Stage 5/7]${NC} DCSync Attack (AD Credential Theft)..."

    # Event ID 4662: Directory Service Access (GUID for user object replication)
    send_windows_event "4662" 1 "$DC_SERVER" "$ATTACKER_USER" "$ATTACKER_IP" \
        "ObjectType=User Properties={1131f6aa-9c07-11d1-f79f-00c04fc2dcd2} AccessMask=0x100 - DCSync Replication Rights"
    echo -e "${GREEN}✓${NC} DCSync: Replication rights requested"
    sleep 0.3

    # Event ID 4662: DS-Replication-Get-Changes
    send_windows_event "4662" 1 "$DC_SERVER" "$ATTACKER_USER" "$ATTACKER_IP" \
        "ObjectType=domainDNS Properties={1131f6ad-9c07-11d1-f79f-00c04fc2dcd2} Operation=DS-Replication-Get-Changes - DCSync Domain Replication"
    echo -e "${GREEN}✓${NC} DCSync: Domain replication initiated"
    sleep 0.3

    # Extract all domain hashes
    for user in "${TARGET_USERS[@]}"; do
        send_windows_event "4662" 1 "$DC_SERVER" "$user" "$ATTACKER_IP" \
            "ObjectType=User ObjectName=CN=$user,CN=Users,DC=corp,DC=local AccessMask=0x100 - Hash Extracted via DCSync"
        echo -e "${GREEN}✓${NC} Hash extracted: $user"
        sleep 0.2
    done

    echo -e "${GREEN}✓${NC} Stage 5 complete: 8 DCSync events (6 hashes stolen)"
}

##############################################################################
# Stage 6: Credential Spraying
##############################################################################

stage6_credential_spraying() {
    echo -e "${YELLOW}[Stage 6/7]${NC} Credential Spraying (Password Guessing)..."

    local common_passwords=("Password123!" "Summer2024!" "Welcome1!" "Admin@123" "P@ssw0rd")

    for password_attempt in {1..3}; do
        for user in "${TARGET_USERS[@]}"; do
            # Event ID 4625: Failed logon (credential spray)
            send_windows_event "4625" 4 "$DC_SERVER" "$user" "$ATTACKER_IP" \
                "FailureReason=0xC000006A SubStatus=0xC000006A LogonType=3 - Credential Spray Attempt"
            sleep 0.1
        done
        echo -e "${GREEN}✓${NC} Password spray attempt $password_attempt (6 users)"
    done

    # One successful spray
    send_windows_event "4624" 3 "$DC_SERVER" "${TARGET_USERS[4]}" "$ATTACKER_IP" \
        "LogonType=3 AuthenticationPackage=NTLM - Credential Spray Success: ${TARGET_USERS[4]}"
    echo -e "${RED}✓${NC} Password found: ${TARGET_USERS[4]}"

    echo -e "${GREEN}✓${NC} Stage 6 complete: 19 credential spray events (18 failed + 1 success)"
}

##############################################################################
# Stage 7: Privilege Escalation via Stolen Credentials
##############################################################################

stage7_privilege_escalation() {
    echo -e "${YELLOW}[Stage 7/7]${NC} Privilege Escalation (Admin Token Theft)..."

    # Event ID 4672: Special privileges assigned after credential theft
    send_windows_event "4672" 2 "${WORKSTATIONS[0]}" "Administrator" "$ATTACKER_IP" \
        "PrivilegeList=SeDebugPrivilege SeBackupPrivilege SeRestorePrivilege SeTakeOwnershipPrivilege - Stolen Admin Token"
    echo -e "${GREEN}✓${NC} Administrator token stolen"
    sleep 0.3

    # Event ID 4648: Logon with explicit credentials (RunAs)
    send_windows_event "4648" 3 "${WORKSTATIONS[0]}" "$ATTACKER_USER" "$ATTACKER_IP" \
        "TargetUser=Administrator TargetServer=$DC_SERVER ProcessName=C:\\Windows\\System32\\runas.exe - RunAs with Stolen Creds"
    echo -e "${GREEN}✓${NC} RunAs executed with stolen credentials"
    sleep 0.3

    # Event ID 4624: Interactive admin logon
    send_windows_event "4624" 2 "$DC_SERVER" "Administrator" "$ATTACKER_IP" \
        "LogonType=10 AuthenticationPackage=Negotiate ElevatedToken=Yes - RemoteInteractive Admin Logon"
    echo -e "${GREEN}✓${NC} Remote Desktop admin access obtained"

    echo -e "${GREEN}✓${NC} Stage 7 complete: 3 privilege escalation events"
}

##############################################################################
# Main Execution
##############################################################################

main() {
    echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║    Mimikatz Credential Theft Simulation Starting      ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Attack Timeline:"
    echo "  [Stage 1] LSASS memory dumping (credential extraction)"
    echo "  [Stage 2] Pass-the-Hash (PtH) attacks"
    echo "  [Stage 3] Pass-the-Ticket (Kerberos abuse)"
    echo "  [Stage 4] Golden Ticket (domain persistence)"
    echo "  [Stage 5] DCSync (AD database theft)"
    echo "  [Stage 6] Credential spraying"
    echo "  [Stage 7] Privilege escalation"
    echo ""

    stage1_lsass_dumping
    echo ""
    stage2_pass_the_hash
    echo ""
    stage3_pass_the_ticket
    echo ""
    stage4_golden_ticket
    echo ""
    stage5_dcsync
    echo ""
    stage6_credential_spraying
    echo ""
    stage7_privilege_escalation
    echo ""

    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Mimikatz Credential Theft Simulation Complete!       ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Summary:"
    echo "  • ${GREEN}4${NC} LSASS memory dumps (Mimikatz execution)"
    echo "  • ${GREEN}8${NC} Pass-the-Hash attacks (4 users compromised)"
    echo "  • ${GREEN}6${NC} Kerberos ticket attacks (Pass-the-Ticket)"
    echo "  • ${GREEN}3${NC} Golden Ticket events (domain persistence)"
    echo "  • ${GREEN}8${NC} DCSync events (6 domain hashes stolen)"
    echo "  • ${GREEN}19${NC} Credential spray attempts (1 success)"
    echo "  • ${GREEN}3${NC} Privilege escalation events"
    echo ""
    echo "Total: ${GREEN}51${NC} credential theft attack events sent to Logstash"
    echo ""
    echo "Compromised Credentials:"
    for user in "${TARGET_USERS[@]}"; do
        echo "  - ${RED}✗${NC} $user (NTLM hash stolen)"
    done
    echo ""
    echo "Check logs in Elasticsearch: ${GREEN}security-*${NC}"
    echo ""
    echo "${CYAN}APT Attacks Covered:${NC}"
    echo "  ✓ Equifax Breach (credential theft)"
    echo "  ✓ DNC Hack (credential spraying)"
    echo "  ✓ Operation Aurora (credential dumping)"
    echo "  ✓ RSA SecurID (credential compromise)"
    echo ""
}

main
