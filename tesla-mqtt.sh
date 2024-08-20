#!/usr/bin/env bash

trap ctrl_c INT

TESLA_BIN_DIR=/home/pi/bin/tesla
TESLA_VIN=XXXXXXXXXXXXXXXXX
MQTT_BROKER=192.168.1.100

function ctrl_c() {
    echo "Exiting!"
    exit 0
}

mosquitto_pub -h "${MQTT_BROKER}" -t "tesla/command/info" -m "{ \"ip\": \"$(ifconfig wlan0 2>/dev/null | grep "inet " | awk '{print $2}')\", \"hostname\": \"$(hostname -f)\", \"model\":\"$(tr -d '\0' </proc/device-tree/model)\" }"
if [ "$?" -ne "0" ]; then
    echo "ERROR sending message to MQTT broker, exiting"
    sleep 5
    exit 1
fi

while true  # Keep an infinite loop to reconnect when connection lost/broker unavailable
do
    mosquitto_sub -h "${MQTT_BROKER}" -t "tesla/command" | while read -r payload
    do
        # Here is the callback to execute whenever you receive a message:
        echo "Tesla command: ${payload}"
        RESPONSE=$(${TESLA_BIN_DIR}/tesla-control -vin ${TESLA_VIN} -ble -key-name private.pem -key-file ${TESLA_BIN_DIR}/private.pem ${payload} 2>&1)
        RES=$?
        if [ "${#RESPONSE}" -eq "0" ]; then
            RESPONSE="\"\""
        fi
        jq -e . >/dev/null 2>&1 <<< "${RESPONSE}"
        if [ "$?" -ne "0" ]; then
            RESPONSE=\"${RESPONSE}\"
        fi
        if [ $RES -eq 0 ]; then
            echo "OK command: ${payload}"
            mosquitto_pub -h "${MQTT_BROKER}" -t "tesla/command/response" -m "{ \"status\": \"OK\", \"response\": ${RESPONSE} }"
        else
            echo "ERROR command: ${payload}"
            mosquitto_pub -h "${MQTT_BROKER}" -t "tesla/command/response" -m "{ \"status\": \"ERROR\", \"response\": ${RESPONSE} }"
        fi
    done
done
