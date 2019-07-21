#!/bin/bash

set -x
# This is a crazily lazy and bad structure script for a lazy man
# Please do not use unless you do not care your system be broken
{

if [ "$(id -u)" != "0" ]; then
  echo "Please give me root permission" 1>&2
  exit 1
fi

function append() {
  test "$(tail -c 1 "$2")" && echo "" >> "$2"
  echo "$1" >> "$2"
}

StartTimestamp="$(date +%s)"

# binary PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# simply detect IPv6 by dns config /etc/resolv.conf
if [ "" = "$(command grep 'nameserver' /etc/resolv.conf | cut -d' ' -f 2 | grep ':')" ]; then
  # disable IPv6 for ufw if no IPv6 dns detected
  sed -i 's/IPV6=yes/IPV6=no/g' /etc/default/ufw
fi

# enable commonly used ports (ufw)
ufw allow 22
ufw allow 80
ufw allow 443
ufw allow 8000
ufw allow 8080

# enable ufw
echo 'y' | ufw enable

# decrease swappiness
sysctl vm.swappiness=5
sysctl vm.vfs_cache_pressure=80 &
append 'vm.swappiness=5' /etc/sysctl.conf
append 'vm.vfs_cache_pressure=80' /etc/sysctl.conf &

# no src in general
sed -i 's/^deb-src/\#deb-src/g' /etc/apt/sources.list

# replace security.ubuntu.com with a local mirror
apt_local="$(grep ^deb /etc/apt/sources.list | grep ubuntu --color=never | awk '{print $2}' | sort | uniq -c | sort -Vr | head -n 1 | awk '{print $2}' | sed 's/\//\\\//g')"
sed -i "s/http:\/\/security.ubuntu.com\/ubuntu/$apt_local/g" /etc/apt/sources.list

# again for linuxmint config
if [ -r /etc/apt/sources.list.d/official-package-repositories.list ]; then
  apt_local="$(grep ^deb /etc/apt/sources.list.d/official-package-repositories.list | grep ubuntu --color=never | awk '{print $2}' | sort | uniq -c | sort -nr | head -n 1 | awk '{print $2}' | sed 's/\//\\\//g')"
  sed -i "s/http:\/\/security.ubuntu.com\/ubuntu/$apt_local/g" /etc/apt/sources.list.d/official-package-repositories.list
fi
# set timezone
timedatectl set-timezone Asia/Taipei &

# set unattended parameters
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

# disable root ssh login
sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
service ssh restart &

# update apt meta info
apt-get update

# upgrade/install the most important packages
apt-get --force-yes -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install apt bash bsdutils ca-certificates coreutils cpio dnsutils dpkg file gnupg linux-firmware login mount ntpdate openssh-client openssh-server openssl passwd patch ssh sudo udev util-linux wget

if lscpu | grep -q ^Hypervisor; then
  Hypervisor="$(lscpu | grep ^Hypervisor | awk '{print $3}')"
  case $Hypervisor in
    VMware)
      apt-get --force-yes -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install open-vm-tools
      ;;
    KVM)
      apt-get --force-yes -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install qemu-guest-agent
      ;;
  esac
fi

# sync system time
sudo ntpdate tw.pool.ntp.org
sudo ntpdate tw.pool.ntp.org &

# locale
locale-gen en_US.UTF-8
append "LC_ALL=en_US.UTF-8" /etc/default/locale

# install some essential and useful tools
apt-get --force-yes -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install dstat glances htop sysstat tmux vim vnstat

# modern NICs usually be 1Gbit ...
sed -i 's/^MaxBandwidth 100$/MaxBandwidth 1000/g' /etc/vnstat.conf
service vnstat restart &

# enable sysstat
sed -i 's/ENABLED="false"/ENABLED="true"/g' /etc/default/sysstat
service sysstat restart &

# now upgrade packages
apt-get --force-yes -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
apt-get --force-yes -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade

# first apt clean up
apt-get autoremove --force-yes -y
apt-get clean

# now install some commonly used pacakges
apt-get --force-yes -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install apt-file aptitude apt-show-versions aria2 bash-completion colordiff command-not-found cpu-checker curl debian-goodies dmidecode ethtool exfat-fuse fail2ban fbterm gdebi geoip-bin git hdparm iftop inxi iotop iperf iperf3 irssi jq lm-sensors lsof lynis mailutils make moc mosh mtr-tiny needrestart nmap p7zip-full p7zip-rar parallel pbzip2 pigz ppa-purge pv pxz rename smartmontools software-properties-common tcpdump timelimit tree ufw unattended-upgrades unzip w3m whois xfsprogs xterm youtube-dl zram-config ioping

# disable needrestart apt hook which is annoying
sed -i 's/^DPkg/\#DPkg/g' /etc/apt/apt.conf.d/99needrestart

# restart services need to be restarted
needrestart -r a

# reinstall bash-completion, sometimes it doesn't work properly
apt-get --force-yes -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install --reinstall bash-completion

# apt-file update
apt-file update &

# disable DNS lookup for ssh
append 'UseDNS no' /etc/ssh/sshd_config &

# second apt clean up
apt-get autoremove --force-yes -y
apt-get clean

# enable unattended-upgrades
echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
append 'APT::Periodic::Unattended-Upgrade "1";' /etc/apt/apt.conf.d/20auto-upgrades

# set SSD IO scheduler to noop, determinate by /sys/block/sd*/queue/rotational
append ' ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0",ATTR{queue/scheduler}="noop"' /etc/udev/rules.d/60-ssd-scheduler.rules

# enable mosh ports (ufw)
ufw allow mosh

# add-apt-ppa
wget https://github.com/PeterDaveHello/add-apt-ppa/raw/v0.0.1/add-apt-ppa -O /usr/bin/add-apt-ppa
ln -s /usr/bin/add-apt-ppa /usr/bin/apt-add-ppa

# Unitial setup
curl --compressed -L -o- https://github.com/PeterDaveHello/Unitial/raw/master/setup.sh | HOME='/root/' bash
if [ -n "$SUDO_USER" ]; then
  curl --compressed -L -o- https://github.com/PeterDaveHello/Unitial/raw/master/setup.sh | sudo -u "$SUDO_USER" bash
fi

wait

EndTimestamp="$(date +%s)"

echo -e "\nTotal time spent for this build is _$((EndTimestamp - StartTimestamp))_ second(s)\n"
}
