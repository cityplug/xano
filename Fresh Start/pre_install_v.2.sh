#!/bin/bash
set -euo pipefail  # Strict error handling

# Define Variables
##INTERFACE="eth0"  # Change to "wlan0" for Wi-Fi
##STATIC_IP="192.168.7.254/24"
##GATEWAY="192.168.7.1"
##DNS_SERVERS="8.8.8.8 8.8.4.4"
USERNAME="focal"
SSH_KEYS_URL="https://github.com/cityplug.keys"
SSH_CONFIG="/etc/ssh/sshd_config"

##echo "### Assigning Static IP to $INTERFACE ###"
##nmcli connection modify "$INTERFACE" ipv4.addresses "$STATIC_IP"
##nmcli connection modify "$INTERFACE" ipv4.gateway "$GATEWAY"
##nmcli connection modify "$INTERFACE" ipv4.dns "$DNS_SERVERS"
##nmcli connection modify "$INTERFACE" ipv4.method manual
##nmcli connection reload
##nmcli connection up "$INTERFACE"

echo "### Configuring User Privileges ###"
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/$USERNAME"

# Ask if the user wants to import SSH keys
read -p "Would you like to import your SSH keys? (y/n): " choice

if [[ "$choice" =~ ^[Yy]$ ]]; then
    mkdir -p "/home/$USERNAME/.ssh"
    touch "/home/$USERNAME/.ssh/authorized_keys"
    curl -fsSL "$SSH_KEYS_URL" >> "/home/$USERNAME/.ssh/authorized_keys"
    echo "SSH keys imported successfully."
else
    echo "SSH keys import canceled."
fi

echo "### Securing SSH Server ###"

# Ask the user for the SSH port
read -p "Enter the new SSH port number: " SSH_PORT

# Backup SSH config
sudo cp "$SSH_CONFIG" "$SSH_CONFIG.bak"

# Update SSH config with the new port and security settings
sudo sed -i "s/^#Port 22/Port $SSH_PORT/" "$SSH_CONFIG"
sudo sed -i "s/^Port [0-9]*/Port $SSH_PORT/" "$SSH_CONFIG"
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
sudo ufw allow 85  # Homer
sudo ufw allow 9000  # Portainer
sudo ufw logging on

# Ask if the user wants to enable UFW
read -p "Would you like to enable UFW? (Y/N): " response
if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "Enabling UFW..."
    sudo ufw enable
elif [[ "$response" =~ ^[Nn]$ ]]; then
    echo "UFW not enabled."
else
    echo "Invalid response. Please enter Y or N."
fi

# Show UFW status
sudo ufw status verbose

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
sudo apt-get install -y neofetch htop lm-sensors

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
systemd-analyze blame

echo "### Configuration Complete! Rebooting... ###"
sudo reboot
