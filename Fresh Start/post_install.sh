#!/bin/bash

# System Optimization and MOTD Customization for Raspberry Pi with Docker
set -euo pipefail  # Strict error handling
LOG_FILE="/var/log/system_optimization.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "### Starting system optimization ###"

## SECTION 1: Enable and Disable Services
echo "Managing services for optimal startup..."
systemctl list-unit-files --type=service

for service in bluetooth hciuart wpa_supplicant; do
    if systemctl is-active --quiet "$service.service"; then
        sudo systemctl disable "$service.service"
        echo "Disabled $service.service"
    else
        echo "$service.service was not running."
    fi
done

## SECTION 2: Boot Optimization
echo "Optimizing boot process..."
sudo sed -i '/^disable_splash/d' /boot/config.txt
sudo sed -i '/^boot_delay/d' /boot/config.txt
echo -e "disable_splash=1\nboot_delay=0" | sudo tee -a /boot/config.txt

sudo sed -i 's/$/ fastboot noswap/' /boot/cmdline.txt

## SECTION 3: Install and Configure Logging Tools
echo "Installing and configuring logging tools..."
sudo apt-get install -y busybox-syslogd || echo "Failed to install busybox-syslogd."

## SECTION 4: Docker Configuration
echo "Setting up Docker..."
sudo systemctl enable docker

# Add startup optimizations
DOCKER_OVERRIDE="/etc/systemd/system/docker.service.d/override.conf"
sudo mkdir -p /etc/systemd/system/docker.service.d
echo -e "[Service]\nTimeoutStartSec=5s\nExecStartPre=-/sbin/modprobe overlay" | sudo tee "$DOCKER_OVERRIDE"
sudo systemctl daemon-reload
sudo systemctl restart docker

## SECTION 5: Storage Optimization
echo "Configuring storage..."
STORAGE_DEVICE="/dev/sda1"
MOUNT_POINT="/mnt/storage"

# Check if device exists and is not already mounted
if lsblk -no MOUNTPOINT "$STORAGE_DEVICE" | grep -q .; then
    echo "Storage device $STORAGE_DEVICE is already mounted, skipping format."
else
    echo "Formatting and mounting $STORAGE_DEVICE..."
    sudo mkfs.ext4 "$STORAGE_DEVICE"
    sudo mkdir -p "$MOUNT_POINT"
    sudo mount "$STORAGE_DEVICE" "$MOUNT_POINT"
    echo "$STORAGE_DEVICE $MOUNT_POINT ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab
fi

## SECTION 6: ZRAM Configuration
echo "Setting up ZRAM for memory optimization..."
sudo apt-get install -y zram-tools
sudo sed -i 's/#ALGO=lz4/ALGO=lz4/' /etc/default/zramswap
sudo systemctl restart zramswap

## SECTION 7: MOTD Customization
echo "Customizing MOTD..."
sudo apt-get install -y neofetch htop lm-sensors

# Disable default MOTD scripts
sudo chmod -x /etc/update-motd.d/*

# Create custom MOTD script
MOTD_SCRIPT="/etc/update-motd.d/00-custom"
sudo tee "$MOTD_SCRIPT" > /dev/null << 'EOF'
#!/bin/bash
# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}System information as of: ${GREEN}$(date)${NC}\n"
echo -e "${YELLOW}System load:${NC} $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
echo -e "${YELLOW}Usage of /:${NC} $(df -h / | awk 'NR==2 {print $5 " used of " $2}')"
echo -e "${YELLOW}Memory usage:${NC} $(free -m | awk 'NR==2 {printf "%sMB / %sMB (%.2f%%)", $3, $2, $3*100/$2 }')"
echo -e "${YELLOW}Swap usage:${NC} $(free -m | awk 'NR==3 {printf "%sMB / %sMB (%.2f%%)", $3, $2, $3*100/$2 }')"
echo -e "${YELLOW}Temperature:${NC} $(vcgencmd measure_temp | cut -d '=' -f2)"
echo -e "${YELLOW}Processes:${NC} $(ps ax | wc -l)"
echo -e "${YELLOW}Users logged in:${NC} $(who | wc -l)\n"
echo -e "${RED}IPv4 address for eth0:${NC} $(hostname -I | awk '{print $1}')"
echo -e "${RED}IPv4 address for docker0:${NC} $(ip addr show docker0 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)\n"
echo -e "${BLUE}Docker containers running:${NC} $(docker ps -q | wc -l)"
docker ps --format "  ${GREEN}Container:${NC} {{.Names}} ${YELLOW}Status:${NC} {{.Status}}" | sed 's/^/  /'
EOF

# Set permissions and test the MOTD script
sudo chmod +x "$MOTD_SCRIPT"
sudo "$MOTD_SCRIPT"

## SECTION 8: Test Boot Performance
echo "Measuring boot performance..."
systemd-analyze
systemd-analyze blame

echo "### System optimization complete! ###"
