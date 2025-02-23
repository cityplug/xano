#!/bin/bash
set -euo pipefail
LOG_FILE="/var/log/system_validation.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "### Starting System validation ###"

## Define Variables
INTERFACE="eth0"
STATIC_IP="192.168.7.254/24"
GATEWAY="192.168.7.1"
DNS_SERVERS="8.8.8.8 8.8.4.4"
USERNAME="focal"
SSH_KEYS_URL="https://github.com/cityplug.keys"
SSH_CONFIG="/etc/ssh/sshd_config"

## Prompt user before applying network settings
echo "Interface: $INTERFACE"
echo "Static IP: $STATIC_IP"
echo "Gateway: $GATEWAY"
echo "DNS Servers: $DNS_SERVERS"

read -rp "Would you like to apply these network settings? (y/n): " apply_network

if [[ "$apply_network" =~ ^[Yy]$ ]]; then
    echo "### Applying Static IP to $INTERFACE ###"
    sudo nmcli connection modify "$INTERFACE" ipv4.addresses "$STATIC_IP"
    sudo nmcli connection modify "$INTERFACE" ipv4.gateway "$GATEWAY"
    sudo nmcli connection modify "$INTERFACE" ipv4.dns "$DNS_SERVERS"
    sudo nmcli connection modify "$INTERFACE" ipv4.method manual
    sudo nmcli connection reload
    sudo nmcli connection up "$INTERFACE"
    echo "✅ Network settings applied successfully."
else
    echo "❌ Network settings were not applied."
fi

## Disable Unnecessary Services
echo "### Disabling Unnecessary Services ###"
SERVICES=(bluetooth hciuart wpa_supplicant keyboard-setup modprobe@drm sys-kernel-tracing)
for service in "${SERVICES[@]}"; do
    if systemctl list-units --full -all | grep -q "$service.service"; then
        if systemctl is-enabled --quiet "$service.service"; then
            sudo systemctl disable --now "$service.service"
            echo "✅ Disabled: $service.service"
        else
            echo "⚠️ Already disabled: $service.service"
        fi
    else
        echo "❌ Service not found: $service.service"
    fi
done

echo "### Installing Required Packages and Tools ###"
PACKAGES=(git ufw curl ca-certificates gnupg software-properties-common zram-tools htop lm-sensors)
for pkg in "${PACKAGES[@]}"; do
    dpkg -l | grep -qw "$pkg" || sudo apt install -y "$pkg"
done

# Load OS release information
. /etc/os-release

echo "### Adding Debian Backports Repository and Installing Cockpit ###"
echo "deb http://deb.debian.org/debian ${VERSION_CODENAME}-backports main" | sudo tee /etc/apt/sources.list.d/backports.list
sudo apt update && sudo apt install -t ${VERSION_CODENAME}-backports -y cockpit


## Removing Default Ubuntu/Debian Legal Messages
sudo tee /etc/issue /etc/issue.net <<< "" > /dev/null
sudo rm -f /etc/motd && echo "Removed /etc/motd" || echo "/etc/motd not found, skipping."

echo "### Customizing MOTD ###"
[[ -d /etc/update-motd.d ]] && sudo chmod -x /etc/update-motd.d/*

MOTD_SCRIPT="/etc/update-motd.d/00-custom"
sudo tee "$MOTD_SCRIPT" > /dev/null << 'EOF'
#!/bin/bash
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Display system date and time
echo -e "System info as of: ${RED}$(date)${NC}"

# Display OS, Host, Kernel, and CPU information from neofetch
os_info=$(grep PRETTY_NAME /etc/os-release | cut -d '=' -f2 | tr -d '"')
host_info=$(hostnamectl | grep "Virtualization" | awk '{print $2, $3, $4, $5}')
kernel_info=$(uname -r)
cpu_info=$(lscpu | grep "Model name" | head -n1 | awk -F ':' '{print $2}' | sed 's/^ *//')

echo -e "${RED}OS:${NC} $os_info"
echo -e "${RED}Host:${NC} $host_info"
echo -e "${RED}Kernel:${NC} $kernel_info"
echo -e "${RED}CPU:${NC} $cpu_info"

# Display system load
echo -e "${YELLOW}System Load:${NC} $(cat /proc/loadavg | awk '{print $1, $2, $3}')"

# Display disk usage for root
disk_usage=$(df -h / | awk 'NR==2 {print $3 " used of " $2}')
echo -e "${YELLOW}Disk Usage:${NC} $disk_usage"

# Display memory usage
mem_usage=$(free -m | awk 'NR==2 {printf "%sMB / %sMB (%.2f%%)", $3, $2, $3*100/$2 }')
echo -e "${YELLOW}Memory Usage:${NC} $mem_usage"

# Display number of processes
echo -e "${YELLOW}Processes:${NC} $(ps aux --no-heading | wc -l)"

# Display IPv4 addresses for each interface
echo -e "${RED}IPv4 Addresses:${NC}"
ip -4 -o addr show | awk '{print "  " $2 ": " $4}'

# Display running Docker containers if Docker is installed
if command -v docker &> /dev/null; then
    echo -e "${BLUE}Docker Containers:${NC} $(docker ps -q | wc -l)"
    docker ps --format "  Container: {{.Names}} {{.Status}} Ports: {{.Ports}}"
fi
EOF

sudo chmod +x "$MOTD_SCRIPT" && echo "### MOTD Customization Complete ###"

## Securing SSH Server
echo "### Securing SSH Server ###"
sudo mkdir -p "/home/$USERNAME/.ssh"
sudo chmod 700 "/home/$USERNAME/.ssh"
sudo curl -fsSL "$SSH_KEYS_URL" | sudo tee -a "/home/$USERNAME/.ssh/authorized_keys" > /dev/null
sudo chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
sudo chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"

# Ask the user for the SSH port
while true; do
    read -rp "Enter the new SSH port number (1024-65535): " SSH_PORT
    if [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && (( SSH_PORT >= 1024 && SSH_PORT <= 65535 )); then
        break
    else
        echo "Invalid port. Please enter a number between 1024 and 65535."
    fi
done

# Backup SSH config
sudo cp "$SSH_CONFIG" "$SSH_CONFIG.bak"

# Update SSH config with the new port and security settings
sudo sed -i -E "s/^#?Port [0-9]+/Port $SSH_PORT/" "$SSH_CONFIG"
sudo sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' "$SSH_CONFIG"
sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' "$SSH_CONFIG"

sudo systemctl restart sshd
echo "SSH has been secured and is now running on port $SSH_PORT"
sleep 3

## Configure UFW Firewall
sudo ufw allow from 10.1.1.0/24 to any
sudo ufw delete allow 22 2>/dev/null || true # Ensure default SSH (22) is removed
sudo ufw allow "$SSH_PORT"
sudo ufw allow 9090/tcp  # Cockpit
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw logging on

read -rp "Would you like to enable UFW? (Y/N): " response
case "$response" in
    [Yy]* ) echo "Enabling UFW..."; sudo ufw enable ;;
    [Nn]* ) echo "UFW not enabled." ;;
    * ) echo "Invalid response. Please enter Y or N." ;;
esac

sudo ufw status verbose
sudo apt update && sudo apt full-upgrade -y

sudo tee -a /etc/sysctl.conf > /dev/null <<EOF
# Enable IPv4 and IPv6 Forwarding
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

sudo sysctl -p

## Setting up Tailscale
echo "### Setting up Tailscale ###"
if command -v tailscale &>/dev/null; then
    echo "✅ Tailscale is already installed."
else
    curl -fsSL https://tailscale.com/install.sh | sh && echo "✅ Tailscale installed successfully."
fi
# Ask to connect to Tailscale
read -rp "Connect to Tailscale? (y/n): " choice
if [[ "$choice" =~ ^[Yy]$ ]]; then
    sudo tailscale up --advertise-routes=192.168.41.0/24 --advertise-exit-node
    echo "✅ Connected to Tailscale."
else
    echo "❌ Connection to Tailscale cancelled."
fi

## Clean up unnecessary packages
echo "🧹 Running autoremove to clean up..."
sudo apt autoremove -y
echo "### Package Installation Complete! ###"
sleep 5

## Install Docker Official GPG key to Apt sources:
echo "Installing Docker..."
read -p "Would you like to install Docker? (Y/N): " response
if [[ "$response" == "y" ]]; then
    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        echo "Docker is already installed."
        # Ask if the user wants to update Docker
        read -p "Would you like to update Docker? (Y/N): " update_response
        if [[ "$update_response" == "y" ]]; then
            echo "Updating Docker..."
            # Set up Docker repository and update Docker
            sudo install -m 0755 -d /etc/apt/keyrings
            sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
            sudo chmod a+r /etc/apt/keyrings/docker.asc
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
            $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update && sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-compose -y
            echo "Docker has been updated."
        else
            echo "Docker update skipped."
        fi
    else
        # Docker is not installed, proceed with installation
        echo "Installing Docker..."
        # Set up Docker repository
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update && sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-compose -y 
        echo "Docker has been installed."
    fi
else
    echo "Docker installation skipped."
fi
sudo systemctl enable docker

for group in ssh-users docker; do
    if getent group "$group" > /dev/null 2>&1; then
        sudo usermod -aG "$group" "$USERNAME"
    fi
done

echo "Setup complete. Rebooting in 10s..."
sleep 10
sudo reboot
