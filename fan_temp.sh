#!/bin/bash

CONFIG_FILE="/boot/firmware/config.txt"
BACKUP_FILE="/boot/firmware/config.txt.bak"

# Create a backup of the config file
sudo cp "$CONFIG_FILE" "$BACKUP_FILE"
echo "Backup of config.txt created at $BACKUP_FILE"

# Prompt user for fan activation temperature
echo -n "Enter the desired fan activation temperature (in °C, e.g., 55): "
read temp_c

# Validate input (numeric check)
if ! [[ "$temp_c" =~ ^[0-9]+$ ]]; then
    echo "Error: Input must be a numeric value."
    exit 1
fi

# Convert temperature to millidegrees Celsius (e.g., 55°C -> 55000)
temp_millic=$((temp_c * 1000))

# Remove existing rpi-fan overlay settings
sudo sed -i '/dtoverlay=rpi-fan/d' "$CONFIG_FILE"

# Append new configuration
echo "dtoverlay=rpi-fan,temp=$temp_millic" | sudo tee -a "$CONFIG_FILE"

# Notify user
echo "Fan activation temperature set to ${temp_c}°C."
echo "Please reboot your Raspberry Pi to apply the changes."

# Optionally, ask user if they want to reboot now
read -p "Would you like to reboot now? (y/n): " reboot_now
if [[ "$reboot_now" =~ ^[Yy]$ ]]; then
    sudo reboot
fi