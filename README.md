# Dell PowerEdge Fan Control

This repository provides a Bash script and optional systemd service to dynamically control fan speeds on Dell PowerEdge servers using local `ipmitool` commands. Version 1.1 introduces built-in log rotation to keep `/var/log/fanctrl.log` tidy.

## Requirements
- Debian/Ubuntu/OpenMediaVault on a Dell PowerEdge server (tested on T430)
- Root or `sudo` privileges
- Packages: `ipmitool`, `openipmi`, `bc`

Install prerequisites and load kernel modules:
```bash
sudo apt update
sudo apt install ipmitool openipmi bc
sudo modprobe ipmi_si
sudo modprobe ipmi_devintf
```

## Installation
1. Copy the script to `/opt/dell/fancontrol`:
   ```bash
   sudo mkdir -p /opt/dell/fancontrol
   sudo cp fanctl.sh /opt/dell/fancontrol/
   sudo chmod +x /opt/dell/fancontrol/fanctl.sh
   ```
2. (Optional) Install the provided systemd unit:
   ```bash
   sudo cp fancontrol.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now fancontrol.service
   ```

## Configuration
Key script settings (edit inside `fanctl.sh`):
- Temperature thresholds: `TEMP_THRESHOLD_1` through `TEMP_THRESHOLD_9`
- Check interval: `CHECK_INTERVAL` (seconds)
- Log location: `LOG_FILE` (default `/var/log/fanctrl.log`)
- Log rotation: `LOG_MAX_SIZE` (bytes, default 1MB) and `LOG_BACKUP_COUNT` (default 5 backups)

Log rotation (v1.1) creates the log directory automatically, rotates when the active log exceeds `LOG_MAX_SIZE`, renames older logs as `.1`, `.2`, etc., and removes the oldest file beyond `LOG_BACKUP_COUNT`.

## Operations
- Start service: `sudo systemctl start fancontrol.service`
- Check status: `sudo systemctl status fancontrol.service`
- Follow logs: `sudo journalctl -u fancontrol.service -f`

If the script exits, it restores iDRAC automatic fan control via its built-in trap handler.
