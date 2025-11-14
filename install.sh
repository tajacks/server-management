#!/usr/bin/env bash
# Server Installation Script
# Setup for new servers with optional units
#
# Usage:
#   sudo ./install.sh base               # Install base only
#
# Requires: Bash 4.0+, root privileges

#==============================================================================
# CONFIGURATION
#==============================================================================

# Modify these variables before running
ADMIN_USER=""
ADMIN_USER_COMMENT=""
ADMIN_SSH_KEY=""
APP_USER="app"
SSH_PORT="2222"

# All variables above are validated during preflight checks

#==============================================================================
# LOGGING
#==============================================================================

# Modern Bash strict mode
set -euo pipefail  # Exit on error, undefined vars, pipe failures.
IFS=$'\n\t'         # Sane word splitting

# Script metadata
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly LOG_FILE="/var/log/server-install-$(date '+%Y%m%d-%H%M%S').log"
readonly REQUIRED_BASH_VERSION=4

# Ensure TERM is set for color support
# Support common color-capable terminals or set a sensible default
if [[ -z "${TERM:-}" ]] || [[ "$TERM" == "dumb" ]] || [[ "$TERM" == "xterm-ghostty" ]]; then
    export TERM=xterm-256color
fi

# Color codes for log output when running this script in a terminal (-t)
if [[ -t 1 ]]; then
    readonly COLOR_RESET="$(tput sgr0 2>/dev/null || echo '')"
    readonly COLOR_RED="$(tput setaf 1 2>/dev/null || echo '')"
    readonly COLOR_GREEN="$(tput setaf 2 2>/dev/null || echo '')"
    readonly COLOR_YELLOW="$(tput setaf 3 2>/dev/null || echo '')"
    readonly COLOR_CYAN="$(tput setaf 6 2>/dev/null || echo '')"
else
    readonly COLOR_RESET=""
    readonly COLOR_RED=""
    readonly COLOR_GREEN=""
    readonly COLOR_YELLOW=""
    readonly COLOR_CYAN=""
fi

# Logging functions with consistent formatting
log_info() {
    local -r timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    printf "%s %b[INFO]%b %s\n" "${timestamp}" "${COLOR_GREEN}" "${COLOR_RESET}" "$*" | tee -a "$LOG_FILE"
}

log_warn() {
    local -r timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    printf "%s %b[WARN]%b %s\n" "${timestamp}" "${COLOR_YELLOW}" "${COLOR_RESET}" "$*" | tee -a "$LOG_FILE"
}

log_error() {
    local -r timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    printf "%s %b[ERROR]%b %s\n" "${timestamp}" "${COLOR_RED}" "${COLOR_RESET}" "$*" | tee -a "$LOG_FILE" >&2
}

log_step() {
    local -r timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    printf "%s %b[STEP]%b %s\n" "${timestamp}" "${COLOR_CYAN}" "${COLOR_RESET}" "$*" | tee -a "$LOG_FILE"
}

# Idempotent file write - only writes if content has changed (MD5 comparison)
# Usage: idempotent_write_file <file_path> <content> [owner] [permissions]
# Returns: 0 if written/updated, 1 if skipped (unchanged), 2 on error
idempotent_write_file() {
    local -r file_path="$1"
    local -r content="$2"
    local -r owner="${3:-root:root}"
    local -r perms="${4:-644}"

    if [[ -z "$file_path" ]] || [[ -z "$content" ]]; then
        log_error "idempotent_write_file: file_path and content are required"
        return 2
    fi

    # Calculate MD5 of new content
    local -r new_md5=$(echo -n "$content" | md5sum | cut -d' ' -f1)

    # If file exists, calculate MD5 of existing content
    if [[ -f "$file_path" ]]; then
        local -r existing_md5=$(md5sum "$file_path" | cut -d' ' -f1)

        if [[ "$new_md5" == "$existing_md5" ]]; then
            log_info "File unchanged (MD5 match): $file_path"
            return 1
        else
            log_info "File content changed, updating: $file_path"
        fi
    else
        log_info "Creating new file: $file_path"
    fi

    # Write the file
    echo -n "$content" > "$file_path" || {
        log_error "Failed to write file: $file_path"
        return 2
    }

    # Set ownership and permissions
    if ! chown "$owner" "$file_path"; then
        log_error "Failed to set ownership '$owner' on: $file_path"
        rm -f "$file_path"  # Clean up the file we just created
        return 2
    fi

    if ! chmod "$perms" "$file_path"; then
        log_error "Failed to set permissions '$perms' on: $file_path"
        rm -f "$file_path"  # Clean up the file we just created
        return 2
    fi

    return 0
}

# Get the primary IP address of the system
get_primary_ip() {
    local ip=""

    # Method 1: Try to get IP from default route interface
    if command -v ip &>/dev/null; then
        local default_iface
        default_iface=$(ip route | grep '^default' | head -1 | awk '{print $5}')
        if [[ -n "$default_iface" ]]; then
            ip=$(ip -4 addr show "$default_iface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        fi
    fi

    # Method 2: Fallback to hostname -I (gets all IPs, we take first)
    if [[ -z "$ip" ]] && command -v hostname &>/dev/null; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    # Method 3: Last resort - try to get any non-loopback IPv4
    if [[ -z "$ip" ]]; then
        ip=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | head -1)
    fi

    # Return the IP or "unknown" if we couldn't find it
    if [[ -n "$ip" ]]; then
        echo "$ip"
    else
        echo "unknown"
    fi
}

# Cleanup handler
cleanup() {
    local -r exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Installation failed with exit code: $exit_code"
        log_error "Check log file for details: $LOG_FILE"
    fi
}

# Handle script exit conditions
trap cleanup EXIT
trap 'log_error "Installation interrupted"; exit 130' INT TERM

# Check Bash version
check_bash_version() {
    if [[ "${BASH_VERSINFO[0]}" -lt "$REQUIRED_BASH_VERSION" ]]; then
        log_error "Bash ${REQUIRED_BASH_VERSION}.0+ required, but you have ${BASH_VERSION}"
        exit 1
    fi
}

# Check root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        log_error "Try: sudo $SCRIPT_NAME"
        exit 1
    fi
}

# Check configuration variables are set
check_config_vars() {
    local -a empty_vars=()

    [[ -z "${ADMIN_USER}" ]] && empty_vars+=("ADMIN_USER")
    [[ -z "${ADMIN_USER_COMMENT}" ]] && empty_vars+=("ADMIN_USER_COMMENT")
    [[ -z "${ADMIN_SSH_KEY}" ]] && empty_vars+=("ADMIN_SSH_KEY")
    [[ -z "${APP_USER}" ]] && empty_vars+=("APP_USER")
    [[ -z "${SSH_PORT}" ]] && empty_vars+=("SSH_PORT")

    if [[ ${#empty_vars[@]} -gt 0 ]]; then
        log_error "Configuration variables must not be empty:"
        for var in "${empty_vars[@]}"; do
            log_error "  - $var"
        done
        log_error "Please set all required variables in the CONFIGURATION section"
        exit 1
    fi
}

# Display help
show_help() {
    cat << 'EOF'
Server Installation Script

USAGE:
    sudo ./install.sh [OPTIONS] [UNITS...]

UNITS:
    base        System hardening, users, SSH, firewall

OPTIONS:
    --all       Install all available units
    --help, -h  Show this help message

EXAMPLES:
    # Initial server setup (recommended)
    sudo ./install.sh base              # Base hardening only
    sudo ./install.sh --all             # Everything
EOF
    exit 0
}

# Perform pre-flight checks
preflight_checks() {
    check_bash_version
    check_root
    check_config_vars

    # Check for required commands
    local -a required_commands=("apt" "systemctl" "tee")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done

    log_info "Pre-flight checks passed"
}

# Available units (readonly)
declare -ra AVAILABLE_UNITS=("base")
# Units requested by user (populated during argument parsing)
declare -a REQUESTED_UNITS=()

# Check if unit exists
unit_exists() {
    local -r unit=$1
    local u
    for u in "${AVAILABLE_UNITS[@]}"; do
        [[ "$u" == "$unit" ]] && return 0
    done
    return 1
}

# Check if unit has been requested
unit_requested() {
    local -r unit=$1
    local u
    for u in "${REQUESTED_UNITS[@]}"; do
        [[ "$u" == "$unit" ]] && return 0
    done
    return 1
}

# Parse command line arguments
parse_args() {
    # Handle special cases first
    if [[ $# -eq 0 ]]; then
        log_error "No units specified"
        log_info "Use --help for usage information"
        log_info "Example: sudo ./install.sh base"
        exit 1
    fi

    # Process arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                REQUESTED_UNITS=("${AVAILABLE_UNITS[@]}")
                return 0
                ;;
            --help|-h)
                show_help
                ;;
            -*)
                log_error "Unknown option: $1"
                log_info "Use --help for usage information"
                exit 1
                ;;
            *)
                # It's a unit name
                if unit_exists "$1"; then
                    if ! unit_requested "$1"; then
                        REQUESTED_UNITS+=("$1")
                    fi
                else
                    log_error "Unknown unit: $1"
                    log_info "Available units: $(printf '%s, ' "${AVAILABLE_UNITS[@]}" | head -c -2)"
                    exit 1
                fi
                ;;
        esac
        shift
    done
}

# Execute a unit
execute_unit() {
    local -r unit=$1
    local -r unit_script="$SCRIPT_DIR/units/$unit.sh"

    if [[ ! -f "$unit_script" ]]; then
        log_error "Unit script not found: $unit_script"
        return 1
    fi

    if [[ ! -r "$unit_script" ]]; then
        log_error "Unit script not readable: $unit_script"
        return 1
    fi

    log_step "Executing unit: $unit"
    printf "%s\n" "$(printf '%.0s-' {1..80})" | tee -a "$LOG_FILE"

    # Source the unit script (it will use our logging functions)
    # shellcheck source=/dev/null
    if source "$unit_script"; then
        log_info "✓ Unit '$unit' completed successfully"
        printf "\n" | tee -a "$LOG_FILE"
        return 0
    else
        log_error "✗ Unit '$unit' failed"
        return 1
    fi
}

# Display installation summary
show_summary() {
    log_info "========================================"
    log_info "Installation Complete!"
    log_info "========================================"
    log_info "Installed units: $(printf '%s, ' "${REQUESTED_UNITS[@]}" | head -c -2)"
    log_info "Log file: $LOG_FILE"
    log_info "Installation time: $(date)"
    log_info ""

    # Show SSH warning only if base was installed
    if unit_requested "base"; then
        # Get server IP address
        local -r server_ip=$(get_primary_ip)

        local base_script="$SCRIPT_DIR/units/base.sh"

        log_warn "IMPORTANT: Review the following before disconnecting:"
        log_info "  1. SSH is now on port $SSH_PORT"
        log_info "  2. Password authentication is disabled"
        log_info "  3. Root login is disabled"
        log_info "  4. Firewall is active"
        log_info ""
        log_warn "CRITICAL: Test SSH in a new terminal before closing this session!"
        log_info ""
        log_info "Server IP: $server_ip"
        log_info ""
        log_info "SSH Connection Command:"
        log_info "  ${COLOR_CYAN}ssh -p $SSH_PORT $ADMIN_USER@$server_ip${COLOR_RESET}"
    fi
    log_info ""
}

#==============================================================================
# MAIN EXECUTION
#==============================================================================

main() {
    # Parse command line arguments
    parse_args "$@"

    # Run pre-flight checks
    preflight_checks

    # Display installation plan
    log_info "========================================"
    log_info "Server Installation Starting"
    log_info "========================================"
    log_info "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "Hostname: $(hostname)"
    log_info "Units to install: $(printf '%s, ' "${REQUESTED_UNITS[@]}" | head -c -2)"
    log_info "Log file: $LOG_FILE"
    log_info ""

    # Execute each unit in order
    for unit in "${REQUESTED_UNITS[@]}"; do
        execute_unit "$unit" || exit 1
    done

    # Show completion summary
    show_summary
}

# Run main function with all arguments
main "$@"
