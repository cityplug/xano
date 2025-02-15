#!/bin/bash
set -euo pipefail
LOG_FILE="/var/log/system_validation.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "### Starting System validation ###"

echo "### Disabling Unnecessary Services ###"

# List of services to disable
SERVICES=(
    bluetooth
    hciuart
    wpa_supplicant
    keyboard-setup
    modprobe@drm
    sys-kernel-tracing
)
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
echo "### Service disabling complete! ###"

## Optimize Boot Process
echo "Optimizing boot..."
# Remove boot_delay line; if this fails, print a warning and continue.
sudo sed -i '/^boot_delay/d' /boot/config.txt || echo "Warning: Could not remove boot_delay from /boot/config.txt"
# Append new boot options; if this fails, print a warning and continue.
echo -e "disable_splash=1\nboot_delay=0" | sudo tee -a /boot/config.txt || echo "Warning: Could not append boot options to /boot/config.txt"
# Append fastboot and noswap flags; if this fails, print a warning and continue.
sudo sed -i 's/$/ fastboot noswap/' /boot/cmdline.txt || echo "Warning: Could not append fastboot noswap to /boot/cmdline.txt"

## Configure ZRAM
echo "Configuring ZRAM..."
sudo apt-get install -y zram-tools
sudo sed -i 's/#ALGO=lz4/ALGO=lz4/' /etc/default/zramswap
sudo systemctl restart zramswap

# Define package list
echo "### Installing Required Packages ###"
PACKAGES=(
    git
    ufw
    curl
    ca-certificates
    gnupg
    software-properties-common
)
# Install packages
for pkg in "${PACKAGES[@]}"; do
    if dpkg -l | grep -qw "$pkg"; then
        echo "✅ $pkg is already installed."
    else
        echo "📦 Installing: $pkg..."
        sudo apt install -y "$pkg" && echo "✅ Installed: $pkg" || echo "❌ Failed to install: $pkg"
    fi
done
# Install Tailscale
echo "### Installing Tailscale ###"
if command -v tailscale &>/dev/null; then
    echo "✅ Tailscale is already installed."
else
    curl -fsSL https://tailscale.com/install.sh | sh && echo "✅ Tailscale installed successfully."
fi
# Clean up unnecessary packages
echo "🧹 Running autoremove to clean up..."
sudo apt autoremove -y
echo "### Package Installation Complete! ###"

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
systemctl enable docker

sleep 5
sudo reboot