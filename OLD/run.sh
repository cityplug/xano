#!/bin/bash

# Raspberry Pi Debian 32GB/8Core/(4GB Swap) - (xano) setup script

#> apt update -y && apt install git ufw curl ca-certificates gnupg software-properties-common -y && apt full-upgrade -y && apt autoremove && reboot
#> cd /opt && git clone https://github.com/cityplug/xano && chmod +x /opt/xano/* && cd /opt/xano/ && ./run.sh

---------------------------
# --- Change root password
echo "#  ---  Change root password  ---  #"
passwd root

# --- Disable Bluetooth/WIFI & Splash
echo "
disable_splash=1
dtoverlay=disable-wifi
dtoverlay=disable-bt" >> /boot/config.txt

# --- Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# --- Install Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update && apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

# --- Create and allocate swap
echo "#  ---  Creating 4GB swap file  ---  #"
fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
sh -c 'echo "/swapfile none swap sw 0 0" >> /etc/fstab' && cat /etc/fstab

# --- Addons
rm -r /etc/update-motd.d/* && rm -r /etc/motd && 
wget https://raw.githubusercontent.com/cityplug/xano/main/10-uname -O /etc/update-motd.d/10-uname && chmod +x /etc/update-motd.d/10-uname

echo "
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
sysctl -p
systemctl stop systemd-resolved && systemctl disable systemd-resolved

# --- Security Addons
groupadd ssh-users
usermod -aG ssh-users,docker focal
sed -i '15i\AllowGroups ssh-users\n' /etc/ssh/sshd_config

# --- Firewall Rules 
ufw allow from 10.1.1.0/24 to any
ufw deny 22
ufw allow 4792
ufw allow 9000 #portainer agent

ufw logging on
ufw enable
ufw status

# -- Parent Folder
mkdir -p /mnt/xano_/appdata/immich
#chmod -R 777 /xano_/ && chown -R nobody:nogroup /xano_/

# --- Mount USB
echo "UUID=15b585b7-6eb4-42ce-9bfc-60398e975c74 /xano_/  auto   defaults,nofail 0 0" >> /etc/fstab
mount -a
systemctl daemon-reload

#--
systemctl enable docker 
docker-compose --version && docker --version
tailscale up --advertise-routes=192.168.7.0/24

sleep 5
reboot
#--------------------------------------------------------------------------------

# --- Docker Services
docker run -d -p 9000:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v /xano/appdata/portainer:/data portainer/portainer-ce:latest

wget https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml -O /xano_/docker-compose.yml
#wget -O .env https://github.com/immich-app/immich/releases/latest/download/example.env

cd /xano_/ && docker-compose up -d && docker ps
docker-compose logs -f

echo "#  ---  STOPPING ALL CONTAINERS  ---  #"
sleep 10
docker stop $(docker ps -a -q)

echo "#  ---  COMPLETED | REBOOTING SYSTEM  ---  #"
#------------------------------------------------------------------------------
sleep 10
reboot