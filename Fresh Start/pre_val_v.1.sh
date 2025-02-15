#!/bin/bash
set -euo pipefail  # Strict error handling
set -x  # Enable debugging (optional, can be removed)

# Define Variables
INTERFACE="eth0"  # Change to "wlan0" for Wi-Fi
STATIC_IP="192.168.7.254/24"
GATEWAY="192.168.7.1"
DNS_SERVERS="8.8.8.8 8.8.4.4"
USERNAME="focal"
SSH_KEYS_URL="https://github.com/cityplug.keys"
SSH_CONFIG="/etc/ssh/sshd_config"

# Prompt user before applying network settings
echo "### Proposed Network Settings ###"
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

echo "### Configuring User Privileges ###"
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/$USERNAME" > /dev/null

# Ask if the user wants to import SSH keys
read -rp "Would you like to import your SSH keys? (y/n): " choice

if [[ "$choice" =~ ^[Yy]$ ]]; then
    sudo mkdir -p "/home/$USERNAME/.ssh"
    sudo chmod 700 "/home/$USERNAME/.ssh"
    sudo touch "/home/$USERNAME/.ssh/authorized_keys"
    sudo curl -fsSL "$SSH_KEYS_URL" | sudo tee -a "/home/$USERNAME/.ssh/authorized_keys" > /dev/null
    sudo chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
    sudo chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
    echo "✅ SSH keys imported successfully."
else
    echo "❌ SSH keys import canceled."
fi

echo "### Securing SSH Server ###"

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

# Restart SSH service
sudo systemctl restart sshd
echo "SSH has been secured and is now running on port $SSH_PORT"

echo "### Configuring UFW Firewall ###"

# Set up UFW rules
sudo ufw allow from 10.1.1.0/24 to any
sudo ufw delete allow 22 2>/dev/null || true  # Ensure default SSH (22) is removed
sudo ufw allow "$SSH_PORT"
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw logging on

# Ask if the user wants to enable UFW
read -rp "Would you like to enable UFW? (Y/N): " response
case "$response" in
    [Yy]* ) echo "Enabling UFW..."; sudo ufw enable ;;
    [Nn]* ) echo "UFW not enabled." ;;
    * ) echo "Invalid response. Please enter Y or N." ;;
esac

# Show UFW status
sudo ufw status verbose

# Ensure groups exist before adding user
for group in ssh-users docker; do
    if getent group "$group" > /dev/null 2>&1; then
        sudo usermod -aG "$group" "$USERNAME"
    fi
done

echo "### Updating and Upgrading System ###"
sudo apt update && sudo apt full-upgrade -y

echo "### Enabling Packet Forwarding ###"
sudo tee -a /etc/sysctl.conf > /dev/null <<EOF

# Enable IPv4 and IPv6 Forwarding
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

sudo sysctl -p

echo "### Installing Useful Tools ###"
for pkg in neofetch htop lm-sensors; do
    if ! dpkg -l | grep -q "$pkg"; then
        sudo apt-get install -y "$pkg"
    fi
done

echo "### Customizing MOTD ###"
sudo chmod -x /etc/update-motd.d/*

MOTD_SCRIPT="/etc/update-motd.d/00-custom"
sudo tee "$MOTD_SCRIPT" > /dev/null << 'EOF'
#!/bin/bash
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}System info as of: ${GREEN}$(date)${NC}"
echo -e "${YELLOW}Disk Usage:${NC} $(df -h / | awk 'NR==2 {print $5 " used of " $2}')"
echo -e "${YELLOW}Memory:${NC} $(free -m | awk 'NR==2 {printf "%sMB / %sMB (%.2f%%)", $3, $2, $3*100/$2 }')"
echo -e "${RED}IPv4 Address:${NC} $(hostname -I | awk '{print $1}')"
if command -v docker &> /dev/null; then
    echo -e "${BLUE}Docker Containers:${NC} $(docker ps -q | wc -l)"
    docker ps --format "  ${GREEN}Container:${NC} {{.Names}} ${YELLOW}Status:${NC} {{.Status}}" | sed 's/^/  /'
fi
EOF

sudo chmod +x "$MOTD_SCRIPT"

echo "### Checking Boot Performance ###"
sudo systemd-analyze blame

echo "### Configuration Complete! ###"

# Check for Docker Installation
sudo docker-compose --version && sudo docker --version

# Ask to connect to Tailscale
read -rp "Connect to Tailscale? (y/n): " choice
if [[ "$choice" =~ ^[Yy]$ ]]; then
    sudo tailscale up --advertise-routes=192.168.41.0/24 --advertise-exit-node
    echo "✅ Connected to Tailscale."
else
    echo "❌ Connection to Tailscale cancelled."
fi

echo "### Rebooting System in 10 Seconds... ###"
sleep 10
sudo reboot
