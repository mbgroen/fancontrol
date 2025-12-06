# # Script / service to dynamicly control fan speed of Dell PowerEdge servers
IPMI fan speed control utility (Tested on Dell PowerEdge T430)

This script makes use of the ipmitool -I open option and not the -I lan or lanplus options

# 1.  Step 1 - Prerequisites

Before starting, ensure your operating system has access to the necessary tools and kernel modules.

### A. System Requirements

*   **Operating System:** Debian, Ubuntu or OpenMediaVault running  on a Dell PE T430 server.
*   **Privileges:** Root access or `sudo` privileges.

### B. Install Dependencies and Load Modules

Open a terminal on the server and run the following commands to install `ipmitool`, the required kernel modules, and the basic calculator utility (`bc`) used by the script:

```bash
# Update package lists
sudo apt update

# Install required packages
sudo apt install ipmitool openipmi bc

# Load the necessary kernel modules (these usually load automatically on boot)
sudo modprobe ipmi_si
sudo modprobe ipmi_devintf
```


# 2. Step 2 - The Fan Control Script

The script monitors average CPU temperature and adjusts the fans dynamically.

### A. Create the Directory

Create the directory where the script will live:

```bash
sudo mkdir -p /opt/dell/fancontrol
````

### B. Create and Edit the Script File

Use `nano` (or another text editor) to create the script file:

```bash
sudo nano /opt/dell/fancontrol/fanctl.sh
```

### C. Paste the Script Code

Paste the local script code into the `nano` editor. (This version uses the ipmitool `-I open` for local installation and not  `-I lanplus` for remote network installion configurations):

```
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
LOG_FILE="/var/log/fanctrl.log"

# Danger Zone Temperature Threshold (in Celsius)
TEMP_MAX=90

# Init Current Fan Speed
current_fan_speed=""

# Logging
log() {
    level=$1
    message=$2
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
```

### D. Make the Script Executable

```bash
sudo chmod +x /opt/dell/fancontrol/fanctl.sh
```

# 3. Create the Systemd Service

This allows the script to run in the background and start automatically when the server boots.

### A. Create the Service File

```bash
sudo nano /etc/systemd/system/fancontrol.service
````

### B. Paste the Service Configuration

```
[Unit]
Description=Local Dell PowerEdge Fan Control Script
After=network-online.target

[Service]
Type=simple
ExecStart=/opt/dell/fancontrol/fanctl.sh
# Use the script's built-in 'trap' function to return control to iDRAC on stop/kill
Restart=on-failure

[Install]
WantedBy=multi-user.target
```


# 4. Enable and Start the Service

Final steps to activate the service configuration:

```bash
# Reload the systemd manager to recognize the new service file
sudo systemctl daemon-reload

# Enable the service to start automatically at boot
sudo systemctl enable fancontrol.service

# Start the service immediately
sudo systemctl start fancontrol.service
````


# 5. Verify Operation

You can check if the script is running correctly and view its output using the `journalctl` command:

```bash
sudo systemctl status fancontrol.service

# View live logs to see temperature readings:
sudo journalctl -u fancontrol.service -f
````
