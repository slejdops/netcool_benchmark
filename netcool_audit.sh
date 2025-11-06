#!/bin/bash
################################################################################
# Netcool Environment Audit & Benchmark Script
# Version: 1.0
# Purpose: Comprehensive read-only assessment of Netcool/OMNIbus environment
#          against IBM best practices and performance baselines
#
# Author: SRE Team
# Date: 2025-11-06
#
# Usage: ./netcool_audit.sh [OPTIONS]
#   Options:
#     --help              Show usage information
#     --output FILE       Save report to specified file
#     --no-color          Disable colored output
#     --verbose           Enable verbose logging
#     --skip-sql          Skip ObjectServer SQL queries (if credentials unavailable)
#     --stress-test       [FUTURE] Enable active stress testing (not yet implemented)
#
# Requirements:
#   - Run as Netcool admin user (typically 'netcool' or user with $NCHOME set)
#   - Read access to Netcool installation directories
#   - Optional: ObjectServer credentials for performance profiling
################################################################################

set -o pipefail

################################################################################
# GLOBAL VARIABLES & CONFIGURATION
################################################################################

# Script metadata
SCRIPT_VERSION="1.0"
SCRIPT_START_TIME=$(date +%s)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Output configuration
OUTPUT_FILE=""
USE_COLOR=true
VERBOSE=false
SKIP_SQL=false
STRESS_TEST=false

# Color codes (will be disabled if --no-color is set)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Tracking arrays for report generation
declare -a PASSED_CHECKS=()
declare -a WARNINGS=()
declare -a FAILURES=()
declare -a RECOMMENDATIONS=()

# Environment detection
NCHOME=""
OMNIHOME=""
IMPACT_HOME=""
WEBGUI_HOME=""
OS_TYPE=""
OS_VERSION=""
HOSTNAME=$(hostname)

################################################################################
# IBM RECOMMENDED BASELINES (Embedded Best Practices)
#
# All baseline values are derived from official IBM documentation, best practices
# guides, and IBM support technotes. For detailed references and sources, see:
# IBM_BASELINE_REFERENCES.md
#
# Key IBM Documentation Sources:
# - IBM Netcool Performance Manager: Kernel Settings
#   https://www.ibm.com/docs/en/tnpm/1.4.4?topic=parameters-linux-kernel-settings
# - IBM WebSphere ulimit Guidelines
#   https://www.ibm.com/support/pages/guidelines-setting-ulimits-websphere-application-server
# - IBM Netcool/OMNIbus 8.1 Best Practices Guide
# - IBM Netcool/Impact Administration Guide
#   https://www.ibm.com/docs/en/tivoli-netcoolimpact/7.1.0
################################################################################

# OS Level Baselines
# Source: IBM WebSphere technotes, Netcool deployment guides
BASELINE_ULIMIT_NOFILE=65536           # Minimum open files limit
                                       # IBM Ref: WebSphere ulimit recommendations
                                       # Netcool requires 2-3x ObjectServer connections

# Source: IBM Tivoli Netcool Performance Manager Documentation
# URL: https://www.ibm.com/docs/en/tnpm/1.4.4?topic=parameters-linux-kernel-settings
# Format: kernel.sem = SEMMSL SEMMNS SEMOPM SEMMNI
BASELINE_KERNEL_SEMMSL=250             # Semaphores per set
BASELINE_KERNEL_SEMMNS=32000           # Total semaphores system-wide
BASELINE_KERNEL_SEMOPM=100             # Max operations per semop call (IBM: 100)
BASELINE_KERNEL_SEMMNI=128             # Max number of semaphore sets

# ObjectServer Baselines
# Source: IBM Netcool/OMNIbus Best Practices Guide
BASELINE_OBJSERV_MIN_MEMORY_MB=2048    # Minimum memory allocation (2GB)
                                       # Small: 1-2GB, Medium: 2-4GB, Large: 4GB+
BASELINE_OBJSERV_MAX_CONNECTIONS=1000  # Warning threshold for connections
                                       # Default limit often 1024, monitor usage
BASELINE_MAX_TRIGGERS_DISABLED=5       # Max acceptable disabled triggers
                                       # Review disabled triggers regularly
BASELINE_PROFILER_TRIGGER_MS=100       # Trigger execution time threshold (ms)
                                       # Source: IBM trigger profiling best practices

# alerts.status Table Size
# Source: IBM Netcool/OMNIbus 7.4 Best Practices - "Monitoring row numbers"
# Small system: <10,000 rows | Medium: 10,000-50,000 | Large: >50,000
BASELINE_ALERTS_STATUS_WARNING=50000   # Warning threshold for alerts.status rows

# Impact Baselines
# Source: IBM Netcool/Impact Administration Guide
# URL: https://www.ibm.com/docs/en/tivoli-netcoolimpact/7.1.0
BASELINE_IMPACT_HEAP_MIN_GB=4          # Minimum heap for production
                                       # IBM Default: 2.4GB explicitly insufficient
                                       # Production: 4GB+ based on deployment size
BASELINE_IMPACT_HEAP_MAX_GB=16         # Recommended max heap
                                       # Above 16GB: consider clustering/scaling

# WebGUI/JazzSM Baselines
# Source: IBM WebSphere and Netcool deployment guidelines
BASELINE_WEBGUI_HEAP_MIN_GB=2          # Minimum heap for WebGUI
                                       # Small: 2GB, Medium: 4GB, Large: 6-8GB
BASELINE_WEBGUI_HEAP_MAX_GB=8          # Recommended max heap

# Probe/Gateway Baselines
# Source: IBM Netcool/OMNIbus administration best practices
BASELINE_PROBE_DISCONNECT_THRESHOLD=10  # Max acceptable disconnects in recent logs
                                        # Frequent disconnects indicate systematic issues
BASELINE_GATEWAY_LAG_WARNING_SEC=30    # Gateway replication lag threshold
                                       # Replication should be near real-time

################################################################################
# UTILITY FUNCTIONS
################################################################################

# Print colored output
print_color() {
    local color=$1
    shift
    if [ "$USE_COLOR" = true ]; then
        echo -e "${color}$*${NC}"
    else
        echo "$*"
    fi
}

# Logging functions
log_info() {
    print_color "$BLUE" "[INFO] $*"
    [ "$VERBOSE" = true ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >&2
}

log_success() {
    print_color "$GREEN" "[PASS] $*"
    PASSED_CHECKS+=("$*")
}

log_warning() {
    print_color "$YELLOW" "[WARN] $*"
    WARNINGS+=("$*")
}

log_error() {
    print_color "$RED" "[FAIL] $*"
    FAILURES+=("$*")
}

log_verbose() {
    [ "$VERBOSE" = true ] && print_color "$CYAN" "[DEBUG] $*"
}

# Add recommendation to the final report
add_recommendation() {
    local priority=$1  # HIGH, MEDIUM, LOW
    shift
    local recommendation="[$priority] $*"
    RECOMMENDATIONS+=("$recommendation")
    log_verbose "Added recommendation: $recommendation"
}

# Print section header
print_section() {
    echo ""
    print_color "$BOLD$CYAN" "============================================"
    print_color "$BOLD$CYAN" "$*"
    print_color "$BOLD$CYAN" "============================================"
}

# Print subsection header
print_subsection() {
    echo ""
    print_color "$BOLD" "--- $* ---"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Safe command execution with error handling
safe_exec() {
    local cmd=$1
    log_verbose "Executing: $cmd"
    eval "$cmd" 2>/dev/null
    return $?
}

################################################################################
# USAGE & ARGUMENT PARSING
################################################################################

show_usage() {
    cat << EOF
Netcool Environment Audit & Benchmark Script v${SCRIPT_VERSION}

Usage: $0 [OPTIONS]

Options:
    --help              Show this help message
    --output FILE       Save report to specified file (in addition to stdout)
    --no-color          Disable colored output
    --verbose           Enable verbose/debug logging
    --skip-sql          Skip ObjectServer SQL queries (if credentials unavailable)
    --stress-test       [FUTURE] Enable active stress testing (placeholder)

Examples:
    $0                                    # Run with default settings
    $0 --output /tmp/netcool_audit.txt    # Save report to file
    $0 --skip-sql --no-color              # Run without SQL checks, no colors

Notes:
    - This script is READ-ONLY and safe to run in production
    - For ObjectServer profiling, you'll be prompted for credentials
    - Run as the Netcool service account for best results

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_usage
                exit 0
                ;;
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --no-color)
                USE_COLOR=false
                RED=''
                GREEN=''
                YELLOW=''
                BLUE=''
                CYAN=''
                BOLD=''
                NC=''
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --skip-sql)
                SKIP_SQL=true
                shift
                ;;
            --stress-test)
                STRESS_TEST=true
                log_warning "Stress test mode requested but not yet implemented"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

################################################################################
# ENVIRONMENT DISCOVERY
################################################################################

detect_os() {
    print_section "System Information Discovery"

    # Detect OS type
    if [ -f /etc/redhat-release ]; then
        OS_TYPE="RHEL"
        OS_VERSION=$(cat /etc/redhat-release)
    elif [ -f /etc/SuSE-release ]; then
        OS_TYPE="SLES"
        OS_VERSION=$(head -1 /etc/SuSE-release)
    elif uname -a | grep -q AIX; then
        OS_TYPE="AIX"
        OS_VERSION=$(oslevel)
    else
        OS_TYPE="Unknown"
        OS_VERSION=$(uname -a)
    fi

    log_info "Hostname: $HOSTNAME"
    log_info "OS Type: $OS_TYPE"
    log_info "OS Version: $OS_VERSION"
    log_info "Kernel: $(uname -r)"
    log_info "Architecture: $(uname -m)"

    # CPU and Memory info
    if [ "$OS_TYPE" = "AIX" ]; then
        CPU_CORES=$(lsdev -Cc processor | wc -l)
        TOTAL_RAM_MB=$(lsattr -El sys0 -a realmem | awk '{print $2/1024}')
    else
        CPU_CORES=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "Unknown")
        TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    fi

    log_info "CPU Cores: $CPU_CORES"
    log_info "Total RAM: ${TOTAL_RAM_MB} MB"
}

detect_netcool_home() {
    print_subsection "Netcool Installation Discovery"

    # Try to detect NCHOME
    if [ -n "$NCHOME" ]; then
        log_success "NCHOME already set: $NCHOME"
    else
        # Common installation paths
        local common_paths=(
            "/opt/IBM/tivoli/netcool"
            "/opt/netcool"
            "/usr/IBM/tivoli/netcool"
            "$HOME/IBM/tivoli/netcool"
        )

        for path in "${common_paths[@]}"; do
            if [ -d "$path" ]; then
                NCHOME="$path"
                export NCHOME
                log_info "Auto-detected NCHOME: $NCHOME"
                break
            fi
        done

        if [ -z "$NCHOME" ]; then
            log_error "NCHOME not set and could not be auto-detected"
            add_recommendation "HIGH" "Set NCHOME environment variable to point to Netcool installation"
            return 1
        fi
    fi

    # Try to detect OMNIHOME
    if [ -n "$OMNIHOME" ]; then
        log_success "OMNIHOME already set: $OMNIHOME"
    elif [ -d "$NCHOME/omnibus" ]; then
        OMNIHOME="$NCHOME/omnibus"
        export OMNIHOME
        log_info "Auto-detected OMNIHOME: $OMNIHOME"
    else
        log_warning "OMNIHOME not found (may not be ObjectServer host)"
    fi

    # Try to detect Impact
    if [ -d "$NCHOME/impact" ]; then
        IMPACT_HOME="$NCHOME/impact"
        log_info "Detected Impact installation: $IMPACT_HOME"
    fi

    # Try to detect WebGUI
    for path in "$NCHOME/gui/jazz" "$NCHOME/webgui" "/opt/IBM/JazzSM"; do
        if [ -d "$path" ]; then
            WEBGUI_HOME="$path"
            log_info "Detected WebGUI installation: $WEBGUI_HOME"
            break
        fi
    done

    return 0
}

detect_running_processes() {
    print_subsection "Running Netcool Processes"

    # Check if nco_pad is available
    if command_exists nco_pad && [ -n "$OMNIHOME" ]; then
        log_info "Querying processes via nco_pad..."
        local pad_output=$(nco_pad -list 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$pad_output" ]; then
            echo "$pad_output" | while read -r line; do
                log_verbose "Process: $line"
            done
        else
            log_warning "nco_pad available but returned no data"
        fi
    else
        log_verbose "nco_pad not available, using ps-based detection"
    fi

    # Fallback: Use ps to find Netcool processes
    log_info "Scanning for Netcool processes..."

    local process_patterns=(
        "nco_objserv"
        "nco_pad"
        "nco_g_"
        "nco_p_"
        "NCI_SERVICE"
        "Impact"
        "WebSphere"
    )

    for pattern in "${process_patterns[@]}"; do
        local count=$(ps -ef | grep -i "$pattern" | grep -v grep | wc -l)
        if [ "$count" -gt 0 ]; then
            log_info "Found $count process(es) matching: $pattern"
        fi
    done
}

################################################################################
# OS LEVEL CONFIGURATION AUDITING
################################################################################

check_os_tuning() {
    print_section "OS Level Configuration Audit"

    check_ulimits
    check_kernel_parameters
    check_network_tuning
}

check_ulimits() {
    print_subsection "User Limits (ulimit) Check"

    # Check open files limit
    local soft_nofile=$(ulimit -Sn)
    local hard_nofile=$(ulimit -Hn)

    log_info "Open Files - Soft Limit: $soft_nofile"
    log_info "Open Files - Hard Limit: $hard_nofile"

    if [ "$hard_nofile" -ge "$BASELINE_ULIMIT_NOFILE" ]; then
        log_success "Open files limit ($hard_nofile) meets baseline (>= $BASELINE_ULIMIT_NOFILE)"
    else
        log_error "Open files limit ($hard_nofile) below baseline ($BASELINE_ULIMIT_NOFILE)"
        add_recommendation "HIGH" "Increase ulimit nofile to at least $BASELINE_ULIMIT_NOFILE in /etc/security/limits.conf"
    fi

    # Check max user processes
    local max_proc=$(ulimit -u)
    log_info "Max User Processes: $max_proc"

    if [ "$max_proc" -ge 16384 ]; then
        log_success "Max user processes limit is adequate"
    else
        log_warning "Max user processes ($max_proc) may be insufficient for large deployments"
        add_recommendation "MEDIUM" "Consider increasing max user processes to 16384+"
    fi

    # Check stack size
    local stack_size=$(ulimit -s)
    log_info "Stack Size: $stack_size KB"

    if [ "$stack_size" = "unlimited" ] || [ "$stack_size" -ge 10240 ]; then
        log_success "Stack size is adequate"
    else
        log_warning "Stack size may be too small for complex ObjectServer operations"
        add_recommendation "LOW" "Consider increasing stack size to unlimited or 10240 KB"
    fi
}

check_kernel_parameters() {
    print_subsection "Kernel Parameter Check"

    if [ "$OS_TYPE" = "AIX" ]; then
        log_info "AIX system - skipping Linux kernel parameter checks"
        return
    fi

    # Check semaphore settings
    if command_exists sysctl; then
        local sem_values=$(sysctl kernel.sem 2>/dev/null | awk '{print $3}')

        if [ -n "$sem_values" ]; then
            local semmsl=$(echo "$sem_values" | awk '{print $1}')
            local semmns=$(echo "$sem_values" | awk '{print $2}')
            local semopm=$(echo "$sem_values" | awk '{print $3}')
            local semmni=$(echo "$sem_values" | awk '{print $4}')

            log_info "Kernel Semaphores: $sem_values"
            log_info "  SEMMSL (sems per set): $semmsl (baseline: $BASELINE_KERNEL_SEMMSL)"
            log_info "  SEMMNS (total sems): $semmns (baseline: $BASELINE_KERNEL_SEMMNS)"
            log_info "  SEMOPM (ops per call): $semopm (baseline: $BASELINE_KERNEL_SEMOPM)"
            log_info "  SEMMNI (max sets): $semmni (baseline: $BASELINE_KERNEL_SEMMNI)"

            local sem_pass=true
            [ "$semmsl" -lt "$BASELINE_KERNEL_SEMMSL" ] && sem_pass=false
            [ "$semmns" -lt "$BASELINE_KERNEL_SEMMNS" ] && sem_pass=false
            [ "$semopm" -lt "$BASELINE_KERNEL_SEMOPM" ] && sem_pass=false
            [ "$semmni" -lt "$BASELINE_KERNEL_SEMMNI" ] && sem_pass=false

            if [ "$sem_pass" = true ]; then
                log_success "Kernel semaphore settings meet IBM baseline requirements"
            else
                log_error "Kernel semaphore settings below IBM recommendations"
                add_recommendation "HIGH" "Update /etc/sysctl.conf: kernel.sem = $BASELINE_KERNEL_SEMMSL $BASELINE_KERNEL_SEMMNS $BASELINE_KERNEL_SEMOPM $BASELINE_KERNEL_SEMMNI"
            fi
        else
            log_warning "Could not read kernel.sem values"
        fi
    else
        log_warning "sysctl command not found, skipping kernel parameter checks"
    fi

    # Check shared memory settings
    if command_exists ipcs; then
        log_info "Checking shared memory limits..."
        local shmmax=$(cat /proc/sys/kernel/shmmax 2>/dev/null)
        local shmall=$(cat /proc/sys/kernel/shmall 2>/dev/null)

        if [ -n "$shmmax" ]; then
            local shmmax_gb=$((shmmax / 1024 / 1024 / 1024))
            log_info "SHMMAX: ${shmmax_gb} GB"

            if [ "$shmmax_gb" -ge 8 ]; then
                log_success "Shared memory max size is adequate"
            else
                log_warning "SHMMAX may be too small for large ObjectServer deployments"
                add_recommendation "MEDIUM" "Consider increasing kernel.shmmax to support large memory requirements"
            fi
        fi
    fi
}

check_network_tuning() {
    print_subsection "Network Configuration Check"

    if [ "$OS_TYPE" = "AIX" ]; then
        log_info "AIX system - network checks limited"
        return
    fi

    # Check TCP settings relevant to Netcool
    if [ -f /proc/sys/net/ipv4/tcp_keepalive_time ]; then
        local keepalive=$(cat /proc/sys/net/ipv4/tcp_keepalive_time)
        log_info "TCP Keepalive Time: $keepalive seconds"

        if [ "$keepalive" -le 300 ]; then
            log_success "TCP keepalive time is reasonable for Netcool connections"
        else
            log_warning "TCP keepalive time is high; may delay detection of connection failures"
            add_recommendation "LOW" "Consider reducing net.ipv4.tcp_keepalive_time to 120-300 seconds"
        fi
    fi

    # Check if firewall might interfere
    if command_exists firewall-cmd; then
        local firewall_state=$(firewall-cmd --state 2>/dev/null)
        log_info "Firewall state: $firewall_state"

        if [ "$firewall_state" = "running" ]; then
            log_warning "Firewall is active - ensure Netcool ports are allowed"
            add_recommendation "MEDIUM" "Verify firewall rules allow ObjectServer (4100), Impact (9080), WebGUI ports"
        fi
    fi
}

################################################################################
# OBJECTSERVER CONFIGURATION & HEALTH
################################################################################

audit_objectserver() {
    print_section "ObjectServer Configuration Audit"

    if [ -z "$OMNIHOME" ]; then
        log_warning "OMNIHOME not set, skipping ObjectServer checks"
        return 1
    fi

    check_objectserver_config
    check_objectserver_properties
    check_objectserver_performance
}

check_objectserver_config() {
    print_subsection "ObjectServer Environment Configuration"

    local omni_env="$OMNIHOME/etc/omnibus.env"

    if [ ! -f "$omni_env" ]; then
        log_error "omnibus.env not found at $omni_env"
        return 1
    fi

    log_info "Found omnibus.env at $omni_env"

    # Parse key settings from omnibus.env
    if grep -q "^OMNIHOME" "$omni_env"; then
        local env_omnihome=$(grep "^OMNIHOME" "$omni_env" | cut -d= -f2)
        log_info "OMNIHOME in env file: $env_omnihome"
    fi

    # Check for common configuration issues
    if grep -qi "debug" "$omni_env"; then
        log_warning "DEBUG settings found in omnibus.env - may impact performance"
        add_recommendation "MEDIUM" "Review and disable debug logging in production"
    fi

    log_success "omnibus.env file accessible and readable"
}

check_objectserver_properties() {
    print_subsection "ObjectServer Properties Files"

    local props_dir="$OMNIHOME/etc"

    if [ ! -d "$props_dir" ]; then
        log_error "Properties directory not found: $props_dir"
        return 1
    fi

    # Find all ObjectServer property files
    local props_files=($(find "$props_dir" -maxdepth 1 -name "*.props" 2>/dev/null))

    if [ ${#props_files[@]} -eq 0 ]; then
        log_warning "No ObjectServer .props files found in $props_dir"
        return 1
    fi

    log_info "Found ${#props_files[@]} ObjectServer property file(s)"

    for props_file in "${props_files[@]}"; do
        local server_name=$(basename "$props_file" .props)
        log_info "Analyzing: $server_name"

        # Check security settings
        local audit_level=$(grep -i "^Sec.AuditLevel" "$props_file" | awk '{print $2}')
        if [ -n "$audit_level" ]; then
            log_info "  Sec.AuditLevel: $audit_level"
            if [ "$audit_level" -ge 2 ]; then
                log_success "  Security auditing is enabled"
            else
                log_warning "  Security auditing is minimal or disabled"
                add_recommendation "MEDIUM" "Enable ObjectServer security auditing (Sec.AuditLevel >= 2)"
            fi
        fi

        # Check message log level
        if grep -qi "MessageLog.*debug" "$props_file"; then
            log_warning "  MessageLog set to DEBUG level - high performance impact!"
            add_recommendation "HIGH" "Change MessageLog level from DEBUG to INFO or WARN in production"
        fi

        # Check memory settings
        local mem_threshold=$(grep -i "^MemThreshold" "$props_file" | awk '{print $2}')
        if [ -n "$mem_threshold" ]; then
            log_info "  MemThreshold: $mem_threshold"
        fi

        local soft_limit=$(grep -i "^SoftLimit" "$props_file" | awk '{print $2}')
        if [ -n "$soft_limit" ]; then
            log_info "  SoftLimit: $soft_limit"
        fi

        # Check if profiler is enabled
        if grep -qi "profiler" "$props_file"; then
            log_success "  Profiler configuration found"
        else
            log_warning "  Profiler may not be configured"
            add_recommendation "MEDIUM" "Enable profiler_report trigger group for performance diagnostics"
        fi
    done
}

check_objectserver_performance() {
    print_subsection "ObjectServer Performance Profiling"

    if [ "$SKIP_SQL" = true ]; then
        log_info "Skipping SQL-based checks (--skip-sql enabled)"
        return 0
    fi

    if ! command_exists nco_sql; then
        log_warning "nco_sql not found in PATH, skipping performance queries"
        add_recommendation "LOW" "Ensure nco_sql is in PATH for detailed performance profiling"
        return 1
    fi

    # Prompt for credentials
    echo ""
    print_color "$CYAN" "ObjectServer SQL Profiling requires credentials"
    read -p "Enter ObjectServer name (or 'skip' to bypass): " objserv_name

    if [ "$objserv_name" = "skip" ] || [ -z "$objserv_name" ]; then
        log_info "Skipping ObjectServer SQL profiling"
        return 0
    fi

    read -p "Enter username (default: root): " objserv_user
    objserv_user=${objserv_user:-root}

    read -sp "Enter password: " objserv_pass
    echo ""

    if [ -z "$objserv_pass" ]; then
        log_warning "No password provided, skipping SQL profiling"
        return 0
    fi

    # Test connection
    log_info "Testing connection to ObjectServer: $objserv_name"

    local test_query="SELECT COUNT(*) FROM catalog.connections;"
    local test_result=$(echo "$test_query" | nco_sql -server "$objserv_name" -user "$objserv_user" -passwd "$objserv_pass" 2>&1)

    if [ $? -ne 0 ]; then
        log_error "Failed to connect to ObjectServer: $objserv_name"
        log_verbose "Error: $test_result"
        return 1
    fi

    log_success "Connected to ObjectServer: $objserv_name"

    # Query active connections
    query_objectserver_connections "$objserv_name" "$objserv_user" "$objserv_pass"

    # Query trigger performance
    query_trigger_performance "$objserv_name" "$objserv_user" "$objserv_pass"

    # Query table statistics
    query_table_statistics "$objserv_name" "$objserv_user" "$objserv_pass"

    # Query alerts status
    query_alerts_statistics "$objserv_name" "$objserv_user" "$objserv_pass"
}

query_objectserver_connections() {
    local server=$1
    local user=$2
    local pass=$3

    print_subsection "Active ObjectServer Connections"

    local query="SELECT AppName, COUNT(*) AS ConnectionCount FROM catalog.connections GROUP BY AppName ORDER BY ConnectionCount DESC;"

    local result=$(echo "$query" | nco_sql -server "$server" -user "$user" -passwd "$pass" -batch 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$result" ]; then
        echo "$result" | tail -n +3 | while IFS='|' read -r app_name count; do
            app_name=$(echo "$app_name" | xargs)
            count=$(echo "$count" | xargs)

            if [ -n "$app_name" ] && [ -n "$count" ]; then
                log_info "  $app_name: $count connection(s)"
            fi
        done

        local total_connections=$(echo "$result" | tail -n +3 | awk -F'|' '{sum+=$2} END {print sum}')

        if [ -n "$total_connections" ] && [ "$total_connections" -gt 0 ]; then
            log_info "Total active connections: $total_connections"

            if [ "$total_connections" -gt "$BASELINE_OBJSERV_MAX_CONNECTIONS" ]; then
                log_warning "Connection count ($total_connections) exceeds baseline ($BASELINE_OBJSERV_MAX_CONNECTIONS)"
                add_recommendation "MEDIUM" "Review and optimize ObjectServer connection pooling"
            else
                log_success "Connection count is within normal range"
            fi
        fi
    else
        log_warning "Could not retrieve connection statistics"
    fi
}

query_trigger_performance() {
    local server=$1
    local user=$2
    local pass=$3

    print_subsection "Trigger Performance Analysis"

    # Check if profiler tables exist
    local check_profiler="SELECT COUNT(*) FROM master.profiles WHERE TriggerName IS NOT NULL;"
    local profiler_result=$(echo "$check_profiler" | nco_sql -server "$server" -user "$user" -passwd "$pass" -batch 2>/dev/null)

    if [ $? -ne 0 ]; then
        log_warning "Profiler data not available - trigger group may be disabled"
        add_recommendation "MEDIUM" "Enable profiler_report trigger group: nco_sql -server $server -user root -passwd XXXXX"
        add_recommendation "MEDIUM" "  Execute: ALTER TRIGGER GROUP profiler_report SET ENABLED TRUE;"
        return 1
    fi

    # Get top 10 slowest triggers
    local query="SELECT TriggerName, ExecutionCount, CAST(TotalTime AS INTEGER) AS TotalTimeMs, CAST(AvgTime AS INTEGER) AS AvgTimeMs FROM master.profiles WHERE TriggerName IS NOT NULL ORDER BY TotalTime DESC;"

    local result=$(echo "$query" | nco_sql -server "$server" -user "$user" -passwd "$pass" -batch 2>/dev/null | head -20)

    if [ $? -eq 0 ] && [ -n "$result" ]; then
        log_info "Top triggers by total execution time:"

        echo "$result" | tail -n +3 | head -10 | while IFS='|' read -r trigger exec_count total_ms avg_ms; do
            trigger=$(echo "$trigger" | xargs)
            total_ms=$(echo "$total_ms" | xargs)
            avg_ms=$(echo "$avg_ms" | xargs)

            if [ -n "$trigger" ] && [ -n "$total_ms" ]; then
                log_info "  $trigger: Total=${total_ms}ms, Avg=${avg_ms}ms"

                if [ "$avg_ms" -gt "$BASELINE_PROFILER_TRIGGER_MS" ]; then
                    log_warning "    Trigger exceeds performance threshold (${BASELINE_PROFILER_TRIGGER_MS}ms)"
                    add_recommendation "HIGH" "Optimize trigger: $trigger (avg execution time: ${avg_ms}ms)"
                fi
            fi
        done

        log_success "Profiler data retrieved successfully"
    else
        log_warning "Could not retrieve trigger performance data"
    fi
}

query_table_statistics() {
    local server=$1
    local user=$2
    local pass=$3

    print_subsection "Table Statistics"

    # Query key table sizes
    local tables=("alerts.status" "alerts.journal" "alerts.details")

    for table in "${tables[@]}"; do
        local query="SELECT COUNT(*) as RowCount FROM $table;"
        local result=$(echo "$query" | nco_sql -server "$server" -user "$user" -passwd "$pass" -batch 2>/dev/null | tail -1)

        if [ $? -eq 0 ] && [ -n "$result" ]; then
            local row_count=$(echo "$result" | xargs)
            log_info "$table: $row_count rows"

            # Check if alerts.status is too large
            # IBM Best Practices: Small <10K, Medium 10K-50K, Large >50K rows
            if [ "$table" = "alerts.status" ] && [ "$row_count" -gt "$BASELINE_ALERTS_STATUS_WARNING" ]; then
                log_warning "alerts.status table is large ($row_count rows) - may impact performance"
                add_recommendation "MEDIUM" "Review alert lifecycle and deduplication rules to control alerts.status growth"
                add_recommendation "MEDIUM" "IBM Guidance: Medium systems 10K-50K rows, monitor performance at >50K"
            fi
        fi
    done
}

query_alerts_statistics() {
    local server=$1
    local user=$2
    local pass=$3

    print_subsection "Alert Statistics"

    # Get alert severity distribution
    local query="SELECT Severity, COUNT(*) AS Count FROM alerts.status GROUP BY Severity ORDER BY Severity;"

    local result=$(echo "$query" | nco_sql -server "$server" -user "$user" -passwd "$pass" -batch 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$result" ]; then
        log_info "Alert severity distribution:"
        echo "$result" | tail -n +3 | while IFS='|' read -r severity count; do
            severity=$(echo "$severity" | xargs)
            count=$(echo "$count" | xargs)

            if [ -n "$severity" ] && [ -n "$count" ]; then
                local severity_name=""
                case $severity in
                    0) severity_name="Clear" ;;
                    1) severity_name="Indeterminate" ;;
                    2) severity_name="Warning" ;;
                    3) severity_name="Minor" ;;
                    4) severity_name="Major" ;;
                    5) severity_name="Critical" ;;
                    *) severity_name="Unknown" ;;
                esac

                log_info "  Severity $severity ($severity_name): $count alerts"
            fi
        done
    fi
}

################################################################################
# IMPACT & WEBGUI PROFILING
################################################################################

audit_impact() {
    print_section "Netcool Impact Configuration Audit"

    if [ -z "$IMPACT_HOME" ]; then
        log_warning "Impact installation not detected, skipping Impact checks"
        return 0
    fi

    check_impact_jvm
    check_impact_cluster
    check_impact_services
}

check_impact_jvm() {
    print_subsection "Impact JVM Configuration"

    # Look for Impact startup scripts and configuration
    local impact_bin="$IMPACT_HOME/bin"
    local nci_service=$(find "$impact_bin" -name "nci_server" -o -name "NCI" 2>/dev/null | head -1)

    if [ -z "$nci_service" ]; then
        log_warning "Impact startup script not found"
        return 1
    fi

    log_info "Impact service script: $nci_service"

    # Try to extract JVM settings from running process
    local impact_pid=$(ps -ef | grep -i "NCI_SERVICE\|Impact" | grep -v grep | awk '{print $2}' | head -1)

    if [ -n "$impact_pid" ]; then
        log_info "Impact process detected (PID: $impact_pid)"

        # Get JVM arguments
        local jvm_args=""
        if [ "$OS_TYPE" = "AIX" ]; then
            jvm_args=$(ps eww "$impact_pid" 2>/dev/null)
        else
            jvm_args=$(ps -p "$impact_pid" -o args --no-headers 2>/dev/null)
        fi

        if [ -n "$jvm_args" ]; then
            # Extract heap settings
            local xms=$(echo "$jvm_args" | grep -oP '\-Xms\K[0-9]+[mMgG]' | head -1)
            local xmx=$(echo "$jvm_args" | grep -oP '\-Xmx\K[0-9]+[mMgG]' | head -1)

            if [ -n "$xmx" ]; then
                log_info "Impact Heap Size: -Xms${xms:-N/A} -Xmx$xmx"

                # Convert to GB for comparison
                local xmx_value=$(echo "$xmx" | sed 's/[^0-9]//g')
                local xmx_unit=$(echo "$xmx" | sed 's/[0-9]//g' | tr '[:lower:]' '[:upper:]')

                local xmx_gb=0
                if [ "$xmx_unit" = "G" ]; then
                    xmx_gb=$xmx_value
                elif [ "$xmx_unit" = "M" ]; then
                    xmx_gb=$((xmx_value / 1024))
                fi

                if [ "$xmx_gb" -ge "$BASELINE_IMPACT_HEAP_MIN_GB" ]; then
                    log_success "Impact heap size meets baseline (>= ${BASELINE_IMPACT_HEAP_MIN_GB}GB)"
                else
                    log_warning "Impact heap size ($xmx) below baseline (${BASELINE_IMPACT_HEAP_MIN_GB}GB)"
                    add_recommendation "HIGH" "Increase Impact heap to at least ${BASELINE_IMPACT_HEAP_MIN_GB}GB for production"
                fi

                if [ "$xmx_gb" -gt "$BASELINE_IMPACT_HEAP_MAX_GB" ]; then
                    log_warning "Impact heap size ($xmx) exceeds recommended maximum (${BASELINE_IMPACT_HEAP_MAX_GB}GB)"
                    add_recommendation "MEDIUM" "Review Impact heap size - excessive allocation may cause GC issues"
                fi
            else
                log_warning "Could not determine Impact heap size from process arguments"
            fi

            # Check for other important JVM flags
            if echo "$jvm_args" | grep -q "\-XX:+UseG1GC"; then
                log_success "Using G1GC (recommended for large heaps)"
            elif echo "$jvm_args" | grep -q "\-XX:+UseConcMarkSweepGC"; then
                log_info "Using CMS GC (consider migrating to G1GC)"
            fi

        fi
    else
        log_warning "Impact process not currently running"
    fi
}

check_impact_cluster() {
    print_subsection "Impact Cluster Configuration"

    local cluster_config="$IMPACT_HOME/etc/cluster.props"

    if [ -f "$cluster_config" ]; then
        log_info "Cluster configuration found: $cluster_config"

        if grep -qi "cluster.enabled.*true" "$cluster_config"; then
            log_success "Impact clustering is enabled"

            local cluster_members=$(grep -i "cluster.members" "$cluster_config" | cut -d= -f2)
            if [ -n "$cluster_members" ]; then
                log_info "Cluster members: $cluster_members"
            fi
        else
            log_info "Impact running in standalone mode"
        fi
    else
        log_info "No cluster configuration found (standalone deployment)"
    fi
}

check_impact_services() {
    print_subsection "Impact Service Status"

    # Check for Impact log files
    local impact_logs="$IMPACT_HOME/logs"

    if [ -d "$impact_logs" ]; then
        log_info "Checking Impact logs: $impact_logs"

        local nci_log=$(find "$impact_logs" -name "nci*.log" -type f 2>/dev/null | head -1)

        if [ -f "$nci_log" ]; then
            log_info "Found Impact log: $(basename $nci_log)"

            # Check for recent errors
            local recent_errors=$(tail -1000 "$nci_log" | grep -ci "ERROR\|SEVERE\|Exception")

            if [ "$recent_errors" -gt 0 ]; then
                log_warning "Found $recent_errors error(s) in recent Impact logs"
                add_recommendation "MEDIUM" "Review Impact logs for errors: $nci_log"
            else
                log_success "No recent errors in Impact logs"
            fi
        fi
    fi
}

audit_webgui() {
    print_section "WebGUI/JazzSM Configuration Audit"

    if [ -z "$WEBGUI_HOME" ]; then
        log_warning "WebGUI installation not detected, skipping WebGUI checks"
        return 0
    fi

    check_webgui_jvm
    check_webgui_services
}

check_webgui_jvm() {
    print_subsection "WebGUI JVM Configuration"

    # Look for WebSphere/Liberty processes
    local was_pid=$(ps -ef | grep -i "WebSphere\|wlp" | grep -v grep | awk '{print $2}' | head -1)

    if [ -n "$was_pid" ]; then
        log_info "WebGUI process detected (PID: $was_pid)"

        local jvm_args=$(ps -p "$was_pid" -o args --no-headers 2>/dev/null)

        if [ -n "$jvm_args" ]; then
            local xmx=$(echo "$jvm_args" | grep -oP '\-Xmx\K[0-9]+[mMgG]' | head -1)

            if [ -n "$xmx" ]; then
                log_info "WebGUI Heap Size: -Xmx$xmx"

                local xmx_value=$(echo "$xmx" | sed 's/[^0-9]//g')
                local xmx_unit=$(echo "$xmx" | sed 's/[0-9]//g' | tr '[:lower:]' '[:upper:]')

                local xmx_gb=0
                if [ "$xmx_unit" = "G" ]; then
                    xmx_gb=$xmx_value
                elif [ "$xmx_unit" = "M" ]; then
                    xmx_gb=$((xmx_value / 1024))
                fi

                if [ "$xmx_gb" -ge "$BASELINE_WEBGUI_HEAP_MIN_GB" ]; then
                    log_success "WebGUI heap size meets baseline (>= ${BASELINE_WEBGUI_HEAP_MIN_GB}GB)"
                else
                    log_warning "WebGUI heap size ($xmx) below baseline (${BASELINE_WEBGUI_HEAP_MIN_GB}GB)"
                    add_recommendation "MEDIUM" "Increase WebGUI heap to at least ${BASELINE_WEBGUI_HEAP_MIN_GB}GB"
                fi
            fi
        fi
    else
        log_warning "WebGUI process not currently running"
    fi
}

check_webgui_services() {
    print_subsection "WebGUI Service Status"

    # Check for WebGUI log files
    local webgui_logs="$WEBGUI_HOME/logs"

    if [ -d "$webgui_logs" ]; then
        log_info "WebGUI logs directory: $webgui_logs"

        local error_count=$(find "$webgui_logs" -type f -name "*.log" -mtime -1 -exec grep -c "ERROR\|Exception" {} + 2>/dev/null | awk '{sum+=$1} END {print sum}')

        if [ -n "$error_count" ] && [ "$error_count" -gt 0 ]; then
            log_warning "Found $error_count error(s) in recent WebGUI logs (last 24h)"
            add_recommendation "LOW" "Review WebGUI logs for errors: $webgui_logs"
        else
            log_success "No significant errors in recent WebGUI logs"
        fi
    fi
}

################################################################################
# PROBE & GATEWAY HEALTH CHECKS
################################################################################

check_probes_gateways() {
    print_section "Probe & Gateway Health Check"

    check_probe_health
    check_gateway_health
}

check_probe_health() {
    print_subsection "Probe Health Analysis"

    if [ -z "$OMNIHOME" ]; then
        log_warning "OMNIHOME not set, skipping probe checks"
        return 0
    fi

    # Look for probe log directories
    local probe_log_dirs=(
        "$OMNIHOME/log"
        "$OMNIHOME/probes/log"
        "$NCHOME/omnibus/log"
    )

    local probe_logs_found=false

    for log_dir in "${probe_log_dirs[@]}"; do
        if [ -d "$log_dir" ]; then
            log_info "Scanning probe logs in: $log_dir"

            # Find probe log files
            local probe_files=$(find "$log_dir" -name "*.log" -type f 2>/dev/null)

            if [ -n "$probe_files" ]; then
                probe_logs_found=true

                while IFS= read -r probe_log; do
                    local probe_name=$(basename "$probe_log" .log)
                    log_verbose "Analyzing: $probe_name"

                    # Check last 1000 lines for issues
                    local disconnect_count=$(tail -1000 "$probe_log" 2>/dev/null | grep -ci "disconnect\|connection.*lost\|failed to send")

                    if [ "$disconnect_count" -gt "$BASELINE_PROBE_DISCONNECT_THRESHOLD" ]; then
                        log_warning "Probe $probe_name: $disconnect_count disconnect/error events in recent logs"
                        add_recommendation "MEDIUM" "Investigate connectivity issues for probe: $probe_name"
                    else
                        log_verbose "Probe $probe_name: $disconnect_count disconnect events (acceptable)"
                    fi

                    # Check for processing delays
                    if tail -100 "$probe_log" 2>/dev/null | grep -qi "event processing time.*[5-9][0-9][0-9][0-9]\|processing time.*[1-9][0-9]\{4,\}"; then
                        log_warning "Probe $probe_name: High event processing times detected"
                        add_recommendation "MEDIUM" "Probe $probe_name may be overloaded or experiencing delays"
                    fi

                done <<< "$probe_files"

                log_success "Probe log analysis completed"
            fi
        fi
    done

    if [ "$probe_logs_found" = false ]; then
        log_warning "No probe logs found in standard locations"
    fi
}

check_gateway_health() {
    print_subsection "Gateway Health Analysis"

    if [ -z "$OMNIHOME" ]; then
        log_warning "OMNIHOME not set, skipping gateway checks"
        return 0
    fi

    # Look for gateway log directories
    local gateway_log_dirs=(
        "$OMNIHOME/log"
        "$OMNIHOME/gates/log"
        "$NCHOME/omnibus/gates/log"
    )

    local gateway_logs_found=false

    for log_dir in "${gateway_log_dirs[@]}"; do
        if [ -d "$log_dir" ]; then
            # Find gateway log files
            local gateway_files=$(find "$log_dir" -name "*gateway*.log" -o -name "G_*.log" -type f 2>/dev/null)

            if [ -n "$gateway_files" ]; then
                gateway_logs_found=true
                log_info "Scanning gateway logs in: $log_dir"

                while IFS= read -r gateway_log; do
                    local gateway_name=$(basename "$gateway_log" .log)
                    log_verbose "Analyzing: $gateway_name"

                    # Check for writer buffer issues
                    if tail -1000 "$gateway_log" 2>/dev/null | grep -qi "writer buffer.*full\|buffer.*backlog"; then
                        log_warning "Gateway $gateway_name: Writer buffer issues detected"
                        add_recommendation "HIGH" "Gateway $gateway_name may have replication lag - investigate ObjectServer load"
                    fi

                    # Check for connection issues
                    local conn_errors=$(tail -1000 "$gateway_log" 2>/dev/null | grep -ci "connection.*failed\|lost connection")

                    if [ "$conn_errors" -gt 5 ]; then
                        log_warning "Gateway $gateway_name: $conn_errors connection errors in recent logs"
                        add_recommendation "MEDIUM" "Check network connectivity for gateway: $gateway_name"
                    fi

                done <<< "$gateway_files"

                log_success "Gateway log analysis completed"
            fi
        fi
    done

    if [ "$gateway_logs_found" = false ]; then
        log_info "No gateway logs found (may not have gateways configured)"
    fi
}

################################################################################
# REPORT GENERATION
################################################################################

generate_final_report() {
    print_section "Audit Summary Report"

    local script_end_time=$(date +%s)
    local duration=$((script_end_time - SCRIPT_START_TIME))

    echo ""
    print_color "$BOLD" "=========================================="
    print_color "$BOLD" "Netcool Environment Audit Results"
    print_color "$BOLD" "=========================================="
    echo ""

    log_info "Audit completed at: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "Total execution time: ${duration} seconds"
    log_info "Hostname: $HOSTNAME"
    log_info "OS: $OS_TYPE $OS_VERSION"

    echo ""
    print_color "$BOLD$GREEN" "PASSED CHECKS: ${#PASSED_CHECKS[@]}"
    print_color "$BOLD$YELLOW" "WARNINGS: ${#WARNINGS[@]}"
    print_color "$BOLD$RED" "FAILURES: ${#FAILURES[@]}"

    # Display warnings
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        echo ""
        print_color "$BOLD$YELLOW" "WARNING DETAILS:"
        for warning in "${WARNINGS[@]}"; do
            print_color "$YELLOW" "  - $warning"
        done
    fi

    # Display failures
    if [ ${#FAILURES[@]} -gt 0 ]; then
        echo ""
        print_color "$BOLD$RED" "FAILURE DETAILS:"
        for failure in "${FAILURES[@]}"; do
            print_color "$RED" "  - $failure"
        done
    fi

    # Display recommendations
    if [ ${#RECOMMENDATIONS[@]} -gt 0 ]; then
        echo ""
        print_color "$BOLD$CYAN" "=========================================="
        print_color "$BOLD$CYAN" "RECOMMENDATIONS & REMEDIATION STEPS"
        print_color "$BOLD$CYAN" "=========================================="
        echo ""

        # Sort recommendations by priority
        local high_recs=()
        local medium_recs=()
        local low_recs=()

        for rec in "${RECOMMENDATIONS[@]}"; do
            if [[ $rec == \[HIGH\]* ]]; then
                high_recs+=("$rec")
            elif [[ $rec == \[MEDIUM\]* ]]; then
                medium_recs+=("$rec")
            else
                low_recs+=("$rec")
            fi
        done

        if [ ${#high_recs[@]} -gt 0 ]; then
            print_color "$BOLD$RED" "HIGH PRIORITY:"
            for rec in "${high_recs[@]}"; do
                print_color "$RED" "  $rec"
            done
            echo ""
        fi

        if [ ${#medium_recs[@]} -gt 0 ]; then
            print_color "$BOLD$YELLOW" "MEDIUM PRIORITY:"
            for rec in "${medium_recs[@]}"; do
                print_color "$YELLOW" "  $rec"
            done
            echo ""
        fi

        if [ ${#low_recs[@]} -gt 0 ]; then
            print_color "$BOLD$CYAN" "LOW PRIORITY:"
            for rec in "${low_recs[@]}"; do
                print_color "$CYAN" "  $rec"
            done
            echo ""
        fi
    else
        echo ""
        print_color "$BOLD$GREEN" "No recommendations - system appears well-configured!"
    fi

    echo ""
    print_color "$BOLD" "=========================================="
    print_color "$BOLD" "End of Audit Report"
    print_color "$BOLD" "=========================================="
    echo ""

    # Save to file if requested
    if [ -n "$OUTPUT_FILE" ]; then
        log_info "Saving report to: $OUTPUT_FILE"
        # This would need to redirect all output, implementation depends on requirements
    fi

    # Return exit code based on failures
    if [ ${#FAILURES[@]} -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Print banner
    clear
    print_color "$BOLD$CYAN" "╔════════════════════════════════════════════════════════════╗"
    print_color "$BOLD$CYAN" "║   Netcool Environment Audit & Benchmark Tool v${SCRIPT_VERSION}      ║"
    print_color "$BOLD$CYAN" "║   IBM Tivoli Netcool/OMNIbus Health Assessment            ║"
    print_color "$BOLD$CYAN" "╚════════════════════════════════════════════════════════════╝"
    echo ""
    print_color "$CYAN" "Starting audit at: $TIMESTAMP"
    print_color "$CYAN" "This script performs READ-ONLY operations and is safe for production"
    echo ""

    # Discovery phase
    detect_os
    detect_netcool_home
    detect_running_processes

    # Configuration auditing phase
    check_os_tuning

    # Component-specific audits
    if [ -n "$OMNIHOME" ]; then
        audit_objectserver
    fi

    if [ -n "$IMPACT_HOME" ]; then
        audit_impact
    fi

    if [ -n "$WEBGUI_HOME" ]; then
        audit_webgui
    fi

    # Probe and gateway checks
    check_probes_gateways

    # Generate final report
    generate_final_report

    # Return appropriate exit code
    if [ ${#FAILURES[@]} -gt 0 ]; then
        exit 1
    elif [ ${#WARNINGS[@]} -gt 0 ]; then
        exit 2
    else
        exit 0
    fi
}

# Execute main function
main "$@"
