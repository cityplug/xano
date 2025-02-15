#!/bin/bash
set -euo pipefail
LOG_FILE="/var/log/system_optimization.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "### Starting System Optimization ###"

## Disable Unnecessary Services
echo "Disabling unnecessary services..."
for service in bluetooth hciuart wpa_supplicant; do
    if systemctl is-enabled --quiet "$service.service"; then
        sudo systemctl disable "$service.service"
        echo "Disabled $service.service"
    else
        echo "$service.service was not enabled."
    fi
done

## Optimize Boot Process
echo "Optimizing boot..."
sudo sed -i '/^disable_splash/d' /boot/config.txt
sudo sed -i '/^boot_delay/d' /boot/config.txt
echo -e "disable_splash=1\nboot_delay=0" | sudo tee -a /boot/config.txt
sudo sed -i 's/$/ fastboot noswap/' /boot/cmdline.txt

## Install Logging Tools
echo "Installing logging tools..."
sudo apt-get install -y busybox-syslogd || echo "Failed to install busybox-syslogd."

## Docker Optimization
echo "Configuring Docker..."
sudo systemctl enable docker
sudo mkdir -p /etc/systemd/system/docker.service.d
echo -e "[Service]\nTimeoutStartSec=5s\nExecStartPre=-/sbin/modprobe overlay" | sudo tee /etc/systemd/system/docker.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl restart docker

## Storage Optimization
STORAGE_DEVICE="/dev/sda1"
MOUNT_POINT="/mnt/storage"

if ! blkid "$STORAGE_DEVICE"; then
    echo "Formatting $STORAGE_DEVICE..."
    sudo mkfs.ext4 "$STORAGE_DEVICE"
fi

sudo mkdir -p "$MOUNT_POINT"
if ! grep -qs "$MOUNT_POINT" /proc/mounts; then
    sudo mount "$STORAGE_DEVICE" "$MOUNT_POINT"
    echo "$STORAGE_DEVICE $MOUNT_POINT ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab
fi

## Configure ZRAM
echo "Configuring ZRAM..."
sudo apt-get install -y zram-tools
sudo sed -i 's/#ALGO=lz4/ALGO=lz4/' /etc/default/zramswap
sudo systemctl restart zramswap

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

echo -e "${BLUE}System info as of: ${GREEN}$(date)${NC}"
echo -e "${YELLOW}Load:${NC} $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
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

echo "### System Optimization Complete! ###"
