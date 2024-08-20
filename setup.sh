#!/usr/bin/env bash

sudo tee /etc/default/locale > /dev/null <<EOT
LANG=en_GB.UTF-8
LC_ALL=en_GB.UTF-8
LANGUAGE=en_GB.UTF-8
EOT

sudo apt update
sudo apt upgrade -y
sudo apt install mc git jq build-essentials mosquitto-clients -y
sudo apt install libavahi-compat-libdnssd-dev avahi-utils -y

sudo dphys-swapfile swapoff
sudo mcedit /etc/dphys-swapfile
sudo tee /etc/dphys-swapfile > /dev/null <<EOT
CONF_SWAPSIZE=2048
EOT
sudo dphys-swapfile setup
sudo dphys-swapfile swapon

mkdir -p ~/git
cd ~/git
git checkout https://github.com/teslamotors/vehicle-command.git

VERSION=1.23.0
ARCH=arm64
SHELL_RC="$HOME/.bashrc"

cd ~
wget https://dl.google.com/go/go$VERSION.linux-$ARCH.tar.gz
mkdir -p ~/.local/share
tar -C ~/.local/share -xzf go$VERSION.linux-$ARCH.tar.gz
echo 'export GOPATH=$HOME/.local/share/go' >> "$SHELL_RC"
echo 'export PATH=$HOME/.local/share/go/bin:$HOME/bin/tesla:$PATH' >> "$SHELL_RC"

source ~/.bash_profile

cd ~/git/vehicle-command/cmd/tesla-control
go build
mkdir -p ~/bin/tesla
cp tesla-control ~/bin/tesla/
cd ~/bin/tesla
openssl ecparam -genkey -name prime256v1 -noout > private.pem
openssl ec -in private.pem -pubout > public.pem

sudo setcap 'cap_net_admin=eip' "~/bin/tesla/tesla-control"

sudo systemctl stop dphys-swapfile.service
sudo systemctl disable dphys-swapfile.service

sudo systemctl stop apt-daily.timer
sudo systemctl stop apt-daily-upgrade.timer
sudo systemctl disable apt-daily.timer
sudo systemctl disable apt-daily-upgrade.timer



sudo tee /tmp/c1 > /dev/null <<EOT
0 0 * * * sudo journalctl --vacuum-time=1s
0 0 * * * sudo rm -f /media/root-rw/overlay/var/backups/*.gz
0 0 * * * history -c && history -w
0 0 * * * sudo apt clean
EOT
crontab /tmp/c1
rm -f /tmp/c1


sudo journalctl --vacuum-time=1s
sudo rm -f /var/backups/*.gz
sudo apt clean
history -c && history -w

sudo raspi-config nonint do_overlayfs 0
