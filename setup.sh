#!/usr/bin/env bash

GO_VERSION=1.24.5
ARCH=arm64

TESLA_BIN_DIR=${HOME}/bin/tesla
GIT_REPO_DIR=${HOME}/git

do_exec () {
    $@
    if [ "$?" -ne "0" ]; then
        echo "ERROR executing command: $@"
        exit 1
    fi
}

disable_service () {
    local SERVICE_NAME=$1
    sudo systemctl is-active --quiet ${SERVICE_NAME}
    if [ "$?" -eq "0" ]; then
        echo "### Stopping service ${SERVICE_NAME}"
        do_exec sudo systemctl stop ${SERVICE_NAME}
    fi
    sudo systemctl is-enabled --quiet ${SERVICE_NAME}
    if [ "$?" -eq "0" ]; then
        echo "### Disabling service ${SERVICE_NAME}"
        do_exec sudo systemctl disable ${SERVICE_NAME}
    fi
}

enable_service () {
    local SERVICE_NAME=$1
    sudo systemctl is-enabled --quiet ${SERVICE_NAME}
    if [ "$?" -ne "0" ]; then
        echo "### Enabling service ${SERVICE_NAME}"
        do_exec sudo systemctl enable ${SERVICE_NAME}
    fi
    sudo systemctl is-active --quiet ${SERVICE_NAME}
    if [ "$?" -ne "0" ]; then
        echo "### Starting service ${SERVICE_NAME}"
        do_exec sudo systemctl start ${SERVICE_NAME}
    fi
}

grep -i overlayroot /etc/fstab &>/dev/null
if [ "$?" -eq "0" ]; then
    echo "ERROR: Overlay read-only filesystem is active"
    echo "       Please execute"
    echo "       sudo raspi-config nonint do_overlayfs 1"
    echo "       then reboot and try again"
    exit 1
fi

read -p "Enter MQTT Broker host/ip: " MQTT_BROKER

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
export LANG=en_GB.UTF-8
export LC_ALL=en_GB.UTF-8
export LANGUAGE=en_GB.UTF-8

echo "### Updating system and install needed dependencies"
do_exec sudo apt update
do_exec sudo apt full-upgrade -y
do_exec sudo apt install mc git jq build-essential mosquitto-clients -y

if [ -f /var/lib/man-db/auto-update ]; then
    echo "### Disable man-db auto-update"
    do_exec sudo rm /var/lib/man-db/auto-update
fi

if [ ! -f ${HOME}/.ssh/id_rsa ]; then
    echo "### Creating user keypair"
    yes '' | ssh-keygen -t rsa -N '' > /dev/null
fi

enable_service dphys-swapfile.service
echo "### Temporary bigger Swap to compile tesla-control with GoLang"
do_exec sudo dphys-swapfile swapoff
sudo tee /etc/dphys-swapfile > /dev/null <<EOT
CONF_SWAPSIZE=2048
EOT
do_exec sudo dphys-swapfile setup
do_exec sudo dphys-swapfile swapon

if [ -d "$HOME/.local/share/go" ]; then
    echo "### Uninstalling old GoLang"
    do_exec sudo rm -rf $HOME/.local/share/go
fi

echo "### Installing GoLang ${GO_VERSION}"
cd $HOME
do_exec wget https://dl.google.com/go/go${GO_VERSION}.linux-${ARCH}.tar.gz
do_exec mkdir -p $HOME/.local/share
do_exec tar -C $HOME/.local/share -xzf go${GO_VERSION}.linux-${ARCH}.tar.gz
do_exec rm -f go${GO_VERSION}.linux-${ARCH}.tar.gz

grep -i -q bin/tesla ${HOME}/.bashrc
if [ "$?" -ne "0" ]; then
    echo >> "${HOME}/.bashrc"
    echo 'export PATH=${HOME}/bin/tesla:$PATH' >> "${HOME}/.bashrc"
    source ${HOME}/.bashrc
fi
export GOPATH=${HOME}/.local/share/go
export PATH=${HOME}/.local/share/go/bin:${HOME}/bin/tesla:$PATH

if [ -d "${GIT_REPO_DIR}" ]; then
    echo "### Uninstalling ${GIT_REPO_DIR}"
    sudo rm -rf ${GIT_REPO_DIR}
fi
echo "### Checkout Tesla vehicle-command project from GitHub"
do_exec mkdir -p ${GIT_REPO_DIR}
cd ${GIT_REPO_DIR}
do_exec git clone https://github.com/teslamotors/vehicle-command.git

echo "### Compiling tesla-control"
cd ${GIT_REPO_DIR}/vehicle-command/cmd/tesla-control
do_exec go get
do_exec go build
do_exec mkdir -p ${TESLA_BIN_DIR}
do_exec cp tesla-control ${TESLA_BIN_DIR}
cd ${TESLA_BIN_DIR}
do_exec rm -rf ${GIT_REPO_DIR}

echo "### Uninstalling GoLang"
do_exec sudo rm -rf $HOME/.local/share/go

echo "### Downloading MQTT wrapper script"
curl -o ${TESLA_BIN_DIR}/tesla-mqtt.sh https://raw.githubusercontent.com/gry79/rip-zero-2w-tesla-ble/main/tesla-mqtt.sh
do_exec chmod 0755 ${TESLA_BIN_DIR}/tesla-mqtt.sh

tee ${TESLA_BIN_DIR}/tesla-mqtt.properties > /dev/null <<EOT
MQTT_BROKER=${MQTT_BROKER}
EOT
do_exec chmod 0644 ${TESLA_BIN_DIR}/tesla-mqtt.properties

echo "### Allowing tesla-control binary to access Bluetooth"
do_exec sudo setcap 'cap_net_admin=eip' "${TESLA_BIN_DIR}/tesla-control"

disable_service dphys-swapfile.service
disable_service apt-daily.timer
disable_service apt-daily-upgrade.timer
disable_service bluetooth.service
disable_service hciuart.service
disable_service polkit.service
disable_service avahi-daemon.socket
disable_service avahi-daemon.service

echo "### Removing avahi-daemon"
do_exec sudo apt remove --purge avahi-daemon -y
do_exec sudo rm -rf /run/avahi-daemon

echo "### Removing modemmanager"
do_exec sudo apt remove --purge modemmanager -y

echo "### Removing bluez"
do_exec sudo apt remove --purge bluez -y

echo "### Removing triggerhappy"
do_exec sudo apt remove --purge triggerhappy -y

echo "### Setting minimalistic journald config"
sudo tee /etc/systemd/journald.conf > /dev/null <<EOT
[Journal]
Storage=volatile
RuntimeMaxUse=4M
EOT

echo "### Creating systemd unit file for MQTT wrapper script"
sudo tee /lib/systemd/system/tesla-mqtt.service > /dev/null <<EOT
[Unit]
Description=Accepts command from MQTT to send to Tesla vehicle via BLE
Wants=network-online.target
After=network.target network-online.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=${HOME}
ExecStart=${TESLA_BIN_DIR}/tesla-mqtt.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT

echo "### Installing welcome script on logon"
sudo curl -o /etc/profile.d/xinfo.sh https://raw.githubusercontent.com/gry79/rip-zero-2w-tesla-ble/main/xinfo.sh
do_exec sudo chmod 0755 /etc/profile.d/xinfo.sh

echo "### Setting up some housekeeping cron jobs to free some valuable space"
tee /tmp/c1 > /dev/null <<EOT
0 0 * * * sudo journalctl --vacuum-time=1s
0 0 * * * sudo rm -f /media/root-rw/overlay/var/backups/*.gz
0 0 * * * history -c && history -w
0 0 * * * sudo apt clean
EOT
do_exec crontab /tmp/c1
do_exec rm -f /tmp/c1

enable_service tesla-mqtt.service

echo "### Autoremove unneeded dependencies"
do_exec sudo apt autoremove --purge -y

echo "### Activating overlay filesystem to make SD card read-only to prevent failure"
do_exec sudo raspi-config nonint do_overlayfs 0

echo "### Doing some housekeeing now"
do_exec sudo journalctl --vacuum-time=1s
do_exec sudo rm -f /var/backups/*.gz
do_exec sudo apt clean
do_exec history -c && history -w

echo "### SUCCESS all done, press ENTER to reboot"
read
sudo reboot
