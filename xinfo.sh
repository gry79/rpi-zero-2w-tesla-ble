#!/usr/bin/env bash

MODEL=$(tr -d '\0' </proc/device-tree/model)

# Datum & Uhrzeit
DATUM=`date +"%A, %e %B %Y"`

# Hostname
HOSTNAME=`hostname -f`

# Durchschnittliche Auslasung
LOAD1=`cat /proc/loadavg | awk '{print $1}'`    # Letzte Minute
LOAD2=`cat /proc/loadavg | awk '{print $2}'`    # Letzte 5 Minuten
LOAD3=`cat /proc/loadavg | awk '{print $3}'`    # Letzte 15 Minuten

# Temperatur
TEMP=`vcgencmd measure_temp | cut -c "6-9"`

# Speicherbelegung
DISK1N=`df -h | grep '/dev/mmcblk0p2' | awk '{print $2}'`    # Gesamtspeicher
DISK2N=`df -h | grep '/dev/mmcblk0p2' | awk '{print $3}'`    # Belegt
DISK3N=`df -h | grep '/dev/mmcblk0p2' | awk '{print $4}'`    # Frei

DISK1O=`df -h | grep 'overlayroot' | awk '{print $2}'`    # Gesamtspeicher
DISK2O=`df -h | grep 'overlayroot' | awk '{print $3}'`    # Belegt
DISK3O=`df -h | grep 'overlayroot' | awk '{print $4}'`    # Frei

if [ ${#DISK1O} -gt 0 ]; then
  DISK1=${DISK1O}
  DISK2=${DISK2O}
  DISK3=${DISK3O}
else
  DISK1=${DISK1N}
  DISK2=${DISK2N}
  DISK3=${DISK3N}
fi

# Arbeitsspeicher
RAM1=`free -h -w | grep 'Mem' | awk '{print $2}'`    # Total
RAM2=`free -h -w | grep 'Mem' | awk '{print $3}'`    # Used
RAM3=`free -h -w | grep 'Mem' | awk '{print $4}'`    # Free
RAM4=`free -h -w | grep 'Swap' | awk '{print $3}'`    # Swap used

# IP-Adressen ermitteln
WLAN_IP=`ifconfig wlan0 2>/dev/null | grep "inet " | awk '{print $2}'`

echo
echo -e "\033[1;32m   .~~.   .~~.    \033[1;36m$DATUM
\033[1;32m  '. \ ' ' / .'   \033[0;37mModel       : \033[1;33m$MODEL
\033[1;31m   .~ .~~~..~.    \033[0;37mHostname    : \033[1;33m$HOSTNAME
\033[1;31m  : .~.'~'.~. :   \033[0;37mØ Load      : $LOAD1 (1 Min.) | $LOAD2 (5 Min.) | $LOAD3 (15 Min.)
\033[1;31m ~ (   ) (   ) ~  \033[0;37mTemperature : $TEMP °C
\033[1;31m( : '~'.~.'~' : ) \033[0;37mStorage     : Total: $DISK1 | Used: $DISK2 | Free: $DISK3
\033[1;31m ~ .~ (   ) ~. ~  \033[0;37mRAM (MB)    : Total: $RAM1 | Used: $RAM2 | Free: $RAM3 | Swap: $RAM4
\033[1;31m  (  : '~' :  )   \033[0;37mIP-Address  : \033[1;35m$WLAN_IP\033[0;37m
\033[1;31m   '~ .~~~. ~'    \033[0;37m
\033[1;31m       '~'        \033[0;37m
\033[1;31m                  \033[0;37m
\033[m"
