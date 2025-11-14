#!/usr/bin/env bash
# Base Unit: System hardening and security configuration
#
# Features:
#   - System updates and essential packages
#   - User creation (admin + app users)
#   - SSH hardening (custom port, key-only auth)
#   - Firewall configuration (UFW)
#   - fail2ban for SSH protection
#   - Automatic security updates
#

#==============================================================================
# HELPER FUNCTIONS
#==============================================================================

# Check if user exists
user_exists() {
    local -r username=$1
    id "$username" &>/dev/null
}

# Check if package is installed
package_installed() {
    local -r package=$1
    dpkg -l "$package" 2>/dev/null | grep -q "^ii"
}

# Install packages if not already installed (idempotent)
install_packages() {
    local -a packages_to_install=()

    for pkg in "$@"; do
        if ! package_installed "$pkg"; then
            packages_to_install+=("$pkg")
        fi
    done

    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        log_info "Installing packages: ${packages_to_install[*]}"
        DEBIAN_FRONTEND=noninteractive apt install -y -qq "${packages_to_install[@]}" || return 1
    else
        log_info "All required packages already installed"
    fi
}

# Create directory with specific permissions (idempotent)
ensure_directory() {
    local -r dir=$1
    local -r owner=${2:-root}
    local -r perms=${3:-755}

    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        chown "$owner" "$dir"
        chmod "$perms" "$dir"
        log_info "Created directory: $dir"
    fi
}

#==============================================================================
# SYSTEM UPDATES
#==============================================================================

update_system() {
    log_info "Updating package lists..."
    apt update -qq || return 1

    log_info "Upgrading system packages (this may take several minutes)..."
    DEBIAN_FRONTEND=noninteractive apt full-upgrade -y -qq || return 1

    log_info "Cleaning up package cache..."
    apt autoclean -y -qq
    apt autoremove -y -qq

    log_info "System update complete"
}

#==============================================================================
# ESSENTIAL PACKAGES
#==============================================================================

install_essential_packages() {
    log_info "Installing essential packages..."

    local -ra packages=(
        apt-transport-https
        ca-certificates
        curl
        gnupg
        lsb-release
        ufw
        fail2ban
        rsyslog
        unattended-upgrades
        vim
        git
        htop
        fish
        tree
        net-tools
    )

    install_packages "${packages[@]}"
}

#==============================================================================
# USER MANAGEMENT - ADMIN USER
#==============================================================================

create_admin_user() {
    if user_exists "$ADMIN_USER"; then
        log_info "Admin user '$ADMIN_USER' already exists"
    else
        log_info "Creating admin user: $ADMIN_USER"
        useradd -m -s /usr/bin/fish -c "$ADMIN_USER_COMMENT" "$ADMIN_USER"
        usermod -aG sudo "$ADMIN_USER"
    fi

    # Configure passwordless sudo
    local -r sudoers_file="/etc/sudoers.d/$ADMIN_USER"
    if [[ ! -f "$sudoers_file" ]]; then
        log_info "Configuring passwordless sudo for $ADMIN_USER"
        echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > "$sudoers_file"
        chmod 0440 "$sudoers_file"
    fi

    # Setup SSH key
    configure_admin_ssh

    # Configure Fish shell
    local -r fish_config="/home/$ADMIN_USER/.config/fish"
    ensure_directory "$fish_config" "$ADMIN_USER:$ADMIN_USER" 755

    local -r fish_config_content="set -gx TERM xterm-256color
"
    idempotent_write_file "$fish_config/config.fish" "$fish_config_content" "$ADMIN_USER:$ADMIN_USER" "644"

    log_info "Admin user '$ADMIN_USER' configured"
}

configure_admin_ssh() {
    local -r ssh_dir="/home/$ADMIN_USER/.ssh"
    local -r auth_keys="$ssh_dir/authorized_keys"

    ensure_directory "$ssh_dir" "$ADMIN_USER:$ADMIN_USER" 700

    # Check if key already exists
    if [[ -f "$auth_keys" ]] && grep -qF "$ADMIN_SSH_KEY" "$auth_keys"; then
        log_info "SSH key already configured for $ADMIN_USER"
    else
        log_info "Adding SSH key for $ADMIN_USER"
        echo "$ADMIN_SSH_KEY" > "$auth_keys"
        chmod 600 "$auth_keys"
        chown "$ADMIN_USER:$ADMIN_USER" "$auth_keys"
    fi
}

#==============================================================================
# USER MANAGEMENT - APP USER
#==============================================================================

create_app_user() {
    if user_exists "$APP_USER"; then
        log_info "App user '$APP_USER' already exists"
    else
        log_info "Creating app user: $APP_USER"
        useradd -m -s /usr/bin/fish -c "Application User" "$APP_USER"
    fi

    log_info "App user '$APP_USER' configured"
}

#==============================================================================
# SSH HARDENING
#==============================================================================

harden_ssh() {
    local -r sshd_config="/etc/ssh/sshd_config"
    local -r sshd_backup="/etc/ssh/sshd_config.backup"

    # Backup original config (only once)
    if [[ -f "$sshd_config" ]] && [[ ! -f "$sshd_backup" ]]; then
        log_info "Backing up original SSH configuration"
        cp "$sshd_config" "$sshd_backup"
    fi

    # Check if already hardened
    if [[ -f "$sshd_config" ]] && grep -q "# Hardened SSH Configuration" "$sshd_config"; then
        log_info "SSH already hardened, checking port configuration..."
        # Update port if different
        if ! grep -q "^Port $SSH_PORT" "$sshd_config"; then
            log_info "Updating SSH port to $SSH_PORT"
        else
            log_info "SSH configuration up to date"
            return 0
        fi
    fi

    log_info "Deploying hardened SSH configuration (Port: $SSH_PORT)"

    local -r ssh_content="# Hardened SSH Configuration
# Generated by server installation script
# Backup available at: $sshd_backup

# Network
Port $SSH_PORT
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::

# Host Keys
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_rsa_key

# Ciphers and keying
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256

# Authentication
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Security settings
MaxAuthTries 3
MaxSessions 10
LoginGraceTime 60
ClientAliveInterval 300
ClientAliveCountMax 2
MaxStartups 10:30:60

# Access control
AllowUsers $ADMIN_USER $APP_USER

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Disable unnecessary features
X11Forwarding no
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
AcceptEnv LANG LC_*

# Subsystem
Subsystem sftp /usr/lib/openssh/sftp-server
"

    idempotent_write_file "$sshd_config" "$ssh_content" "root:root" "600"

    log_info "Enabling and restarting SSH service"
    systemctl enable ssh
    systemctl restart ssh

    log_info "SSH hardening complete"
}

#==============================================================================
# FAIL2BAN CONFIGURATION
#==============================================================================

configure_fail2ban() {
    local -r jail_local="/etc/fail2ban/jail.local"

    if [[ -f "$jail_local" ]] && grep -q "port = $SSH_PORT" "$jail_local"; then
        log_info "fail2ban already configured"
        return 0
    fi

    log_info "Configuring fail2ban for SSH protection"

    local -r fail2ban_content="[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban
action = %(action_)s

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
"

    idempotent_write_file "$jail_local" "$fail2ban_content" "root:root" "644"

    log_info "Enabling and starting fail2ban"
    systemctl enable fail2ban
    systemctl restart fail2ban

    log_info "fail2ban configuration complete"
}

#==============================================================================
# UFW FIREWALL
#==============================================================================

configure_firewall() {
    log_info "Configuring UFW firewall"

    # Set default policies first (safe even if firewall is active)
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH on custom port (add rule before enabling to prevent lockout)
    if ! ufw status | grep -q "$SSH_PORT/tcp"; then
        log_info "Allowing SSH on port $SSH_PORT"
        ufw allow "$SSH_PORT/tcp" comment 'SSH'
    fi

    # Allow HTTP and HTTPS
    if ! ufw status | grep -q "80/tcp"; then
        log_info "Allowing HTTP (port 80)"
        ufw allow 80/tcp comment 'HTTP'
    fi

    if ! ufw status | grep -q "443/tcp"; then
        log_info "Allowing HTTPS (port 443)"
        ufw allow 443/tcp comment 'HTTPS'
    fi

    # Enable firewall only after all rules are added
    if ! ufw status | grep -q "Status: active"; then
        log_info "Enabling UFW firewall with rules in place"
        yes | ufw --force enable > /dev/null
    else
        log_info "Firewall already active, rules updated"
        # Reload to apply any new rules
        ufw reload > /dev/null
    fi

    log_info "Firewall configuration complete"
}

#==============================================================================
# ROOT PASSWORD LOCKDOWN
#==============================================================================

# Lock root password (root remains accessible via sudo for admin user)
lock_root_password() {
    log_info "Locking root password"

    if passwd -l root > /dev/null 2>&1; then
        log_info "Root password locked (accessible via sudo only)"
    else
        log_warn "Failed to lock root password (may already be locked)"
    fi
}

#==============================================================================
# FILE PERMISSIONS
#==============================================================================

secure_file_permissions() {
    log_info "Setting secure file permissions"

    chmod 644 /etc/passwd
    chmod 640 /etc/shadow
    chmod 644 /etc/group
    chmod 640 /etc/gshadow
    chmod 600 /etc/ssh/sshd_config

    log_info "File permissions secured"
}

#==============================================================================
# AUTOMATIC UPDATES
#==============================================================================

configure_automatic_updates() {
    local -r unattended_config="/etc/apt/apt.conf.d/50unattended-upgrades"
    local -r auto_upgrades="/etc/apt/apt.conf.d/20auto-upgrades"

    if [[ -f "$auto_upgrades" ]] && grep -q "APT::Periodic::Unattended-Upgrade \"1\"" "$auto_upgrades"; then
        log_info "Automatic updates already configured"
        return 0
    fi

    log_info "Configuring automatic security updates"

    local -r unattended_content='Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
'

    local -r auto_upgrades_content='APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
'

    idempotent_write_file "$unattended_config" "$unattended_content" "root:root" "644"
    idempotent_write_file "$auto_upgrades" "$auto_upgrades_content" "root:root" "644"

    log_info "Automatic updates enabled"
}

#==============================================================================
# IPV6 CHECK
#==============================================================================

check_ipv6() {
    if [[ -f /proc/net/if_inet6 ]]; then
        log_info "IPv6 is enabled and available"
    else
        log_warn "IPv6 is not available on this system"
    fi
}

#==============================================================================
# MAIN EXECUTION
#==============================================================================

main() {
    log_info "Starting base unit configuration..."

    update_system || return 1
    install_essential_packages || return 1
    create_admin_user || return 1
    create_app_user || return 1
    harden_ssh || return 1
    configure_fail2ban || return 1
    configure_firewall || return 1
    lock_root_password || return 1
    secure_file_permissions || return 1
    configure_automatic_updates || return 1
    check_ipv6 || return 1

    # Get server IP address (function provided by install.sh)
    local server_ip="unknown"
    if command -v get_primary_ip &>/dev/null; then
        server_ip=$(get_primary_ip)
    else
        # Fallback if function not available
        server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
        [[ -z "$server_ip" ]] && server_ip="unknown"
    fi

    # Summary
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Base Unit Configuration Summary"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "✓ System updated and hardened"
    log_info "✓ Server IP: $server_ip"
    log_info "✓ Admin user: $ADMIN_USER (full sudo)"
    log_info "✓ App user: $APP_USER"
    log_info "✓ SSH: Port $SSH_PORT (SSH key only, no root)"
    log_info "✓ Firewall: Ports $SSH_PORT, 80, 443"
    log_info "✓ fail2ban: SSH protection active"
    log_info "✓ Updates: Automatic security updates enabled"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    return 0
}

# Execute main function
main

