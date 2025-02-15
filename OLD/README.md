#### Assign Static IP
    echo "
    interface eth0
    static ip_address=192.168.7.254/24
    static routers=192.168.7.1" >> /etc/dhcpcd.conf
--------------------------------------------------------------------------------
#### Grant new user account with privileges & assign new privileges
    sudo usermod -aG sudo,root focal && sudo visudo
#### Add the following underneath User privilege specification 
    focal	ALL=(ALL:ALL) ALL 
#### Add the following to the bottom of file under includedir /etc/sudoers.d 
    focal ALL=(ALL) NOPASSWD: ALL
#### Gain Super User Privilages
    sudo su
#### Copy ssh key to server
    mkdir -p /home/focal/.ssh/ && touch /home/focal/.ssh/authorized_keys
    curl https://github.com/cityplug.keys >> /home/focal/.ssh/authorized_keys
#### Secure SSH Server by changing default port
    nano -w /etc/ssh/sshd_config
###### Find the line that says “#Port 22” and change it to desired port 
###### Change “PermitRootLogin” and set to “no”. Set PermitRootLogin to “no”, 
###### Scroll further and set “PasswordAuthentication” to “no” and finally set PasswordAuthentication to “no”
    apt update && apt full-upgrade -y && reboot && exit
--------------------------------------------------------------------------------
#### Host Machine
    echo "
    net.ipv4.ip_forward = 1
    net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
--------------------------------------------------------------------------------
arping -v
arping -c 3 192.168.0.150