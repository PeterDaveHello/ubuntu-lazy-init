#!/bin/bash

set -x
# This is a crazily lazy and bad structure script for a lazy man
# Please do not use unless you do not care your system be broken
{

if [ "$(id -u)" != "0" ]; then
   echo "Please give me root permission" 1>&2
   exit 1
fi

StartTimestamp="`date +%s`"

# binary PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# no src in general
sed -i 's/^deb-src/\#deb-src/g' /etc/apt/sources.list

# replace security.ubuntu.com with a local mirror
apt_local="`grep ^deb /etc/apt/sources.list | grep ubuntu --color=never | awk '{print $2}' | sort | uniq -c | sort -r | head -n 1 | awk '{print $2}' | sed 's/\//\\\\\//g'`"
sed -i "s/http:\/\/security.ubuntu.com\/ubuntu/$apt_local/g" /etc/apt/sources.list

# again for linuxmint config
if [ -r /etc/apt/sources.list.d/official-package-repositories.list ]; then
    apt_local="`grep ^deb /etc/apt/sources.list.d/official-package-repositories.list | grep ubuntu --color=never | awk '{print $2}' | sort | uniq -c | sort -r | head -n 1 | awk '{print $2}' | sed 's/\//\\\\\//g'`"
    sed -i "s/http:\/\/security.ubuntu.com\/ubuntu/$apt_local/g" /etc/apt/sources.list.d/official-package-repositories.list
fi

# decrease swappiness
sysctl vm.swappiness=5
echo 'vm.swappiness=5' >> /etc/sysctl.conf

# no IPv6 in general
sed -i 's/IPV6=yes/IPV6=no/g' /etc/default/ufw

# enable commonly used ports (ufw)
ufw allow 22
ufw allow 80
ufw allow 443

# enable ufw
echo 'y' | ufw enable

# set timezone
timedatectl set-timezone Asia/Taipei

# set unattended parameters
export DEBIAN_FRONTEND=noninteractive

# disable root ssh login
sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
service ssh restart

# update apt meta info
apt-get update

# upgrade/install the most important packages
apt-get --force-yes -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install dnsutils openssh-server openssh-client bash apt dpkg coreutils mount login util-linux gnupg passwd bsdutils file openssl ca-certificates ssh wget linux-firmware cpio dnsutils patch udev sudo
# install some essential and useful tools
apt-get --force-yes -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install sysstat vnstat htop dstat vim tmux

# enable sysstat
sed -i 's/ENABLED="false"/ENABLED="true"/g' /etc/default/sysstat
service sysstat restart

# now upgrade packages
apt-get --force-yes -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
apt-get --force-yes -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade

# first apt clean up
apt-get autoremove --force-yes -y
apt-get clean

# now install some commonly used pacakges
apt-get --force-yes -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install tree aria2 aptitude moc bash-completion colordiff curl pbzip2 pigz fbterm fail2ban mtr-tiny ntpdate git p7zip-full mosh nmap apt-file gdebi command-not-found irssi geoip-bin w3m unzip tcpdump iftop iotop apt-show-versions lm-sensors sensord dmidecode hdparm xfsprogs smartmontools xterm mailutils unattended-upgrades p7zip-rar zram-config ppa-purge jq pxz iperf ethtool parallel whois lsof inxi realpath ufw

# disable DNS lookup for ssh
echo 'UseDNS no' >> /etc/ssh/sshd_config

# second apt clean up
apt-get autoremove --force-yes -y
apt-get clean

# unable unattended-upgrades
echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
echo 'APT::Periodic::Unattended-Upgrade "1";'  >> /etc/apt/apt.conf.d/20auto-upgrades

# Unitial setup
curl -L -o- https://github.com/PeterDaveHello/Unitial/raw/master/setup.sh | bash

EndTimestamp="`date +%s`"

echo -e "\nTotal time spent for this build is _$(($EndTimestamp - $StartTimestamp))_ second(s)\n"
}
