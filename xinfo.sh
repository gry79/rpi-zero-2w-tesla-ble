#!/usr/bin/env bash

MODEL=$(tr -d '\0' </proc/device-tree/model)

# Date & Time
DATE=`date +"%A, %e %B %Y"`

# Hostname
HOSTNAME=`hostname -f`

# System usage
LOAD1=`cat /proc/loadavg | awk '{print $1}'`    # Last minute
LOAD2=`cat /proc/loadavg | awk '{print $2}'`    # Last 5 minutes
LOAD3=`cat /proc/loadavg | awk '{print $3}'`    # Last 15 minutes

# Temperature
TEMP=`vcgencmd measure_temp | cut -c "6-9"`

# Disk usage
DISK1N=`df -h | grep '/dev/mmcblk0p2' | awk '{print $2}'`    # Overall
DISK2N=`df -h | grep '/dev/mmcblk0p2' | awk '{print $3}'`    # Used
DISK3N=`df -h | grep '/dev/mmcblk0p2' | awk '{print $4}'`    # Free

DISK1O=`df -h | grep 'overlayroot' | awk '{print $2}'`    # Overall
DISK2O=`df -h | grep 'overlayroot' | awk '{print $3}'`    # Used
DISK3O=`df -h | grep 'overlayroot' | awk '{print $4}'`    # Free

grep -i overlayroot /etc/fstab &>/dev/null
if [ "$?" -eq "0" ]; then
  DISK1=${DISK1O}
  DISK2=${DISK2O}
  DISK3=${DISK3O}
else
  DISK1=${DISK1N}
  DISK2=${DISK2N}
  DISK3=${DISK3N}
fi

# Memory
RAM1=`free -h -w | grep 'Mem' | awk '{print $2}'`    # Total
RAM2=`free -h -w | grep 'Mem' | awk '{print $3}'`    # Used
RAM3=`free -h -w | grep 'Mem' | awk '{print $4}'`    # Free
RAM4=`free -h -w | grep 'Swap' | awk '{print $3}'`   # Swap used

# Get IP of WiFi
WLAN_IP=`ifconfig wlan0 2>/dev/null | grep "inet " | awk '{print $2}'`

# Current CPU frequency
CPU_FREQ_MHZ=$(($(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq) / 1000))

echo
echo -e "\033[1;32m   .~~.   .~~.    \033[1;36m${DATE}
\033[1;32m  '. \ ' ' / .'   \033[0;37mModel       : \033[1;33m${MODEL}
\033[1;31m   .~ .~~~..~.    \033[0;37mHostname    : \033[1;33m${HOSTNAME}
\033[1;31m  : .~.'~'.~. :   \033[0;37mØ Load      : ${LOAD1} (1 Min.) | ${LOAD2} (5 Min.) | ${LOAD3} (15 Min.)
\033[1;31m ~ (   ) (   ) ~  \033[0;37mTemperature : ${TEMP} °C
\033[1;31m( : '~'.~.'~' : ) \033[0;37mCPU speed   : ${CPU_FREQ_MHZ} MHz
\033[1;31m ~ .~ (   ) ~. ~  \033[0;37mStorage     : Total: ${DISK1} | Used: ${DISK2} | Free: ${DISK3}
\033[1;31m  (  : '~' :  )   \033[0;37mRAM (MB)    : Total: ${RAM1} | Used: ${RAM2} | Free: ${RAM3} | Swap: ${RAM4}
\033[1;31m   '~ .~~~. ~'    \033[0;37mIP-Address  : \033[1;35m${WLAN_IP}\033[0;37m
\033[1;31m       '~'        \033[0;37m
\033[1;31m                  \033[0;37m
\033[m"
