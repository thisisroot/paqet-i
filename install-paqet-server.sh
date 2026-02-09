#!/bin/bash

# Server Installer Script for PAQET

# Check for UFW
if command -v ufw > /dev/null; then
    echo "UFW is installed. Configuring UFW."
    ufw allow 80/tcp
    ufw allow 443/tcp
else
    echo "UFW not installed. Please install UFW for firewall configuration."
fi

# Use example YAML files from the tar.gz package
# Assuming the package is extracted at /opt/paqet
YAML_DIR="/opt/paqet/examples"

# Function to check if the script is run as root
function check_root {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root or with sudo"
        exit 1
    fi
}

# Discover network configuration automatically
function discover_network {
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    echo "Detected IP Address: $IP_ADDRESS"
}

# Create systemd service configuration
function create_service {
    SERVICE_FILE="/etc/systemd/system/paqet.service"
    echo "[Unit]\nDescription=PAQET Service\n\n[Service]\nExecStart=/usr/bin/python3 /opt/paqet/server.py\nRestart=always\n\n[Install]\nWantedBy=multi-user.target" > $SERVICE_FILE

    echo "Systemd service file created at $SERVICE_FILE"
}

# Main installation logic
check_root
discover_network
create_service

echo "PAQET server installation script executed successfully."