#### Grant new user account with privileges & assign new privileges
    sudo usermod -aG sudo,root focal && sudo visudo
#### Add the following underneath User privilege specification 
    focal	ALL=(ALL:ALL) ALL 
#### Add the following to the bottom of file under includedir /etc/sudoers.d 
    focal ALL=(ALL) NOPASSWD: ALL

sudo apt install git -y && sudo git clone https://github.com/cityplug/xano && sudo chmod +x xano/*
cd xano/ && ./setup.sh