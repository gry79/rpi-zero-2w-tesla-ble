#!/usr/bin/env bash

trap ctrl_c INT
trap on_exit EXIT

TESLA_BIN_DIR=/home/pi/bin/tesla
MEIDA_ROOT=/media/root-ro

source ${TESLA_BIN_DIR}/tesla-mqtt.properties

function ctrl_c () {
    echo "Exiting!"
    exit 0
}

function on_exit () {
    mosquitto_pub -h "${MQTT_BROKER}" -t "tesla/info" -m "{ \
    \"online\": \"false\", \
    \"ip\": \"$(ifconfig 2>/dev/null | grep "inet.*broadcast" | awk '{print $2}')\", \
    \"hostname\": \"$(hostname -f)\", \"model\":\"$(tr -d '\0' </proc/device-tree/model)\", \
    \"uptime\": \"$(uptime -p)\" \
    }"
}

echo "----------------------------"
echo "-- Tesla Command BLE MQTT --"
echo "----------------------------"
echo

echo "MQTT Broker: ${MQTT_BROKER}"

VC=$(vcgencmd get_throttled)
UNDERVOLTAGE_DETECTED=$([[ "$(($((16#${VC:12})) & 1))" -eq "0" ]] && echo "no" || echo "yes")
ARM_FREQUENCY_CAPPED=$([[ "$(($((16#${VC:12})) & 2))" -eq "0" ]] && echo "no" || echo "yes")
CURRENTLY_THROTTLED=$([[ "$(($((16#${VC:12})) & 4))" -eq "0" ]] && echo "no" || echo "yes")
SOFT_TEMPERATURE_LIMIT_ACTIVE=$([[ "$(($((16#${VC:12})) & 8))" -eq "0" ]] && echo "no" || echo "yes")
UNDERVOLTAGE_OCCURED=$([[ "$(($((16#${VC:12})) & 65536))" -eq "0" ]] && echo "no" || echo "yes")
ARM_FREQUENCY_CAPPED_OCCURED=$([[ "$(($((16#${VC:12})) & 131072))" -eq "0" ]] && echo "no" || echo "yes")
THROTTLING_OCCURED=$([[ "$(($((16#${VC:12})) & 262144))" -eq "0" ]] && echo "no" || echo "yes")
SOFT_TEMPERATURE_LIMIT_OCCURED=$([[ "$(($((16#${VC:12})) & 524288))" -eq "0" ]] && echo "no" || echo "yes")

mosquitto_pub -h "${MQTT_BROKER}" -t "tesla/info" -m "{ \
    \"online\": \"true\", \
    \"ip\": \"$(ifconfig 2>/dev/null | grep "inet.*broadcast" | awk '{print $2}')\", \
    \"hostname\": \"$(hostname -f)\", \"model\":\"$(tr -d '\0' </proc/device-tree/model)\", \
    \"undervoltage_detected\": \"${UNDERVOLTAGE_DETECTED}\", \
    \"arm_frequency_capped\": \"${ARM_FREQUENCY_CAPPED}\", \
    \"currently_throttled\": \"${CURRENTLY_THROTTLED}\", \
    \"soft_temperature_limit_active\": \"${SOFT_TEMPERATURE_LIMIT_ACTIVE}\", \
    \"undervoltage_occured\": \"${UNDERVOLTAGE_OCCURED}\", \
    \"arm_frequency_capped_occured\": \"${ARM_FREQUENCY_CAPPED_OCCURED}\", \
    \"throttling_occured\": \"${THROTTLING_OCCURED}\", \
    \"soft_temperature_limit_occured\": \"${SOFT_TEMPERATURE_LIMIT_OCCURED}\", \
    \"uptime\": \"$(uptime -p)\" \
    }"
if [ "$?" -ne "0" ]; then
    echo "ERROR sending message to MQTT broker, skipping"
fi

while true; do
    mosquitto_sub -h "${MQTT_BROKER}" -v -t "tesla/+/command" | while read -r -a MESSAGE; do
        TOPIC=${MESSAGE[0]}
        PAYLOAD=${MESSAGE[1]}
        IFS='/' read -r -a SPLIT <<< "${TOPIC}"
        TESLA_VIN=${SPLIT[1]}
        echo "Topic    : ${TOPIC}"
        echo "Payload  : ${PAYLOAD}"
        echo "Tesla VIN: ${TESLA_VIN}"
        if [ "${#TESLA_VIN}" -ne "17" ]; then
            STATUS="ERROR"
            RESPONSE="Invalid VIN ${TESLA_VIN}, must be 17 characters long"
            echo "${STATUS}: ${RESPONSE}"
        else
            if [ "${PAYLOAD}" = "add-key-request" ]; then
                KEY_PATH=${TESLA_BIN_DIR}/${TESLA_VIN}
                grep -i overlayroot /etc/fstab &>/dev/null
                if [ "$?" -eq "0" ]; then
                    KEY_PATH=${MEIDA_ROOT}${TESLA_BIN_DIR}/${TESLA_VIN}
                    sudo mount -o remount,rw ${MEIDA_ROOT}
                fi
                if [ ! -f "${KEY_PATH}.private.pem" ]; then
                    echo "Generating private key ${TESLA_VIN}.private.pem"
                    openssl ecparam -genkey -name prime256v1 -noout > "${KEY_PATH}.private.pem"
                    chmod 0640 "${KEY_PATH}.private.pem"
                fi
                if [ ! -f "${KEY_PATH}.public.pem" ]; then
                    echo "Generating public key ${TESLA_VIN}.public.pem"
                    openssl ec -in "${KEY_PATH}.private.pem" -pubout > "${KEY_PATH}.public.pem"
                fi
                grep -i overlayroot /etc/fstab &>/dev/null
                if [ "$?" -eq "0" ]; then
                    sudo mount -o remount,ro ${MEIDA_ROOT}
                fi
                RESPONSE=$(${TESLA_BIN_DIR}/tesla-control -vin ${TESLA_VIN} -ble add-key-request \
                    "${TESLA_BIN_DIR}/${TESLA_VIN}.public.pem" owner cloud_key 2>&1)
                RES=$?
            else
                if [ -f "${TESLA_BIN_DIR}/${TESLA_VIN}.private.pem" ]; then
                    RESPONSE=$(${TESLA_BIN_DIR}/tesla-control -vin ${TESLA_VIN} -ble \
                        -key-file "${TESLA_BIN_DIR}/${TESLA_VIN}.private.pem" ${PAYLOAD} 2>&1)
                    RES=$?
                    if [ $RES -eq 0 ]; then
                        STATUS="OK"
                    else
                        STATUS="ERROR"
                    fi
                else
                    STATUS="ERROR"
                    RESPONSE="No private key found for VIN ${TESLA_VIN}, please execute 'add-key-request' first"
                fi
            fi
        fi
        echo "${STATUS} command: ${PAYLOAD}"
        if [ "${#RESPONSE}" -eq "0" ]; then
            RESPONSE="\"\""
        fi
        jq -e . >/dev/null 2>&1 <<< "${RESPONSE}"
        if [ "$?" -ne "0" ]; then
            RESPONSE=\"${RESPONSE}\"
        fi
        mosquitto_pub -h "${MQTT_BROKER}" -t "tesla/${TESLA_VIN}/response" -m "{ \
            \"status\": \"${STATUS}\", \"vin\": \"${TESLA_VIN}\", \
            \"uptime\": \"$(uptime -p)\", \"response\": ${RESPONSE} \
            }"
    done
    echo "ERROR: Connection to broker lost or connection interrupted, retry in 5 seconds"
    sleep 5
done
