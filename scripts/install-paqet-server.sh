#!/bin/bash

# paqet Server Installer Script
# This script automates the installation and configuration of paqet server
# Usage: bash install-paqet-server.sh (will use sudo when needed)

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Version
PAQET_VERSION="v1.0.0-alpha.15"
PAQET_DOWNLOAD_URL="https://github.com/hanselime/paqet/releases/download/${PAQET_VERSION}/paqet-linux-amd64-${PAQET_VERSION}.tar.gz"

# Detect if running as root
if [ "$EUID" -eq 0 ]; then
    IS_ROOT=true
    SUDO_CMD=""
    CURRENT_USER="root"
else
    IS_ROOT=false
    SUDO_CMD="sudo"
    CURRENT_USER="$USER"
fi

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "\n${GREEN}=====================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}=====================================${NC}\n"
}

# Check if sudo is available for non-root users
if [ "$IS_ROOT" = false ]; then
    if ! command -v sudo &> /dev/null; then
        print_error "sudo is not installed. Please install sudo or run as root."
        exit 1
    fi
    print_warning "Running as non-root user: ${CURRENT_USER}"
    print_info "Commands requiring privileges will use sudo"
else
    print_info "Running as root user"
fi

print_header "paqet Server Installation"

# Step 1: System Update
print_header "Step 1: Updating System"
print_info "Running apt update and upgrade..."
$SUDO_CMD apt update && $SUDO_CMD apt upgrade -y
print_success "System updated successfully"

# Step 2: Install Essential Packages
print_header "Step 2: Installing Essential Packages"
print_info "Installing curl, wget, git, nano, vim, htop, net-tools, unzip, zip, software-properties-common, ufw..."
$SUDO_CMD apt install curl wget git nano vim htop net-tools unzip zip software-properties-common ufw -y
print_success "Essential packages installed (including UFW)"

# Step 3: Prompt for Firewall Port Configuration
print_header "Step 3: Firewall Port Configuration"

# Check if UFW is installed
if command -v ufw &> /dev/null; then
    print_info "UFW detected on system"
    print_info "Which port would you like to allow through the firewall?"
    print_info "Common choices: 443 (HTTPS), 80 (HTTP), 8080, or custom"
    read -p "Enter port to allow through UFW (press Enter to skip): " UFW_PORT

    if [ -n "$UFW_PORT" ]; then
        print_info "Allowing port ${UFW_PORT}/tcp through UFW..."
        $SUDO_CMD ufw allow ${UFW_PORT}/tcp
        print_success "Firewall configured to allow port ${UFW_PORT}"
    else
        print_warning "Skipping UFW configuration"
    fi
else
    print_warning "UFW is not installed, skipping firewall configuration"
fi

# Step 4: Download and Install paqet
print_header "Step 4: Downloading and Installing paqet"
print_info "Downloading paqet ${PAQET_VERSION}..."
cd /tmp
rm -rf paqet-install
mkdir -p paqet-install
cd paqet-install
wget ${PAQET_DOWNLOAD_URL}
tar -xvf paqet-linux-amd64-${PAQET_VERSION}.tar.gz
$SUDO_CMD mv paqet_linux_amd64 /usr/local/bin/paqet
$SUDO_CMD chmod +x /usr/local/bin/paqet
print_success "paqet binary installed to /usr/local/bin/paqet"

# Step 5: Install Dependencies
print_header "Step 5: Installing paqet Dependencies"
print_info "Installing libpcap-dev and iptables-persistent..."
$SUDO_CMD apt install libpcap-dev iptables-persistent -y
$SUDO_CMD ln -sf /usr/lib/x86_64-linux-gnu/libpcap.so /usr/lib/x86_64-linux-gnu/libpcap.so.0.8
$SUDO_CMD ldconfig
print_success "Dependencies installed and configured"

# Step 6: Test paqet Installation
print_header "Step 6: Testing paqet Installation"
paqet --help
print_success "paqet is working correctly"

# Step 7: Generate Secret Key
print_header "Step 7: Generating Secret Key"
SECRET_KEY=$(paqet secret | tail -n 1)
print_success "Secret key generated: ${GREEN}${SECRET_KEY}${NC}"
print_warning "IMPORTANT: Save this key! You'll need it for client configuration."

if [ "$IS_ROOT" = true ]; then
    echo "${SECRET_KEY}" > /root/paqet-secret-key.txt
    print_info "Secret key also saved to: /root/paqet-secret-key.txt"
else
    echo "${SECRET_KEY}" > ~/paqet-secret-key.txt
    print_info "Secret key also saved to: ~/paqet-secret-key.txt"
fi

# Step 8: Network Configuration Discovery
print_header "Step 8: Discovering Network Configuration"

# Get default route and interface
print_info "Finding default gateway..."
DEFAULT_ROUTE=$(ip r | grep default)
echo "$DEFAULT_ROUTE"
GATEWAY_IP=$(echo "$DEFAULT_ROUTE" | awk '{print $3}')
INTERFACE=$(echo "$DEFAULT_ROUTE" | awk '{print $5}')

print_info "Default Gateway IP: ${GREEN}${GATEWAY_IP}${NC}"
print_info "Network Interface: ${GREEN}${INTERFACE}${NC}"

# Get Gateway MAC Address
print_info "Pinging gateway to populate ARP cache..."
ping -c 3 ${GATEWAY_IP}
sleep 1
GATEWAY_MAC=$(arp -n ${GATEWAY_IP} | grep ${GATEWAY_IP} | awk '{print $3}')
print_success "Gateway MAC Address: ${GREEN}${GATEWAY_MAC}${NC}"

# Get Server IP
SERVER_IP=$(ip -4 addr show ${INTERFACE} | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
print_success "Server IP Address: ${GREEN}${SERVER_IP}${NC}"

# Display interface info
print_info "Network Interface Details:"
ip link show ${INTERFACE}

# Step 9: Prompt for paqet Port Configuration
print_header "Step 9: paqet Port Configuration"
print_warning "IMPORTANT: Do NOT use standard ports like 80 or 443 for paqet server!"
print_warning "Using standard ports can cause issues with iptables rules affecting outgoing connections."
print_info "Recommended ports: 9999, 8888, or other high-numbered ports (1024-65535)"
echo ""
read -p "Enter the port for paqet server (default: 9999): " PAQET_PORT
PAQET_PORT=${PAQET_PORT:-9999}
print_info "Using port: ${PAQET_PORT}"

# Step 10: Configure iptables
print_header "Step 10: Configuring iptables Rules"
print_info "Setting up iptables rules for port ${PAQET_PORT}..."
$SUDO_CMD iptables -t raw -A PREROUTING -p tcp --dport ${PAQET_PORT} -j NOTRACK
$SUDO_CMD iptables -t raw -A OUTPUT -p tcp --sport ${PAQET_PORT} -j NOTRACK
$SUDO_CMD iptables -t mangle -A OUTPUT -p tcp --sport ${PAQET_PORT} --tcp-flags RST RST -j DROP
$SUDO_CMD netfilter-persistent save
print_success "iptables rules configured and saved"

# Step 11: Create Configuration Directory and File
print_header "Step 11: Creating Configuration"
$SUDO_CMD mkdir -p /etc/paqet

# Check if example file exists in the extracted archive
if [ -f "example/server.yaml.example" ]; then
    print_info "Using server.yaml.example from the package..."
    $SUDO_CMD cp example/server.yaml.example /etc/paqet/server.yaml
    
    # Update the configuration file with discovered values
    $SUDO_CMD sed -i "s|interface:.*|interface: \"${INTERFACE}\"|g" /etc/paqet/server.yaml
    $SUDO_CMD sed -i "s|addr: \":.*\"|addr: \":${PAQET_PORT}\"|g" /etc/paqet/server.yaml
    $SUDO_CMD sed -i "s|addr: \".*:9999\"|addr: \"${SERVER_IP}:${PAQET_PORT}\"|g" /etc/paqet/server.yaml
    $SUDO_CMD sed -i "s|router_mac:.*|router_mac: \"${GATEWAY_MAC}\"|g" /etc/paqet/server.yaml
    $SUDO_CMD sed -i "s|key:.*|key: \"${SECRET_KEY}\"|g" /etc/paqet/server.yaml
    
    print_success "Configuration file created from example at /etc/paqet/server.yaml"
else
    print_warning "Example file not found, creating configuration from scratch..."
    
    # Fallback: Create server configuration manually
    $SUDO_CMD tee /etc/paqet/server.yaml > /dev/null << EOF
# paqet Server Configuration
# Auto-generated by installation script

role: "server"

# Logging configuration
log:
  level: "info"

# Server listen configuration
listen:
  addr: ":${PAQET_PORT}"

# Network interface settings
network:
  interface: "${INTERFACE}"
  ipv4:
    addr: "${SERVER_IP}:${PAQET_PORT}"
    router_mac: "${GATEWAY_MAC}"

# Transport protocol configuration
transport:
  protocol: "kcp"
  conn: 1
  
  kcp:
    mode: "fast"
    key: "${SECRET_KEY}"
EOF
    print_success "Configuration file created at /etc/paqet/server.yaml"
fi

print_info "You can edit the configuration with: ${SUDO_CMD} nano /etc/paqet/server.yaml"

# Step 12: Create systemd Service
print_header "Step 12: Creating systemd Service"

if [ "$IS_ROOT" = true ]; then
    # Root user service (simpler, runs as root)
    $SUDO_CMD tee /etc/systemd/system/paqet.service > /dev/null << EOF
[Unit]
Description=paqet Server
After=network.target

[Service]
ExecStart=/usr/local/bin/paqet run -c /etc/paqet/server.yaml
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    print_info "Service created to run as root"
else
    # Non-root user service (with capabilities)
    $SUDO_CMD tee /etc/systemd/system/paqet.service > /dev/null << EOF
[Unit]
Description=paqet Server
After=network.target

[Service]
User=${CURRENT_USER}
ExecStart=/usr/local/bin/paqet run -c /etc/paqet/server.yaml
Restart=always
RestartSec=2

AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    print_info "Service created to run as user: ${CURRENT_USER}"
    print_info "Service configured with necessary network capabilities"
fi

print_success "Systemd service file created"

# Step 13: Enable and Start Service
print_header "Step 13: Starting paqet Service"
$SUDO_CMD systemctl daemon-reload
$SUDO_CMD systemctl enable paqet
$SUDO_CMD systemctl start paqet
sleep 2
$SUDO_CMD systemctl status paqet --no-pager

print_success "paqet service started and enabled"

# Cleanup
cd /tmp
rm -rf paqet-install

# Final Summary
print_header "Installation Complete!"
echo -e "${GREEN}Summary of Configuration:${NC}"
echo -e "  Running as:         ${GREEN}${CURRENT_USER}${NC}"
echo -e "  Server IP:          ${GREEN}${SERVER_IP}${NC}"
echo -e "  Server Port:        ${GREEN}${PAQET_PORT}${NC}"
echo -e "  Network Interface:  ${GREEN}${INTERFACE}${NC}"
echo -e "  Gateway IP:         ${GREEN}${GATEWAY_IP}${NC}"
echo -e "  Gateway MAC:        ${GREEN}${GATEWAY_MAC}${NC}"
echo -e "  Secret Key:         ${GREEN}${SECRET_KEY}${NC}"
if [ -n "$UFW_PORT" ]; then
    echo -e "  UFW Allowed Port:   ${GREEN}${UFW_PORT}${NC}"
fi
echo ""
echo -e "${YELLOW}Important Notes:${NC}"
if [ "$IS_ROOT" = true ]; then
    echo -e "  1. Secret key saved to: ${GREEN}/root/paqet-secret-key.txt${NC}"
else
    echo -e "  1. Secret key saved to: ${GREEN}~/paqet-secret-key.txt${NC}"
fi
echo -e "  2. Configuration file:  ${GREEN}/etc/paqet/server.yaml${NC}"
echo -e "  3. Service status:      ${GREEN}${SUDO_CMD} systemctl status paqet${NC}"
echo -e "  4. View logs:           ${GREEN}${SUDO_CMD} journalctl -u paqet -f${NC}"
echo ""
echo -e "${YELLOW}Client Configuration:${NC}"
echo -e "  Use these details in your client config:"
echo -e "    server:"
echo -e "      addr: \"${SERVER_IP}:${PAQET_PORT}\""
echo -e "    transport:"
echo -e "      kcp:"
echo -e "        key: \"${SECRET_KEY}\""
echo ""
echo -e "${GREEN}Installation completed successfully!${NC}"