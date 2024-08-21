#!/usr/bin/env bash

GO_VERSION=1.23.0
ARCH=arm64
SHELL_RC="$HOME/.bashrc"

TESLA_BIN_DIR=/home/pi/bin/tesla

# Fail script if any command fails
set -e

read -p "Enter Tesla VIN: " TESLA_VIN
read -p "Enter MQTT Broker host/ip: " MQTT_BROKER

echo "Tesla VIN is ${TESLA_VIN}"
echo "MQTT Broker is ${MQTT_BROKER}"
read -p "Is this correct? [y/n] " YES_NO

if [ "${YES_NO}" != "y" ]; then
    echo "ERROR: Entered data wrong, exiting!"
    exit 1
fi

echo "### Fixing locale file"
sudo tee /etc/default/locale > /dev/null <<EOT
LANG=en_GB.UTF-8
LC_ALL=en_GB.UTF-8
LANGUAGE=en_GB.UTF-8
EOT
source /etc/default/locale

echo "### Updating system and install needed dependencies"
sudo apt update
sudo apt upgrade -y
sudo apt install mc git jq build-essential mosquitto-clients -y
sudo apt install libavahi-compat-libdnssd-dev avahi-utils -y

echo "### Creating user keypair"
yes '' | ssh-keygen -t rsa -N '' > /dev/null

echo "### Temporary bigger Swap to compile tesla-control with GO"
sudo dphys-swapfile swapoff
sudo tee /etc/dphys-swapfile > /dev/null <<EOT
CONF_SWAPSIZE=2048
EOT
sudo dphys-swapfile setup
sudo dphys-swapfile swapon

echo "### Installing GoLang ${GO_VERSION}"
cd ~
wget https://dl.google.com/go/go${GO_VERSION}.linux-${ARCH}.tar.gz
mkdir -p ~/.local/share
tar -C ~/.local/share -xzf go${GO_VERSION}.linux-${ARCH}.tar.gz
echo >> "${SHELL_RC}"
echo 'export GOPATH=$HOME/.local/share/go' >> "${SHELL_RC}"
echo 'export PATH=$HOME/.local/share/go/bin:/home/pi/bin/tesla:$PATH' >> "${SHELL_RC}"

source ${SHELL_RC}

echo "### Checkout Tesla vehicle-command project from GitHub"
mkdir -p ~/git
cd ~/git
git clone https://github.com/teslamotors/vehicle-command.git

echo "### Compiling tesla-control"
cd ~/git/vehicle-command/cmd/tesla-control
go build
mkdir -p ~/bin/tesla
cp tesla-control ~/bin/tesla/
cd ~/bin/tesla

echo "### Creating keypair needed for Tesla vehicle"
openssl ecparam -genkey -name prime256v1 -noout > private.pem
openssl ec -in private.pem -pubout > public.pem

echo "### Downloading MQTT wrapper script"
curl -o ${TESLA_BIN_DIR}/tesla-mqtt.sh https://raw.githubusercontent.com/gry79/rip-zero-2w-tesla-ble/main/tesla-mqtt.sh -L
chmod 0755 ${TESLA_BIN_DIR}/tesla-mqtt.sh

tee ${TESLA_BIN_DIR}/tesla-mqtt.properties > /dev/null <<EOT
TESLA_VIN=${TESLA_VIN}
MQTT_BROKER=${MQTT_BROKER}
TOPIC_ID=$(hostname)
EOT

echo "### Allowing tesla-control binary to access Bluetooth"
sudo setcap 'cap_net_admin=eip' "${TESLA_BIN_DIR}/tesla-control"

echo "### Disabling Swap"
sudo systemctl stop dphys-swapfile.service
sudo systemctl disable dphys-swapfile.service

echo "### Disabling apt-daily timers"
sudo systemctl stop apt-daily.timer
sudo systemctl stop apt-daily-upgrade.timer
sudo systemctl disable apt-daily.timer
sudo systemctl disable apt-daily-upgrade.timer

echo "### Creating systemd unit file for MQTT wrapper script"
sudo tee /lib/systemd/system/tesla-mqtt.service > /dev/null <<EOT
[Unit]
Description=Accepts command from MQTT to send to Tesla vehicle via BLE
Wants=network-online.target
After=network.target network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi
ExecStart=/home/pi/bin/tesla/tesla-mqtt.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT

echo "### Installing welcome script on logon"
sudo curl -o /etc/profile.d/xinfo.sh https://raw.githubusercontent.com/gry79/rip-zero-2w-tesla-ble/main/xinfo.sh -L
sudo chmod 0755 /etc/profile.d/xinfo.sh

echo "### Setting up some housekeeping cron jobs to free some valuable space"
tee /tmp/c1 > /dev/null <<EOT
0 0 * * * sudo journalctl --vacuum-time=1s
0 0 * * * sudo rm -f /media/root-rw/overlay/var/backups/*.gz
0 0 * * * history -c && history -w
0 0 * * * sudo apt clean
EOT
crontab /tmp/c1
rm -f /tmp/c1

echo "### Setting boot partition read-only to prevent SD card failure"
sudo awk '$2~"^/boot/firmware$" && $4~"^defaults$"{$4=$4",ro"}1' OFS="\t" /etc/fstab > /tmp/fstab
sudo mv -f /tmp/fstab /etc/fstab

echo "### Enabling systemd unit file"
sudo systemctl enable tesla-mqtt.service
sudo systemctl start tesla-mqtt.service

echo "### Activating overlay filesystem to make SD card read-only to prevent failure"
sudo raspi-config nonint do_overlayfs 0

echo "### Doing some housekeeing now"
sudo journalctl --vacuum-time=1s
sudo rm -f /var/backups/*.gz
sudo apt clean
history -c && history -w

echo "### SUCCESS all done, rebooting in 5 seconds"
sleep 5
sudo reboot
