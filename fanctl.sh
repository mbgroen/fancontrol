#!/bin/bash

# Fan Speed Thresholds
TEMP_THRESHOLD_1=50
TEMP_THRESHOLD_2=55
TEMP_THRESHOLD_3=60
TEMP_THRESHOLD_4=65
TEMP_THRESHOLD_5=70
TEMP_THRESHOLD_6=75
TEMP_THRESHOLD_7=80
TEMP_THRESHOLD_8=85
TEMP_THRESHOLD_9=90

# Time Between Checks (in seconds)
CHECK_INTERVAL=30

# Log Path
LOG_FILE="/var/log/fanctrl/fanctrl.log"
LOG_MAX_SIZE=$((1024 * 1024)) # 1MB
LOG_BACKUP_COUNT=5

# Ensure the log directory exists before writing
ensure_log_directory() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir"
    fi
}

# Danger Zone Temperature Threshold (in Celsius)
TEMP_MAX=90

# Init Current Fan Speed
current_fan_speed=""

# Log rotation helpers
get_file_size() {
    local file=$1
    if command -v stat &>/dev/null; then
        stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null
    elif [ -f "$file" ]; then
        wc -c <"$file" 2>/dev/null
    fi
}

rotate_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        return
    fi

    local size
    size=$(get_file_size "$LOG_FILE")

    if [ -n "$size" ] && [ "$size" -ge "$LOG_MAX_SIZE" ]; then
        if [ "$LOG_BACKUP_COUNT" -gt 0 ]; then
            for ((i = LOG_BACKUP_COUNT - 1; i >= 1; i--)); do
                if [ -f "${LOG_FILE}.${i}" ]; then
                    mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
                fi
            done

            mv "$LOG_FILE" "${LOG_FILE}.1"
        else
            : >"$LOG_FILE"
            return
        fi

        if [ -f "${LOG_FILE}.$((LOG_BACKUP_COUNT + 1))" ]; then
            rm -f "${LOG_FILE}.$((LOG_BACKUP_COUNT + 1))"
        fi

        : >"$LOG_FILE"
    fi
}

# Logging
log() {
    level=$1
    message=$2
    ensure_log_directory
    rotate_logs
    timestamp=$(date +"%d-%m-%Y %H:%M:%S")
    log_message="[$timestamp] [$level] $message"
    echo "$log_message"
    echo "$log_message" >>"$LOG_FILE"
}

# Check Deps
check_dependencies() {
    dependencies=("ipmitool" "bc")
    for dep in "${dependencies[@]}"; do
        if ! command -v $dep &>/dev/null; then
            log "ERROR" "Required dependency '$dep' is not installed. Exiting."
            exit 1
        fi
    done
    # Load kernel modules required for local access
    modprobe ipmi_si
    modprobe ipmi_devintf
}

# Get CPU Temps and Parse Out Inlet & Exhaust
get_cpu_temperatures() {
    # Changed from -I lanplus to -I open
    temps=$(ipmitool -I open sdr type temperature | grep -E '^\s*Temp\s+\|' | awk -F'|' '{print $5}' | awk '{p>
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to retrieve temperatures from IPMI locally. Error: $temps"
        echo ""
    else
        echo "$temps"
    fi
}

# Calculate Average CPU Temps From Both Procs
get_avg_cpu_temperature() {
    temps=$(get_cpu_temperatures)
    if [ -z "$temps" ]; then
        echo ""
    else
        echo "$temps" | awk '{sum+=$1} END {if (NR>0) print sum/NR; else print ""}' | awk '{printf "%.1f", $0}'
    fi
}

# Set The Fan Speed
set_fan_speed() {
    speed=$1
    if [ "$speed" != "$current_fan_speed" ]; then
        # Changed from -I lanplus to -I open
        output=$(ipmitool -I open raw 0x30 0x30 0x02 0xff $speed 2>&1)
        if [ $? -ne 0 ]; then
            log "ERROR" "Failed to set fan speed via local IPMI. Error: $output"
        else
            log "INFO" "Fan speed set to $speed."
            current_fan_speed=$speed
        fi
    else
        log "INFO" "Fan speed unchanged at $speed."
    fi
}

# Manual Fan Control Mode
enable_manual_fan_control() {
    # Changed from -I lanplus to -I open
    output=$(ipmitool -I open raw 0x30 0x30 0x01 0x00 2>&1)
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to enable manual fan control via local IPMI. Error: $output"
        exit 1
    else
        log "INFO" "Manual fan control enabled."
    fi
}

# Disable Fan Control Mode
disable_manual_fan_control() {
    # Changed from -I lanplus to -I open
    output=$(ipmitool -I open raw 0x30 0x30 0x01 0x01 2>&1)
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to disable manual fan control via local IPMI. Error: $output"
    else
        log "INFO" "Manual fan control disabled. Returning to automatic control."
    fi
}

# If Script Exit Or Crash, Reset To Auto Fan Control
trap 'disable_manual_fan_control; log "INFO" "Script terminated."; exit 0' SIGINT SIGTERM

# Check For Required Deps and Load local modules
check_dependencies

# Takeover Fan Control On Launch
enable_manual_fan_control

# Main Loop (rest of script is unchanged logic)
while true; do
    # Get CPU Temperatures
    cpu_temps=$(get_cpu_temperatures)
    # ... [rest of the script logic to check temps and call set_fan_speed]
    # ... 
    avg_temp=$(get_avg_cpu_temperature)

    if [ -z "$avg_temp" ]; then
        log "WARNING" "Unable to retrieve CPU temperatures. Skipping fan speed adjustment."
    else
        log "INFO" "Average CPU temperature: $avg_temp°C"

        # Check If The Temperature Exceeds The Max Threshold
        if (($(echo "$avg_temp >= $TEMP_MAX" | bc -l))); then
            log "WARNING" "Temperature reached or exceeded max threshold ($TEMP_MAX°C). Switching to automatic>
            disable_manual_fan_control
            log "INFO" "Exiting script due to max temperature reached."
            exit 1
        # Step Up Fan Speed As Temp Goes Up
        elif (($(echo "$avg_temp >= $TEMP_THRESHOLD_9" | bc -l))); then
            # ... [logic omitted for brevity, sets hex values as before]
            set_fan_speed 0x5A # 90%
        elif (($(echo "$avg_temp >= $TEMP_THRESHOLD_8" | bc -l))); then
            set_fan_speed 0x50 # 80%
        elif (($(echo "$avg_temp >= $TEMP_THRESHOLD_7" | bc -l))); then
            set_fan_speed 0x46 # 70%
        elif (($(echo "$avg_temp >= $TEMP_THRESHOLD_6" | bc -l))); then
            set_fan_speed 0x3C # 60%
        elif (($(echo "$avg_temp >= $TEMP_THRESHOLD_5" | bc -l))); then
            set_fan_speed 0x32 # 50%
        elif (($(echo "$avg_temp >= $TEMP_THRESHOLD_4" | bc -l))); then
            set_fan_speed 0x28 # 40%
        elif (($(echo "$avg_temp >= $TEMP_THRESHOLD_3" | bc -l))); then
            set_fan_speed 0x1E # 30%
        elif (($(echo "$avg_temp >= $TEMP_THRESHOLD_2" | bc -l))); then
            set_fan_speed 0x14 # 20%
        elif (($(echo "$avg_temp >= $TEMP_THRESHOLD_1" | bc -l))); then
            set_fan_speed 0xA # 10%
        else
            set_fan_speed 0x5 # 5%
        fi
    fi

# Wait A Set Time Before Rechecking
    sleep $CHECK_INTERVAL
done
