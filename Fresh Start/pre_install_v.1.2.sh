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
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USERNAME

echo "### Setting Up SSH Access ###"
mkdir -p "/home/$USERNAME/.ssh"
touch "/home/$USERNAME/.ssh/authorized_keys"
chmod 700 "/home/$USERNAME/.ssh"
chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
chown -R "$USERNAME":"$USERNAME" "/home/$USERNAME/.ssh"

if curl -fsSL "$SSH_KEYS_URL" >> "/home/$USERNAME/.ssh/authorized_keys"; then
    echo "SSH keys added successfully."
else
    echo "Failed to retrieve SSH keys!"
fi

echo "### Securing SSH Server ###"
sudo cp "$SSH_CONFIG" "$SSH_CONFIG.bak"
sudo sed -i 's/^#Port 22/Port 4792/' "$SSH_CONFIG"
sudo sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' "$SSH_CONFIG"
sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' "$SSH_CONFIG"
sudo systemctl restart sshd

echo "### Updating and Upgrading System ###"
sudo apt update && sudo apt full-upgrade -y

echo "### Enabling Packet Forwarding ###"
echo -e "\n# Enable IPv4 and IPv6 Forwarding" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

## Customize MOTD
echo "Setting up MOTD..."
sudo apt-get install -y neofetch htop lm-sensors
sudo chmod -x /etc/update-motd.d/*

MOTD_SCRIPT="/etc/update-motd.d/00-custom"
sudo tee "$MOTD_SCRIPT" > /dev/null << 'EOF'
#!/bin/bash
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}System info as of: 
echo -e "${GREEN}$(date)${NC}"
echo -e "${YELLOW}Disk Usage:${NC} $(df -h / | awk 'NR==2 {print $5 " used of " $2}')"
echo -e "${YELLOW}Memory:${NC} $(free -m | awk 'NR==2 {printf "%sMB / %sMB (%.2f%%)", $3, $2, $3*100/$2 }')"
echo -e "${RED}IPv4 Address:${NC} $(hostname -I | awk '{print $1}')"
if command -v docker &> /dev/null; then
    echo -e "${BLUE}Docker Containers:${NC} $(docker ps -q | wc -l)"
    docker ps --format "  ${GREEN}Container:${NC} {{.Names}} ${YELLOW}Status:${NC} {{.Status}}" | sed 's/^/  /'
fi
EOF

sudo chmod +x "$MOTD_SCRIPT"
sudo "$MOTD_SCRIPT"

## Boot Performance Test
echo "Checking boot performance..."
systemd-analyze blame
echo "### Configuration Complete! Rebooting... ###"
sudo reboot
