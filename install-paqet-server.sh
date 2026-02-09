#!/bin/bash

# Script version
VERSION="v1.0.0-alpha.15"

# Colored output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display messages
function echo_green {
    echo -e "${GREEN}$1${NC}"
}

function echo_red {
    echo -e "${RED}$1${NC}"
}

# Discover network configuration
function discover_network {
    echo_green "Discovering network configuration..."
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    echo_green "Detected IP Address: $IP_ADDRESS"
}

# Generate secret keys
function generate_keys {
    echo_green "Generating secret keys..."
    SECRET_KEY=$(openssl rand -base64 32)
    echo_green "Secret Key: $SECRET_KEY"
}

# Configure iptables
function configure_iptables {
    echo_green "Configuring iptables..."
    iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
    iptables -A INPUT -j DROP
    echo_green "Iptables configured."
}

# Create systemd service
function create_service {
    echo_green "Creating systemd service..."
    cat <<EOF | sudo tee /etc/systemd/system/paqet.service
[Unit]
Description=Paqet Service
After=network.target

[Service]
ExecStart=/usr/local/bin/your-executable
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl enable paqet.service
    echo_green "Systemd service created."
}

# Summary
function summary {
    echo_green "Installation Summary:"
    echo_green "Version: $VERSION"
    echo_green "IP Address: $IP_ADDRESS"
    echo_green "Secret Key: $SECRET_KEY"
}

# Main script execution
discover_network
generate_keys
configure_iptables
create_service
summary
