# Server Management

This document outlines the steps I take to setup a new server. It results in a reasonable base configuration that I can
build off of as needed. Subsequent sections go past basic setup and set up the technologies I use to my run my
applications.

To skip to the setup guide, [click here](#setup).

To learn more about how I run my applications, [click here](#technologies).

## Methods & Motivations

Personal computing can be a very rewarding hobby. More generally, keeping and maintaining a personal server can be a
cost effective way to develop _things_ and have them exposed to the real world. There's no shortage of ways a server can
be useful to an individual, including but not limited to:

- Hosting a personal website
- Hosting generic files for distribution
- Running a VPN node
- Running scheduled jobs that _do something_ every so often
- Hosting file & photo storage
- Hosting a game server
- Hosting a chatbot
- Just having fun configuring infrastructure
- If your server is powerful enough, all of the above

In short, maintaining a personal server can be both a fun hobby project and a powerful tool.

The steps in this document are intended to be manually executed. I've experimented with a variety of automation tools to
provision new servers (ansible, bash, cloud-init, etc), and while they certainly are _neat_, they don't bring me
enough value. Setting up a new server manually takes ~30 minutes if you're decent on the command line (a skill which
setting up the server helps improve...) and I have found little to match the familiarity you build with your
infrastructure when you configure it manually.

I think of it like a construction project. If you were to do a small to medium sized home renovation, it's likely worth learning the skills to do much of the work yourself. You save money, learn new things, and know exactly what's going on behind those walls. If you outsource the work, you declare the end state you wish to receive and the builder (automation tool in this analogy) makes it so. While this works great for large projects, for small personal projects the overhead of managing the builder, communicating requirements, and trusting work you didn't see happen can outweigh the time saved. Similarly, declarative automation tools require investment in learning their syntax and maintaining their configurations—time that may exceed the 30 minutes of manual work they replace, especially when you only provision a server every few years.

This philosophy works where ultimately the stakes and volume of work is low. If I had to run a business to support my livelihood, or provision tens to hundreds of servers, an alternative would be necessary.

For personal-use servers, it's great.

### Technologies

I "bucket" the "types of work" the server will perform and then assign technologies to each bucket. Each choice reflects a preference for simplicity, reliability, and minimal maintenance.

| Category                  | Technology     | Notes                                                                           |
|---------------------------|----------------|---------------------------------------------------------------------------------|
| **Operating System**      | Debian         | Stable, well-documented, boring in the best way                                 |
| **Application Runtime**   | Podman         | Containerization solves dependency conflicts and makes cleanup trivial          |
| **Reverse Proxy & HTTPS** | Caddy          | Automatic HTTPS with Let's Encrypt, remarkably simple configuration             |
| **Scheduled Tasks**       | SystemD Timers | Built into Debian, better logging than cron, runs Podman containers on schedule |
| **Database**              | PostgreSQL     | Capable, reliable                                                               |

A typical deployment includes application containers and a database, Caddy proxying HTTPS traffic to the containers, and SystemD timers for scheduled jobs. Everything runs isolated with logs accessible via `podman logs` and `journalctl`.

## Setup

### Logging In

After ordering your server, your provider is going to likely display or email you connection details. They will probably
look something like this:


> You may connect to your server through SSH with the following details:
>   - IP address: 1.2.3.4
>   - user: debian
>   - authentication method: SSH key


The user is determined by the cloud provider. Some may create a user during provisioning, such as `debian`. Others may
use `root`. The authentication method typically depends on if an SSH key was provided during provisioning. If not, a
password may be used.

Connect to your system via SSH using the specified IP address, user, and authentication method:

```
ssh root@1.2.3.4
```

If _not_ connecting as `root`, you should have some kind of `sudo` access. Try and become `root` for the remainder of
the guide.

```
debian@ns547544:~$ sudo su
root@ns547544:/home/debian# cd # Change back to the root home directory
root@ns547544:~#
```

Subsequent command blocks will omit the terminal prompt for easier copy-pasting.

### Setup Variables

A small number of variables are used in this guide to make copy-pasting commands easier. If any any point during setup
your connection disconnects and your shell loses these variables, set them again before continuing. Set the following to
your own values:

```
ADMIN_USER=""           # I use 'tjack'
ADMIN_USER_COMMENT=""   # I use 'Thomas Jack'
ADMIN_SSH_KEY=""        # I use my personal SSH key
APP_USER=""             # I use 'app'
SSH_PORT=""             # I use 2222
```

### System Updates

Start by updating the system:

```
apt update && apt full-upgrade -y
```

This command first updates the package manager with the latest package information and then performs a `full-upgrade`
which differs from a normal `upgrade` by also removing packages if necessary.

Clean up any stale packages:

```
apt autoclean -y && apt autoremove -y
```

### Essential Packages

Install useful packages including the `fish` shell (personal preference). Some are likely to already be installed.

```
apt install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  ufw \
  fail2ban \
  rsyslog \
  unattended-upgrades \
  vim \
  git \
  htop \
  fish \
  tree \
  net-tools \
  sysstat
```

### Create Admin User

The admin user will be a user that has privileged access to the server but does not run applications. It is best practice to not directly connect as `root`, however, this user effectively has `root` access due to unrestricted passwordless `sudo` capabilities. Given my risk tolerance, this is acceptable.

Create the user with a home directory and the fish shell:

```
useradd -m -s /usr/bin/fish -c "$ADMIN_USER_COMMENT" "$ADMIN_USER"
```

Add the user to the `sudo` group:

```
usermod -aG sudo "$ADMIN_USER"
```

Configure passwordless `sudo` for the admin user:

```
echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$ADMIN_USER"
chmod 0440 "/etc/sudoers.d/$ADMIN_USER"
```

Create the admin users SSH directory with proper ownership and file modes. Then, add the admin users key to the
authorized keys file.

```
mkdir -p "/home/$ADMIN_USER/.ssh"
chmod 700 "/home/$ADMIN_USER/.ssh"
chown "$ADMIN_USER:$ADMIN_USER" "/home/$ADMIN_USER/.ssh"
echo "$ADMIN_SSH_KEY" > "/home/$ADMIN_USER/.ssh/authorized_keys"
chmod 600 "/home/$ADMIN_USER/.ssh/authorized_keys"
chown "$ADMIN_USER:$ADMIN_USER" "/home/$ADMIN_USER/.ssh/authorized_keys"
```

Configure the fish shell with proper terminal colors:

```
mkdir -p "/home/$ADMIN_USER/.config/fish"
echo "set -gx TERM xterm-256color" > "/home/$ADMIN_USER/.config/fish/config.fish"
chmod 755 "/home/$ADMIN_USER/.config/fish"
chmod 644 "/home/$ADMIN_USER/.config/fish/config.fish"
chown -R "$ADMIN_USER:$ADMIN_USER" "/home/$ADMIN_USER/.config"
```

### Create Application User

The application user will be a non-privileged user that runs containerized applications. This user has no `sudo` access and is isolated from administrative functions.

Create the user with a home directory and the fish shell:

```
useradd -m -s /usr/bin/fish -c "Application User" "$APP_USER"
```

Configure the fish shell with proper terminal colors:

```
mkdir -p "/home/$APP_USER/.config/fish"
echo "set -gx TERM xterm-256color" > "/home/$APP_USER/.config/fish/config.fish"
chmod 755 "/home/$APP_USER/.config/fish"
chmod 644 "/home/$APP_USER/.config/fish/config.fish"
chown -R "$APP_USER:$APP_USER" "/home/$APP_USER/.config"
```

### SSH Hardening

Hardening SSH access will change the default port to a non-standard SSH port. This can prevent the bulk of bots and scanners
which constantly attempt to find servers with open or weakly configured SSH access across the internet. This configuration will also restrict SSH access to our admin user and turn off password based SSH authentication in favour of SSH keys.

It is good practice to backup the configuration which shipped with your server:

```
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
```

Install the configuration, overwriting the current file:

```
echo "# Hardened SSH Configuration
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
AllowUsers $ADMIN_USER
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
Subsystem sftp /usr/lib/openssh/sftp-server" > /etc/ssh/sshd_config
```

Ensure the SSH service is enabled and reload the configuration:

```
systemctl enable ssh
systemctl reload ssh
```

**IMPORTANT**: Do not close your current SSH session yet. Open a new terminal and test the connection with the new settings before proceeding:

```
ssh -p $SSH_PORT $ADMIN_USER@SERVER_IP
```

Replace `SERVER_IP` with your server's IP address. If the connection succeeds, you can safely continue. If it fails, you still have your current session to fix any configuration issues.

### Setup fail2ban

fail2ban is a utility which monitors for unsuccesful SSH attempts in your authentication logs and temporarily bans IP
addresses which exceed a threshold. Write the configuration file and restart the service:

```
echo "[DEFAULT]
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
maxretry = 5" > /etc/fail2ban/jail.local

chmod 644 /etc/fail2ban/jail.local
chown root:root /etc/fail2ban/jail.local

systemctl enable fail2ban
systemctl restart fail2ban
```

Execute a command to check if `fail2ban` is running:

```
systemctl status fail2ban
```

### Configure Firewall

`ufw` is the utility used for controlling the host firewall. A good starting place is to allow all outbound traffic,
deny all inbound traffic, and then selectively allow SSH + web traffic to your server. If your server will not serve
web content, those rules can be omitted.

```
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp" comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable
```

Validate the rules:

```
ufw status verbose
```

### Secure File Permissions

Set secure file permissions. This should already be done but it is good defensive practice to set it explicitly.

```
chmod 644 /etc/passwd
chmod 640 /etc/shadow
chmod 644 /etc/group
chmod 640 /etc/gshadow
chmod 600 /etc/ssh/sshd_config
```

### Configure Automatic Updates

The `unattended-upgrades` package automatically installs security updates to keep the system patched without manual intervention. This configuration enables automatic security updates while preventing automatic reboots, giving you control over when the server restarts. Configure the service:

```
echo 'Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";' > /etc/apt/apt.conf.d/50unattended-upgrades
chmod 644 /etc/apt/apt.conf.d/50unattended-upgrades
chown root:root /etc/apt/apt.conf.d/50unattended-upgrades

echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades
chmod 644 /etc/apt/apt.conf.d/20auto-upgrades
chown root:root /etc/apt/apt.conf.d/20auto-upgrades

systemctl enable unattended-upgrades
systemctl start unattended-upgrades
```

Validate that the service is running:

```
systemctl status unattended-upgrades
```

You should see `active (running)` in the output. Verify the automatic upgrade configuration is recognized:

```
apt-config dump APT::Periodic::Unattended-Upgrade
```

This should return `APT::Periodic::Unattended-Upgrade "1";` confirming automatic upgrades are enabled.

### Enable System Statistics

The `sysstat` package collects system performance and activity data, providing valuable metrics for monitoring CPU, memory, disk I/O, and network usage over time. Enable the service:

```
systemctl enable sysstat
systemctl start sysstat
```

Configure sysstat to retain 28 days of history instead of the default 7 days:

```
sed -i 's/^HISTORY=.*/HISTORY=28/' /etc/sysstat/sysstat
```

Verify the configuration change:

```
grep HISTORY /etc/sysstat/sysstat
```

This should return `HISTORY=28`.

### Install Podman

Podman is a container engine that provides an alternative to Docker. Install the required packages:

```
apt install -y podman passt uidmap dbus-user-session systemd-container
```

Configure subordinate user and group ID ranges for the application user to enable rootless container operation:

```
usermod --add-subuids 100000-165535 "$APP_USER"
usermod --add-subgids 100000-165535 "$APP_USER"
```

Enable lingering for the application user, which allows user services to run without an active login session:

```
loginctl enable-linger "$APP_USER"
```

Allow rootless Podman to bind to privileged ports below 1024:

```
echo "# Allow rootless Podman to bind to privileged ports (< 1024)
net.ipv4.ip_unprivileged_port_start=80" > /etc/sysctl.d/99-podman.conf
sysctl --system
```

Create the Podman storage configuration for the application user:

```
mkdir -p "/home/$APP_USER/.config/containers"
mkdir -p "/home/$APP_USER/.local/share/containers/storage"
chmod 755 "/home/$APP_USER/.config/containers"
APP_USER_UID=$(id -u "$APP_USER")
echo "[storage]
driver = \"overlay\"
runroot = \"/run/user/$APP_USER_UID/containers\"
graphroot = \"\$HOME/.local/share/containers/storage\"" > "/home/$APP_USER/.config/containers/storage.conf"
chmod 644 "/home/$APP_USER/.config/containers/storage.conf"
chown -R "$APP_USER:$APP_USER" "/home/$APP_USER/.config"
chown -R "$APP_USER:$APP_USER" "/home/$APP_USER/.local"
```

Validate the Podman installation by running a test container as the application user. Use `machinectl` to start a clean login shell as the application user with proper systemd user session initialization, which is required for rootless Podman to function correctly:

```
machinectl shell "$APP_USER@"
```

Once in the application user's shell, run a hello-world container:

```
podman run --rm hello-world
```

If successful, you should see a welcome message from the container. Exit the application user's shell:

```
exit
```

### Post Installation Tasks

With the server configuration complete, a reboot ensures all changes take effect cleanly. After rebooting, reconnect using the newly configured admin user and SSH port. With the admin user established, it's time to audit and clean up any provisioning users (like `debian`) that may have been created by the cloud provider, and ensure the `root` account doesn't contain any SSH keys that would allow direct access.

Reboot the server:

```
reboot
```

After the server comes back online, reconnect using the admin user on the new SSH port. These variables won't be set
in your host. Replace them with the correct values.

```
ssh -p $SSH_PORT $ADMIN_USER@1.2.3.4
```

Once connected, check for other interactive users with login shells that can be deleted:

```
sudo grep -E '/bin/(bash|sh|fish|zsh)' /etc/passwd
```

If you see any provisioning users like `debian` that are no longer needed, remove them:

```
sudo userdel -r debian
```

Finally, ensure the `root` account doesn't contain any SSH keys in its authorized keys file:

```
sudo rm /root/.ssh/authorized_keys
```

## Maintenance

TODO: Add maintenance procedures and best practices.
