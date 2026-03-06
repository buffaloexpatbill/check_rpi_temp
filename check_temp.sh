#!/bin/bash

VERSION="Version 1.3 (Raspberry Pi aware)"
AUTHOR="(c) 2011 Jack-Benny Persson, (c) 2020 Onkobu Tanaake, Pi adaptation"
# Adapted for use on Raspberry Pi by Bill Mullen 2024

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

shopt -s extglob

#### Detect Raspberry Pi ####

IS_RPI=0

if [[ -f /proc/device-tree/model ]]; then
    if grep -qi "raspberry pi" /proc/device-tree/model; then
        IS_RPI=1
    fi
fi

#### Locate sensors binary if available ####

SENSORPROG=$(command -v sensors 2>/dev/null)

#### Functions ####

print_version() {
    echo "$0 - $VERSION"
}

print_help() {
    print_version
    echo "$AUTHOR"
    echo "Monitor temperature (Raspberry Pi aware)"
cat <<EOT

Options:
-h, --help
   Print detailed help
-V, --version
   Print version
-v, --verbose
   Verbose output

-s, --sensor <WORD>
   Sensor to monitor (CPU, GPU, or lm-sensors name)

-w, --warning <INTEGER>
   Warning threshold

-c, --critical <INTEGER>
   Critical threshold

Examples:
./check_temp.sh -w 65 -c 75 --sensor CPU
./check_temp.sh -w 70 -c 85 --sensor GPU
./check_temp.sh -w 60 -c 75 --sensor temp1

EOT
}

get_pi_cpu_temp() {
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp
    fi
}

get_pi_gpu_temp() {
    if command -v vcgencmd >/dev/null 2>&1; then
        vcgencmd measure_temp | awk -F"[=']" '{print $2}'
    fi
}

get_lmsensors_temp() {

    if [[ -z "$SENSORPROG" ]]; then
        return
    fi

    WHOLE_TEMP=$(${SENSORPROG} | grep "$sensor" | head -n1 | \
        grep -o "+[0-9]\+\(\.[0-9]\+\)\?[^ \t,()]*" | head -n1)

    echo "$WHOLE_TEMP" | grep -o "[0-9]\+\(\.[0-9]\+\)\?"
}

#### MAIN ####

thresh_warn=
thresh_crit=
sensor="CPU"

while [[ -n "$1" ]]; do
   case "$1" in

       -h | --help)
           print_help
           exit $STATE_OK
           ;;

       -V | --version)
           print_version
           exit $STATE_OK
           ;;

       -v | --verbose)
           : $(( verbosity++ ))
           shift
           ;;

       -w | --warning)
           thresh_warn=$2
           shift 2
           ;;

       -c | --critical)
           thresh_crit=$2
           shift 2
           ;;

       -s | --sensor)
           sensor=$2
           shift 2
           ;;

       *)
           echo "Invalid option $1"
           print_help
           exit $STATE_UNKNOWN
           ;;
   esac
done

if [[ -z "$thresh_warn" || -z "$thresh_crit" ]]; then
    echo "Thresholds not set"
    exit $STATE_UNKNOWN
fi

#### Get temperature ####

case "$sensor" in

    cpu|CPU)
        if [[ $IS_RPI -eq 1 ]]; then
            TEMP=$(get_pi_cpu_temp)
        else
            TEMP=$(get_lmsensors_temp)
        fi
        DISPLAY="CPU"
        ;;

    gpu|GPU)
        if [[ $IS_RPI -eq 1 ]]; then
            TEMP=$(get_pi_gpu_temp)
        else
            TEMP=$(get_lmsensors_temp)
        fi
        DISPLAY="GPU"
        ;;

    *)
        TEMP=$(get_lmsensors_temp)
        DISPLAY="$sensor"
        ;;
esac

#### Validate ####

if ! [[ "$TEMP" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "TEMPERATURE UNKNOWN - No data for sensor $sensor"
    exit $STATE_UNKNOWN
fi

TEMP_INT=$(echo "$TEMP" | cut -d. -f1)

if [[ "$verbosity" -ge 1 ]]; then
    echo "Debug:"
    echo "  Raspberry Pi detected: $IS_RPI"
    echo "  Sensor: $sensor"
    echo "  Temperature: $TEMP"
fi

#### Threshold checks ####

if (( $(echo "$TEMP > $thresh_crit" | bc -l) )); then
    echo "TEMPERATURE CRITICAL - $DISPLAY temperature $TEMP°C | ${DISPLAY}=${TEMP};${thresh_warn};${thresh_crit}"
    exit $STATE_CRITICAL

elif (( $(echo "$TEMP > $thresh_warn" | bc -l) )); then
    echo "TEMPERATURE WARNING - $DISPLAY temperature $TEMP°C | ${DISPLAY}=${TEMP};${thresh_warn};${thresh_crit}"
    exit $STATE_WARNING

else
    echo "TEMPERATURE OK - $DISPLAY temperature $TEMP°C | ${DISPLAY}=${TEMP};${thresh_warn};${thresh_crit}"
    exit $STATE_OK
fi
