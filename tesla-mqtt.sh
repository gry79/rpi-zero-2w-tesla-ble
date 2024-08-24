#!/usr/bin/env bash

trap ctrl_c INT

TESLA_BIN_DIR=/home/pi/bin/tesla

source ${TESLA_BIN_DIR}/tesla-mqtt.properties

if [ -z "${TOPIC_ID}" ]; then
    MAIN_TOPIC="tesla/command"
else
    MAIN_TOPIC="tesla/command/${TOPIC_ID}"
fi

function ctrl_c() {
    echo "Exiting!"
    exit 0
}

echo "Tesla VIN   : ${TESLA_VIN}"
echo "MQTT Breoker: ${MQTT_BROKER}"
echo "Topic       : ${MAIN_TOPIC}"

mosquitto_pub -h "${MQTT_BROKER}" -t "${MAIN_TOPIC}/info" -m "{ \"ip\": \"$(ifconfig wlan0 2>/dev/null | grep "inet " | awk '{print $2}')\", \"hostname\": \"$(hostname -f)\", \"model\":\"$(tr -d '\0' </proc/device-tree/model)\" }"
if [ "$?" -ne "0" ]; then
    echo "ERROR sending message to MQTT broker, exiting"
    sleep 5
    exit 1
fi

while true  # Keep an infinite loop to reconnect when connection lost/broker unavailable
do
    mosquitto_sub -h "${MQTT_BROKER}" -t "${MAIN_TOPIC}" | while read -r PAYLOAD
    do
        # Here is the callback to execute whenever you receive a message:
        echo "Tesla command: ${PAYLOAD}"
        if [ "${PAYLOAD}" = "add-key-request" ]; then
            RESPONSE=$(${TESLA_BIN_DIR}/tesla-control -vin ${TESLA_VIN} -ble add-key-request ${TESLA_BIN_DIR}/public.pem owner cloud_key 2>&1)
            RES=$?
        else
            RESPONSE=$(${TESLA_BIN_DIR}/tesla-control -vin ${TESLA_VIN} -ble -key-name private.pem -key-file ${TESLA_BIN_DIR}/private.pem ${PAYLOAD} 2>&1)
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
            STATUS="OK"
        else
            STATUS="ERROR"
        fi
        echo "${STATUS} command: ${PAYLOAD}"
        mosquitto_pub -h "${MQTT_BROKER}" -t "${MAIN_TOPIC}/response" -m "{ \"status\": \"${STATUS}\", \"response\": ${RESPONSE} }"
    done
done
