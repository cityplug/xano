#!/bin/bash
set -euo pipefail  # Strict error handling

# Define Variables
INTERFACE="eth0"  # Change to "wlan0" for Wi-Fi
STATIC_IP="192.168.7.254/24"
GATEWAY="192.168.7.1"
DNS_SERVERS="8.8.8.8 8.8.4.4"
USERNAME="focal"
SSH_KEYS_URL="https://github.com/cityplug.keys"
SSH_CONFIG="/etc/ssh/sshd_config"

echo "### Assigning Static IP to $INTERFACE ###"
nmcli connection modify "$INTERFACE" ipv4.addresses "$STATIC_IP"
nmcli connection modify "$INTERFACE" ipv4.gateway "$GATEWAY"
nmcli connection modify "$INTERFACE" ipv4.dns "$DNS_SERVERS"
nmcli connection modify "$INTERFACE" ipv4.method manual
nmcli connection reload
nmcli connection up "$INTERFACE"

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
sudo sed -i 's/^#Port 22/Port 2222/' "$SSH_CONFIG"
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

echo "### Configuration Complete! Rebooting... ###"
sudo reboot
