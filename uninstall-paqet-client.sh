#!/bin/bash

# paqet Client Uninstaller Script
# This script removes paqet client and all related configurations
# Usage: bash uninstall-paqet-client.sh (will use sudo when needed)

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "\n${RED}=====================================${NC}"
    echo -e "${RED}$1${NC}"
    echo -e "${RED}=====================================${NC}\n"
}

# Check if sudo is available for non-root users
if [ "$IS_ROOT" = false ]; then
    if ! command -v sudo &> /dev/null; then
        print_error "sudo is not installed. Please install sudo or run as root."
        exit 1
    fi
fi

print_header "paqet Client Uninstallation"

print_warning "This will completely remove paqet client from your system!"
print_warning "The following will be removed:"
echo "  - paqet systemd service"
echo "  - paqet binary (/usr/local/bin/paqet)"
echo "  - Configuration files (/etc/paqet/)"
echo "  - iptables rules for paqet"
echo ""
print_info "NOTE: System libraries (libpcap, etc.) will NOT be removed"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    print_info "Uninstallation cancelled."
    exit 0
fi

# Step 1: Stop and disable service
print_header "Step 1: Stopping paqet Service"
if systemctl is-active --quiet paqet; then
    print_info "Stopping paqet service..."
    $SUDO_CMD systemctl stop paqet
    print_success "Service stopped"
else
    print_info "Service is not running"
fi

if systemctl is-enabled --quiet paqet 2>/dev/null; then
    print_info "Disabling paqet service..."
    $SUDO_CMD systemctl disable paqet
    print_success "Service disabled"
else
    print_info "Service is not enabled"
fi

# Step 2: Remove systemd service file
print_header "Step 2: Removing systemd Service File"
if [ -f "/etc/systemd/system/paqet.service" ]; then
    print_info "Removing /etc/systemd/system/paqet.service..."
    $SUDO_CMD rm -f /etc/systemd/system/paqet.service
    $SUDO_CMD systemctl daemon-reload
    print_success "Service file removed"
else
    print_info "Service file not found"
fi

# Step 3: Remove paqet binary
print_header "Step 3: Removing paqet Binary"
if [ -f "/usr/local/bin/paqet" ]; then
    print_info "Removing /usr/local/bin/paqet..."
    $SUDO_CMD rm -f /usr/local/bin/paqet
    print_success "Binary removed"
else
    print_info "Binary not found"
fi

# Step 4: Ask about configuration removal
print_header "Step 4: Configuration Files"
read -p "Do you want to remove configuration files (/etc/paqet/)? (yes/no): " REMOVE_CONFIG

if [ "$REMOVE_CONFIG" = "yes" ]; then
    if [ -d "/etc/paqet" ]; then
        print_info "Removing /etc/paqet/..."
        $SUDO_CMD rm -rf /etc/paqet
        print_success "Configuration directory removed"
    else
        print_info "Configuration directory not found"
    fi
else
    print_info "Configuration files kept"
fi

# Step 5: Ask about iptables rules removal
print_header "Step 5: iptables Rules"
print_warning "iptables rules removal requires the port number that was used"
read -p "Do you want to remove iptables rules? (yes/no): " REMOVE_IPTABLES

if [ "$REMOVE_IPTABLES" = "yes" ]; then
    read -p "Enter the port that was used for paqet client iptables: " CLIENT_PORT
    
    if [ -n "$CLIENT_PORT" ]; then
        print_info "Removing iptables rules for port ${CLIENT_PORT}..."
        
        # Remove iptables rules (ignore errors if rules don't exist)
        $SUDO_CMD iptables -t raw -D PREROUTING -p tcp --dport ${CLIENT_PORT} -j NOTRACK 2>/dev/null || true
        $SUDO_CMD iptables -t raw -D OUTPUT -p tcp --sport ${CLIENT_PORT} -j NOTRACK 2>/dev/null || true
        $SUDO_CMD iptables -t mangle -D OUTPUT -p tcp --sport ${CLIENT_PORT} --tcp-flags RST RST -j DROP 2>/dev/null || true
        
        # Save iptables rules
        if command -v netfilter-persistent &> /dev/null; then
            $SUDO_CMD netfilter-persistent save
            print_success "iptables rules removed and saved"
        else
            print_warning "netfilter-persistent not found, rules removed but not persisted"
        fi
    else
        print_warning "No port provided, skipping iptables cleanup"
    fi
else
    print_info "iptables rules kept"
fi

# Step 6: Ask about UFW rules removal
print_header "Step 6: UFW Rules"

# Check if UFW is installed
if command -v ufw &> /dev/null; then
    read -p "Do you want to remove UFW rules? (yes/no): " REMOVE_UFW

    if [ "$REMOVE_UFW" = "yes" ]; then
        read -p "Enter the port that was allowed through UFW: " UFW_PORT
        
        if [ -n "$UFW_PORT" ]; then
            print_info "Removing UFW rule for port ${UFW_PORT}..."
            $SUDO_CMD ufw delete allow ${UFW_PORT}/tcp 2>/dev/null || true
            print_success "UFW rule removed"
        else
            print_warning "No port provided, skipping UFW cleanup"
        fi
    else
        print_info "UFW rules kept"
    fi
else
    print_info "UFW is not installed, skipping UFW cleanup"
fi

# Final Summary
print_header "Uninstallation Complete!"
echo -e "${GREEN}paqet client has been removed from your system${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo -e "  ✓ Service stopped and disabled"
echo -e "  ✓ Binary removed"
if [ "$REMOVE_CONFIG" = "yes" ]; then
    echo -e "  ✓ Configuration files removed"
else
    echo -e "  - Configuration files kept at /etc/paqet/"
fi
if [ "$REMOVE_IPTABLES" = "yes" ]; then
    echo -e "  ✓ iptables rules removed"
else
    echo -e "  - iptables rules kept"
fi
if [ "$REMOVE_UFW" = "yes" ] 2>/dev/null; then
    echo -e "  ✓ UFW rules removed"
else
    echo -e "  - UFW rules kept"
fi
echo -e "  - System libraries kept (libpcap, iptables-persistent, etc.)"
echo ""
echo -e "${GREEN}Uninstallation completed successfully!${NC}"