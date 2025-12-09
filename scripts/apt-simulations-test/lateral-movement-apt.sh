#!/bin/bash

##############################################################################
# Advanced Lateral Movement Attack Simulation
#
# Simulates:
# - SMB/CIFS lateral movement (PsExec, WMI, Admin shares)
# - RDP session hijacking and lateral movement
# - WinRM remote command execution
# - DCOM lateral movement
# - Scheduled tasks for remote execution
# - Service installation on remote systems
# - PowerShell remoting abuse
# - SSH lateral movement (Linux systems)
#
# Covers APT Attacks:
# - SolarWinds (APT29) - Lateral movement across networks
# - NotPetya - Worm-like lateral spread
# - Colonial Pipeline - Ransomware lateral movement
# - DNC Hack (APT28) - Network traversal
#
# Detection Capabilities:
# - Windows Event ID 4624 (Logon - Types 3, 10, 11)
# - Windows Event ID 4648 (Explicit credential logon)
# - Windows Event ID 4672 (Special privileges assigned)
# - Windows Event ID 5140 (Network share access)
# - Windows Event ID 4697 (Service installed)
# - Windows Event ID 4698 (Scheduled task created)
# - Windows Event ID 7045 (Service created)
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
BLUE='\033[0;34m'
NC='\033[0m'

# Attack metadata
INITIAL_FOOTHOLD="WKS-FINANCE01.corp.local"
ATTACKER_IP="192.168.1.155"
COMPROMISED_USER="jane.smith"

# Target systems
TARGETS=(
    "WKS-HR01.corp.local"
    "WKS-IT02.corp.local"
    "SRV-FILE01.corp.local"
    "SRV-EXCHANGE01.corp.local"
    "DC02.corp.local"
    "SRV-DB-PROD.corp.local"
    "WKS-EXEC01.corp.local"
    "SRV-BACKUP01.corp.local"
)

# Admin accounts for privilege escalation
ADMIN_ACCOUNTS=("domain_admin" "backup_admin" "svc_exchange" "IT_Admin")

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

    local facility=10
    local priority=$((facility * 8 + severity))
    local timestamp=$(date '+%b %d %H:%M:%S')

    local syslog_msg="<${priority}>${timestamp} ${computer} Microsoft-Windows-Security-Auditing: EventID=${event_id} User=${user} Source=${source_ip} ${message}"

    echo "$syslog_msg" | nc -u -w1 "$LOGSTASH_HOST" "$LOGSTASH_SYSLOG_PORT"
}

##############################################################################
# Stage 1: SMB Lateral Movement (PsExec / Admin Shares)
##############################################################################

stage1_smb_lateral_movement() {
    echo -e "${YELLOW}[Stage 1/8]${NC} SMB/PsExec Lateral Movement..."

    for i in {0..3}; do
        local target="${TARGETS[$i]}"

        # Event ID 4624: Network logon (Type 3) - SMB connection
        send_windows_event "4624" 3 "$target" "$COMPROMISED_USER" "$ATTACKER_IP" \
            "LogonType=3 AuthenticationPackage=NTLM WorkstationName=$INITIAL_FOOTHOLD LogonProcess=NtLmSsp - SMB Lateral Movement"
        echo -e "${GREEN}✓${NC} SMB connection: $target"
        sleep 0.3

        # Event ID 5140: Network share accessed (ADMIN$, C$, IPC$)
        send_windows_event "5140" 3 "$target" "$COMPROMISED_USER" "$ATTACKER_IP" \
            "ShareName=\\\\${target}\\ADMIN$ SharePath=C:\\Windows AccessMask=0x1 - Admin Share Access"
        echo -e "${GREEN}✓${NC} Admin share accessed: \\\\${target}\\ADMIN$"
        sleep 0.3

        # Event ID 7045: Service installed (PsExec service)
        send_windows_event "7045" 2 "$target" "SYSTEM" "$ATTACKER_IP" \
            "ServiceName=PSEXESVC ServiceFile=%SystemRoot%\\PSEXESVC.exe ServiceType=UserMode StartType=Demand - PsExec Service"
        echo -e "${GREEN}✓${NC} PsExec service installed: $target"
        sleep 0.3
    done

    echo -e "${GREEN}✓${NC} Stage 1 complete: 12 SMB lateral movement events (4 systems)"
}

##############################################################################
# Stage 2: RDP Lateral Movement
##############################################################################

stage2_rdp_lateral_movement() {
    echo -e "${YELLOW}[Stage 2/8]${NC} RDP Remote Desktop Lateral Movement..."

    for i in {4..5}; do
        local target="${TARGETS[$i]}"

        # Event ID 4624: Interactive logon (Type 10) - RDP
        send_windows_event "4624" 2 "$target" "$COMPROMISED_USER" "$ATTACKER_IP" \
            "LogonType=10 AuthenticationPackage=Negotiate LogonProcess=User32 - RDP RemoteInteractive Logon"
        echo -e "${GREEN}✓${NC} RDP login: $target"
        sleep 0.3

        # Event ID 4648: Logon with explicit credentials (RDP authentication)
        send_windows_event "4648" 3 "$target" "$COMPROMISED_USER" "$ATTACKER_IP" \
            "TargetUserName=${ADMIN_ACCOUNTS[0]} TargetServer=$target ProcessName=C:\\Windows\\System32\\mstsc.exe - RDP Explicit Creds"
        echo -e "${GREEN}✓${NC} Explicit credentials used: ${ADMIN_ACCOUNTS[0]}"
        sleep 0.3

        # Event ID 4672: Special privileges assigned (admin RDP session)
        send_windows_event "4672" 2 "$target" "${ADMIN_ACCOUNTS[0]}" "$ATTACKER_IP" \
            "PrivilegeList=SeBackupPrivilege SeRestorePrivilege SeDebugPrivilege - RDP Admin Session"
        echo -e "${GREEN}✓${NC} Admin privileges obtained: $target"
        sleep 0.3
    done

    echo -e "${GREEN}✓${NC} Stage 2 complete: 6 RDP lateral movement events (2 systems)"
}

##############################################################################
# Stage 3: WinRM / PowerShell Remoting
##############################################################################

stage3_winrm_lateral_movement() {
    echo -e "${YELLOW}[Stage 3/8]${NC} WinRM/PowerShell Remoting Lateral Movement..."

    for i in {2..4}; do
        local target="${TARGETS[$i]}"

        # Event ID 4624: Network logon (Type 3) with WinRM
        send_windows_event "4624" 3 "$target" "$COMPROMISED_USER" "$ATTACKER_IP" \
            "LogonType=3 AuthenticationPackage=Kerberos ProcessName=C:\\Windows\\System32\\wsmprovhost.exe - WinRM Session"
        echo -e "${GREEN}✓${NC} WinRM session: $target"
        sleep 0.3

        # Event ID 4688: Process creation via PowerShell remoting
        send_windows_event "4688" 2 "$target" "$COMPROMISED_USER" "$ATTACKER_IP" \
            "ProcessName=C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe CommandLine=\"powershell.exe -ExecutionPolicy Bypass -Command Invoke-Mimikatz\" ParentProcess=wsmprovhost.exe - Remote PS Execution"
        echo -e "${GREEN}✓${NC} PowerShell remote execution: $target"
        sleep 0.3
    done

    echo -e "${GREEN}✓${NC} Stage 3 complete: 6 WinRM lateral movement events (3 systems)"
}

##############################################################################
# Stage 4: WMI Lateral Movement
##############################################################################

stage4_wmi_lateral_movement() {
    echo -e "${YELLOW}[Stage 4/8]${NC} WMI (Windows Management Instrumentation) Lateral Movement..."

    for i in {5..6}; do
        local target="${TARGETS[$i]}"

        # Event ID 4624: Network logon via WMI
        send_windows_event "4624" 3 "$target" "${ADMIN_ACCOUNTS[1]}" "$ATTACKER_IP" \
            "LogonType=3 LogonProcess=NtLmSsp AuthenticationPackage=NTLM ProcessName=C:\\Windows\\System32\\wbem\\WmiPrvSE.exe - WMI Lateral"
        echo -e "${GREEN}✓${NC} WMI connection: $target"
        sleep 0.3

        # Event ID 4688: Process spawned via WMI
        send_windows_event "4688" 2 "$target" "${ADMIN_ACCOUNTS[1]}" "$ATTACKER_IP" \
            "ProcessName=C:\\Windows\\System32\\cmd.exe CommandLine=\"cmd.exe /c whoami && net user\" ParentProcess=WmiPrvSE.exe - WMI Command Exec"
        echo -e "${GREEN}✓${NC} WMI command executed: $target"
        sleep 0.3

        # Event ID 4672: Special privileges via WMI
        send_windows_event "4672" 2 "$target" "${ADMIN_ACCOUNTS[1]}" "$ATTACKER_IP" \
            "PrivilegeList=SeDebugPrivilege SeTcbPrivilege - WMI Admin Privileges"
        echo -e "${GREEN}✓${NC} WMI admin privileges: $target"
        sleep 0.3
    done

    echo -e "${GREEN}✓${NC} Stage 4 complete: 6 WMI lateral movement events (2 systems)"
}

##############################################################################
# Stage 5: DCOM Lateral Movement
##############################################################################

stage5_dcom_lateral_movement() {
    echo -e "${YELLOW}[Stage 5/8]${NC} DCOM (Distributed COM) Lateral Movement..."

    local target="${TARGETS[6]}"

    # Event ID 4624: DCOM network logon
    send_windows_event "4624" 3 "$target" "${ADMIN_ACCOUNTS[2]}" "$ATTACKER_IP" \
        "LogonType=3 AuthenticationPackage=Kerberos ProcessName=C:\\Windows\\System32\\svchost.exe ServiceName=DcomLaunch - DCOM Lateral"
    echo -e "${GREEN}✓${NC} DCOM connection: $target"
    sleep 0.3

    # Event ID 4688: MMC20.Application DCOM execution
    send_windows_event "4688" 2 "$target" "${ADMIN_ACCOUNTS[2]}" "$ATTACKER_IP" \
        "ProcessName=C:\\Windows\\System32\\mmc.exe CommandLine=\"C:\\Windows\\System32\\mmc.exe -Embedding\" ParentProcess=svchost.exe - DCOM MMC Exec"
    echo -e "${GREEN}✓${NC} DCOM MMC execution: $target"
    sleep 0.3

    # Event ID 4688: Malicious payload via DCOM
    send_windows_event "4688" 1 "$target" "${ADMIN_ACCOUNTS[2]}" "$ATTACKER_IP" \
        "ProcessName=C:\\Windows\\System32\\cmd.exe CommandLine=\"cmd.exe /c powershell -enc [base64]\" ParentProcess=mmc.exe - DCOM Payload"
    echo -e "${GREEN}✓${NC} DCOM payload executed: $target"

    echo -e "${GREEN}✓${NC} Stage 5 complete: 3 DCOM lateral movement events"
}

##############################################################################
# Stage 6: Scheduled Task Lateral Movement
##############################################################################

stage6_scheduled_task_lateral() {
    echo -e "${YELLOW}[Stage 6/8]${NC} Scheduled Task Lateral Movement..."

    for i in {0..2}; do
        local target="${TARGETS[$i]}"

        # Event ID 4698: Scheduled task created
        send_windows_event "4698" 2 "$target" "${ADMIN_ACCOUNTS[3]}" "$ATTACKER_IP" \
            "TaskName=\\Microsoft\\Windows\\UpdateTask TaskContent=C:\\Windows\\System32\\payload.exe - Remote Scheduled Task"
        echo -e "${GREEN}✓${NC} Scheduled task created: $target"
        sleep 0.3

        # Event ID 4688: Task execution
        send_windows_event "4688" 2 "$target" "SYSTEM" "$ATTACKER_IP" \
            "ProcessName=C:\\Windows\\System32\\payload.exe CommandLine=\"payload.exe /elevated\" ParentProcess=taskeng.exe - Task Execution"
        echo -e "${GREEN}✓${NC} Task executed: $target"
        sleep 0.3
    done

    echo -e "${GREEN}✓${NC} Stage 6 complete: 6 scheduled task lateral events (3 systems)"
}

##############################################################################
# Stage 7: Linux SSH Lateral Movement (Cross-Platform)
##############################################################################

stage7_ssh_lateral_movement() {
    echo -e "${YELLOW}[Stage 7/8]${NC} SSH Lateral Movement (Linux Systems)..."

    local linux_targets=("srv-web01.corp.local" "srv-app02.corp.local" "srv-db-linux.corp.local")

    for target in "${linux_targets[@]}"; do
        # Syslog: SSH successful authentication
        local facility=4  # auth
        local severity=6  # info
        local priority=$((facility * 8 + severity))
        local timestamp=$(date '+%b %d %H:%M:%S')

        local syslog_msg="<${priority}>${timestamp} ${target} sshd[12345]: Accepted publickey for root from ${ATTACKER_IP} port 54321 ssh2: RSA SHA256:abcdef123456 - SSH Lateral"
        echo "$syslog_msg" | nc -u -w1 "$LOGSTASH_HOST" "$LOGSTASH_SYSLOG_PORT"
        echo -e "${GREEN}✓${NC} SSH login: $target"
        sleep 0.3

        # Sudo privilege escalation
        syslog_msg="<${priority}>${timestamp} ${target} sudo: $COMPROMISED_USER : TTY=pts/0 ; PWD=/home/$COMPROMISED_USER ; USER=root ; COMMAND=/bin/bash"
        echo "$syslog_msg" | nc -u -w1 "$LOGSTASH_HOST" "$LOGSTASH_SYSLOG_PORT"
        echo -e "${GREEN}✓${NC} Sudo escalation: $target"
        sleep 0.3
    done

    echo -e "${GREEN}✓${NC} Stage 7 complete: 6 SSH lateral movement events (3 Linux systems)"
}

##############################################################################
# Stage 8: Pivoting Through Compromised Systems
##############################################################################

stage8_network_pivoting() {
    echo -e "${YELLOW}[Stage 8/8]${NC} Network Pivoting (Multi-Hop Lateral Movement)..."

    # Pivot chain: WKS -> SRV-FILE -> DC -> DB Server
    local pivot_chain=("$INITIAL_FOOTHOLD" "${TARGETS[2]}" "${TARGETS[4]}" "${TARGETS[5]}")

    for i in {0..2}; do
        local source="${pivot_chain[$i]}"
        local target="${pivot_chain[$((i + 1))]}"

        # Event ID 4624: Multi-hop logon
        send_windows_event "4624" 3 "$target" "$COMPROMISED_USER" "$source" \
            "LogonType=3 LogonProcess=NtLmSsp NetworkAccount=$source - Pivoted Logon from $source"
        echo -e "${GREEN}✓${NC} Pivot: $source → $target"
        sleep 0.3

        # Event ID 5140: Share access via pivot
        send_windows_event "5140" 3 "$target" "$COMPROMISED_USER" "$source" \
            "ShareName=\\\\${target}\\C$ SharePath=C:\\ RelativeTargetName=Windows\\System32 - Pivot Share Access"
        echo -e "${GREEN}✓${NC} Pivot share access: $target"
        sleep 0.3
    done

    # Final target reached: Database server
    echo -e "${CYAN}✓${NC} ${RED}CRITICAL:${NC} Database server reached via multi-hop pivot"
    send_windows_event "4624" 1 "${TARGETS[5]}" "${ADMIN_ACCOUNTS[0]}" "${TARGETS[4]}" \
        "LogonType=3 LogonProcess=Kerberos - FINAL TARGET: Database Server Compromised via Pivot Chain"
    sleep 0.3

    echo -e "${GREEN}✓${NC} Stage 8 complete: 7 network pivoting events"
}

##############################################################################
# Main Execution
##############################################################################

main() {
    echo -e "${RED}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║      Advanced Lateral Movement Simulation Starting    ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Attack Scenario: APT-style Network Traversal"
    echo "Initial Foothold: ${BLUE}$INITIAL_FOOTHOLD${NC}"
    echo "Compromised User: ${BLUE}$COMPROMISED_USER${NC}"
    echo "Attacker IP: ${BLUE}$ATTACKER_IP${NC}"
    echo ""
    echo "Attack Timeline:"
    echo "  [Stage 1] SMB/PsExec lateral movement (4 systems)"
    echo "  [Stage 2] RDP remote desktop access (2 systems)"
    echo "  [Stage 3] WinRM/PowerShell remoting (3 systems)"
    echo "  [Stage 4] WMI command execution (2 systems)"
    echo "  [Stage 5] DCOM lateral movement (1 system)"
    echo "  [Stage 6] Scheduled task persistence (3 systems)"
    echo "  [Stage 7] SSH lateral movement (3 Linux systems)"
    echo "  [Stage 8] Network pivoting (multi-hop)"
    echo ""

    stage1_smb_lateral_movement
    echo ""
    stage2_rdp_lateral_movement
    echo ""
    stage3_winrm_lateral_movement
    echo ""
    stage4_wmi_lateral_movement
    echo ""
    stage5_dcom_lateral_movement
    echo ""
    stage6_scheduled_task_lateral
    echo ""
    stage7_ssh_lateral_movement
    echo ""
    stage8_network_pivoting
    echo ""

    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Advanced Lateral Movement Simulation Complete!       ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Summary:"
    echo "  • ${GREEN}12${NC} SMB/PsExec lateral movements"
    echo "  • ${GREEN}6${NC} RDP remote desktop sessions"
    echo "  • ${GREEN}6${NC} WinRM/PowerShell remoting executions"
    echo "  • ${GREEN}6${NC} WMI command executions"
    echo "  • ${GREEN}3${NC} DCOM lateral movements"
    echo "  • ${GREEN}6${NC} Scheduled task lateral movements"
    echo "  • ${GREEN}6${NC} SSH lateral movements (Linux)"
    echo "  • ${GREEN}7${NC} Network pivoting (multi-hop)"
    echo ""
    echo "Total: ${GREEN}52${NC} lateral movement attack events sent to Logstash"
    echo ""
    echo "Compromised Systems:"
    for target in "${TARGETS[@]}"; do
        echo "  - ${RED}✗${NC} $target"
    done
    echo "  - ${RED}✗${NC} srv-web01.corp.local (Linux)"
    echo "  - ${RED}✗${NC} srv-app02.corp.local (Linux)"
    echo "  - ${RED}✗${NC} srv-db-linux.corp.local (Linux)"
    echo ""
    echo "${RED}CRITICAL:${NC} Attacker reached database server via 3-hop pivot"
    echo ""
    echo "Check logs in Elasticsearch: ${GREEN}security-*${NC}"
    echo ""
    echo "${CYAN}APT Techniques Covered:${NC}"
    echo "  ✓ SolarWinds (APT29) - Multi-stage lateral movement"
    echo "  ✓ NotPetya - Worm-like lateral spread"
    echo "  ✓ Colonial Pipeline - Ransomware lateral propagation"
    echo "  ✓ DNC Hack (APT28) - Network traversal"
    echo ""
}

main
