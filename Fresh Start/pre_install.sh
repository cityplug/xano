#!/bin/bash

# Define Variables
WIFI_INTERFACE="eth0"
STATIC_IP="192.168.7.254/24"
GATEWAY="192.168.7.1"
DNS_SERVERS="8.8.8.8 8.8.4.4"
USERNAME="focal"
SSH_KEYS_URL="https://github.com/cityplug.keys"
SSH_CONFIG="/etc/ssh/sshd_config"

echo "### Assigning Static IP to $WIFI_INTERFACE ###"
nmcli connection show
nmcli connection modify "$WIFI_INTERFACE" ipv4.addresses "$STATIC_IP"
nmcli connection modify "$WIFI_INTERFACE" ipv4.gateway "$GATEWAY"
nmcli connection modify "$WIFI_INTERFACE" ipv4.dns "$DNS_SERVERS"
nmcli connection modify "$WIFI_INTERFACE" ipv4.method manual
nmcli connection up "$WIFI_INTERFACE"

echo "### Assigning New Privileges ###"
# Edit sudoers safely using visudo
sudo bash -c "echo '$USERNAME ALL=(ALL:ALL) ALL' >> /etc/sudoers"
sudo bash -c "echo '$USERNAME ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers.d/$USERNAME"

echo "### Enabling Superuser Privileges ###"
sudo su

echo "### Setting Up SSH Access ###"
# Create SSH directory if it doesn't exist
mkdir -p /home/$USERNAME/.ssh/
touch /home/$USERNAME/.ssh/authorized_keys
chmod 700 /home/$USERNAME/.ssh/
chmod 600 /home/$USERNAME/.ssh/authorized_keys
chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh/

# Download SSH keys securely
if curl -fsSL "$SSH_KEYS_URL" >> /home/$USERNAME/.ssh/authorized_keys; then
    echo "SSH keys added successfully."
else
    echo "Failed to retrieve SSH keys!"
fi

echo "### Securing SSH Server ###"
# Backup SSH configuration before modifying
sudo cp "$SSH_CONFIG" "$SSH_CONFIG.bak"

# Update SSH configuration using sed
sudo sed -i 's/#Port 22/Port <your_desired_port>/g' "$SSH_CONFIG"
sudo sed -i 's/#PermitRootLogin yes/PermitRootLogin no/g' "$SSH_CONFIG"
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' "$SSH_CONFIG"

# Restart SSH service
sudo systemctl restart sshd

echo "### Updating and Upgrading System ###"
sudo apt update && sudo apt full-upgrade -y && sudo reboot

echo "### Enabling Packet Forwarding on Host Machine ###"
echo -e "\n# Enable IPv4 and IPv6 Forwarding" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "### Configuration Complete! ###"
