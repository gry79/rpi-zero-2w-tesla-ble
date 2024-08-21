#!/usr/bin/env bash

trap ctrl_c INT

TESLA_BIN_DIR=/home/pi/bin/tesla

source ${TESLA_BIN_DIR}/tesla-mqtt.properties

function ctrl_c() {
    echo "Exiting!"
    exit 0
}

mosquitto_pub -h "${MQTT_BROKER}" -t "tesla/command/${TOPIC_ID}/info" -m "{ \"ip\": \"$(ifconfig wlan0 2>/dev/null | grep "inet " | awk '{print $2}')\", \"hostname\": \"$(hostname -f)\", \"model\":\"$(tr -d '\0' </proc/device-tree/model)\" }"
if [ "$?" -ne "0" ]; then
    echo "ERROR sending message to MQTT broker, exiting"
    sleep 5
    exit 1
fi

while true  # Keep an infinite loop to reconnect when connection lost/broker unavailable
do
    mosquitto_sub -h "${MQTT_BROKER}" -t "tesla/command/${TOPIC_ID}" | while read -r payload
    do
        # Here is the callback to execute whenever you receive a message:
        echo "Tesla command: ${payload}"
        if [ "${payload}" = "add-key-request" ]; then
            RESPONSE=$(${TESLA_BIN_DIR}/tesla-control -vin ${TESLA_VIN} -ble add-key-request ${TESLA_BIN_DIR}/public.pem owner cloud_key 2>&1)
            RES=$?
        else
            RESPONSE=$(${TESLA_BIN_DIR}/tesla-control -vin ${TESLA_VIN} -ble -key-name private.pem -key-file ${TESLA_BIN_DIR}/private.pem ${payload} 2>&1)
            RES=$?
        fi
        if [ "${#RESPONSE}" -eq "0" ]; then
            RESPONSE="\"\""
        fi
        jq -e . >/dev/null 2>&1 <<< "${RESPONSE}"
        if [ "$?" -ne "0" ]; then
            RESPONSE=\"${RESPONSE}\"
        fi
        if [ $RES -eq 0 ]; then
            echo "OK command: ${payload}"
            mosquitto_pub -h "${MQTT_BROKER}" -t "tesla/command/${TOPIC_ID}/response" -m "{ \"status\": \"OK\", \"response\": ${RESPONSE} }"
        else
            echo "ERROR command: ${payload}"
            mosquitto_pub -h "${MQTT_BROKER}" -t "tesla/command/${TOPIC_ID}/response" -m "{ \"status\": \"ERROR\", \"response\": ${RESPONSE} }"
        fi
    done
done
