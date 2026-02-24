#!/bin/bash

# paqet Management Script
# Unified installer / uninstaller for paqet server and client on Ubuntu (amd64)
# Usage: bash paqet-manage.sh
#        bash paqet-manage.sh install-server
#        bash paqet-manage.sh install-client
#        bash paqet-manage.sh uninstall-server
#        bash paqet-manage.sh uninstall-client
#        bash paqet-manage.sh status-server
#        bash paqet-manage.sh status-client

set -e

# ============================================================================
#  Colors & styles
# ============================================================================
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# ============================================================================
#  Constants
# ============================================================================
PAQET_VERSION_FALLBACK="v1.0.0-alpha.15"   # used when GitHub API is unreachable
PAQET_BINARY_NAME="paqet_linux_amd64"      # name inside the tarball
PAQET_INSTALL_PATH="/usr/local/bin/paqet"
PAQET_CONFIG_DIR="/etc/paqet"
PAQET_SERVICE_FILE="/etc/systemd/system/paqet.service"
PAQET_PORT_FILE="${PAQET_CONFIG_DIR}/iptables-port"  # sidecar: stores iptables port

# Set by step_select_version()
PAQET_VERSION=""
PAQET_DOWNLOAD_URL=""

# Step counter (set per mode)
_STEP=0
_TOTAL_STEPS=0

# ============================================================================
#  Print helpers
# ============================================================================

print_info()    { echo -e "  ${BLUE}${BOLD}ℹ${NC}  $1"; }
print_success() { echo -e "  ${GREEN}${BOLD}✔${NC}  $1"; }
print_warning() { echo -e "  ${YELLOW}${BOLD}⚠${NC}  $1"; }
print_error()   { echo -e "  ${RED}${BOLD}✘${NC}  $1"; }
print_dim()     { echo -e "  ${DIM}$1${NC}"; }

# Section header: print_section "Title"
print_section() {
    _STEP=$(( _STEP + 1 ))
    local counter=""
    [ "${_TOTAL_STEPS}" -gt 0 ] && counter=" ${DIM}[${_STEP}/${_TOTAL_STEPS}]${NC}"
    echo ""
    echo -e "  ${CYAN}${BOLD}▶  $1${NC}${counter}"
    echo -e "  ${DIM}$(printf '%.0s─' {1..52})${NC}"
}

# Full-width banner box
print_banner() {
    local color="${1}"
    local title="${2}"
    local subtitle="${3:-}"
    echo ""
    echo -e "${color}${BOLD}  ╔══════════════════════════════════════════════════════╗${NC}"
    printf "${color}${BOLD}  ║  %-52s║${NC}\n" "${title}"
    if [ -n "${subtitle}" ]; then
        printf "${color}${BOLD}  ║  %-52s║${NC}\n" "${subtitle}"
    fi
    echo -e "${color}${BOLD}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Key-value row inside a summary box:  kv_row "Label" "value"
kv_row() {
    printf "  ${DIM}│${NC}  ${WHITE}%-22s${NC}  ${GREEN}%-28s${NC}  ${DIM}│${NC}\n" "$1" "$2"
}

kv_row_plain() {
    printf "  ${DIM}│${NC}  ${WHITE}%-22s${NC}  ${DIM}%-28s${NC}  ${DIM}│${NC}\n" "$1" "$2"
}

print_table_top()    { echo -e "  ${DIM}┌──────────────────────────────────────────────────────┐${NC}"; }
print_table_bottom() { echo -e "  ${DIM}└──────────────────────────────────────────────────────┘${NC}"; }
print_table_divider(){ echo -e "  ${DIM}├──────────────────────────────────────────────────────┤${NC}"; }

# Spinner — run in background, call stop_spinner when done
_SPINNER_PID=""
start_spinner() {
    local msg="$1"
    (
        local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local i=0
        while true; do
            printf "\r  ${CYAN}${frames[$i]}${NC}  %s  " "${msg}"
            i=$(( (i+1) % ${#frames[@]} ))
            sleep 0.1
        done
    ) &
    _SPINNER_PID=$!
    disown "${_SPINNER_PID}" 2>/dev/null || true
}

stop_spinner() {
    local msg="${1:-Done}"
    if [ -n "${_SPINNER_PID}" ]; then
        kill "${_SPINNER_PID}" 2>/dev/null || true
        _SPINNER_PID=""
    fi
    printf "\r  ${GREEN}${BOLD}✔${NC}  %-50s\n" "${msg}"
}

# Prompt with a visible default:  ask "Question" default_value VAR_NAME
ask() {
    local prompt="$1"
    local default="$2"
    local var="$3"
    local display_default=""
    [ -n "${default}" ] && display_default=" ${DIM}[${default}]${NC}"
    echo -ne "  ${WHITE}${BOLD}?${NC}  ${prompt}${display_default}: "
    read -r _input
    printf -v "${var}" '%s' "${_input:-${default}}"
}

# yes/no confirm:  confirm "Question" → returns 0 (yes) or 1 (no)
confirm() {
    echo -ne "  ${WHITE}${BOLD}?${NC}  $1 ${DIM}(yes/no)${NC}: "
    read -r _yn
    [ "${_yn}" = "yes" ]
}

# ============================================================================
#  Version selection
# ============================================================================

fetch_latest_version() {
    local tag
    tag=$(curl -fsSL --max-time 10 \
        "https://api.github.com/repos/hanselime/paqet/releases/latest" \
        2>/dev/null \
        | grep '"tag_name"' \
        | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    echo "${tag}"
}

step_select_version() {
    print_section "Select paqet Version"
    print_info "Checking latest release on GitHub..."

    local latest
    latest=$(fetch_latest_version)

    local default_version
    if [ -n "${latest}" ]; then
        print_success "Latest release found: ${GREEN}${BOLD}${latest}${NC}"
        default_version="${latest}"
    else
        print_warning "GitHub API unreachable — falling back to ${PAQET_VERSION_FALLBACK}"
        default_version="${PAQET_VERSION_FALLBACK}"
    fi

    echo ""
    ask "Version to install" "${default_version}" PAQET_VERSION
    print_info "Will install: ${GREEN}${BOLD}${PAQET_VERSION}${NC}"
    PAQET_DOWNLOAD_URL="https://github.com/hanselime/paqet/releases/download/${PAQET_VERSION}/paqet-linux-amd64-${PAQET_VERSION}.tar.gz"
}

# ============================================================================
#  Root / sudo detection
# ============================================================================

detect_user() {
    if [ "$EUID" -eq 0 ]; then
        IS_ROOT=true
        SUDO_CMD=""
        CURRENT_USER="root"
    else
        IS_ROOT=false
        SUDO_CMD="sudo"
        CURRENT_USER="${USER}"
        if ! command -v sudo &>/dev/null; then
            print_error "sudo is not installed. Run as root or install sudo."
            exit 1
        fi
    fi
}

# ============================================================================
#  Shared install steps
# ============================================================================

step_system_update() {
    print_section "System Update"
    start_spinner "Running apt update & upgrade..."
    $SUDO_CMD apt-get update -qq && $SUDO_CMD apt-get upgrade -y -qq
    stop_spinner "System is up to date"
}

step_install_essentials() {
    print_section "Essential Packages"
    start_spinner "Installing curl, wget, net-tools, unzip..."
    $SUDO_CMD apt-get install -y -qq \
        curl wget git nano vim htop net-tools unzip zip software-properties-common
    stop_spinner "Essential packages ready"
}

step_download_binary() {
    print_section "Download paqet ${PAQET_VERSION}"
    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/paqet-install-XXXXXX)
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp_dir}'" EXIT
    (
        cd "${tmp_dir}"
        start_spinner "Downloading paqet ${PAQET_VERSION}..."
        wget -q "${PAQET_DOWNLOAD_URL}"
        stop_spinner "Download complete"

        start_spinner "Extracting archive..."
        tar -xf "paqet-linux-amd64-${PAQET_VERSION}.tar.gz"
        stop_spinner "Extracted"

        $SUDO_CMD mv "${PAQET_BINARY_NAME}" "${PAQET_INSTALL_PATH}"
        $SUDO_CMD chmod +x "${PAQET_INSTALL_PATH}"
    )
    trap - EXIT
    rm -rf "${tmp_dir}"
    print_success "Binary installed → ${PAQET_INSTALL_PATH}"
}

step_install_dependencies() {
    print_section "paqet Dependencies"
    start_spinner "Installing libpcap-dev & iptables-persistent..."
    # DEBIAN_FRONTEND avoids the interactive "save rules?" prompt
    DEBIAN_FRONTEND=noninteractive $SUDO_CMD apt-get install -y -qq \
        libpcap-dev iptables-persistent
    stop_spinner "Packages installed"

    # NOTE: amd64-specific path. arm64 would use aarch64-linux-gnu.
    $SUDO_CMD ln -sf \
        /usr/lib/x86_64-linux-gnu/libpcap.so \
        /usr/lib/x86_64-linux-gnu/libpcap.so.0.8
    $SUDO_CMD ldconfig
    print_success "libpcap symlink created"
}

step_test_binary() {
    print_section "Verify Binary"
    if paqet --help &>/dev/null; then
        print_success "paqet binary is working"
    else
        print_error "paqet binary test failed"
        exit 1
    fi
}

step_discover_network() {
    print_section "Network Discovery"
    start_spinner "Reading default route..."
    local default_route
    default_route=$(ip r | grep '^default')
    GATEWAY_IP=$(echo "${default_route}" | awk '{print $3}')
    INTERFACE=$(echo "${default_route}"  | awk '{print $5}')
    stop_spinner "Route detected"

    print_info "Interface:   ${GREEN}${BOLD}${INTERFACE}${NC}"
    print_info "Gateway IP:  ${GREEN}${BOLD}${GATEWAY_IP}${NC}"

    start_spinner "Resolving gateway MAC (pinging ${GATEWAY_IP})..."
    ping -c 3 "${GATEWAY_IP}" >/dev/null 2>&1 || true

    local attempts=0
    GATEWAY_MAC=""
    while [ ${attempts} -lt 5 ]; do
        sleep 1
        GATEWAY_MAC=$(arp -n "${GATEWAY_IP}" | grep "${GATEWAY_IP}" | awk '{print $3}')
        if [ -n "${GATEWAY_MAC}" ] && [ "${GATEWAY_MAC}" != "<incomplete>" ]; then
            break
        fi
        attempts=$(( attempts + 1 ))
        ping -c 1 "${GATEWAY_IP}" >/dev/null 2>&1 || true
    done
    stop_spinner "ARP resolved"

    if [ -z "${GATEWAY_MAC}" ] || [ "${GATEWAY_MAC}" = "<incomplete>" ]; then
        print_error "Could not resolve gateway MAC. Check connectivity."
        exit 1
    fi

    LOCAL_IP=$(ip -4 addr show "${INTERFACE}" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

    print_info "Gateway MAC: ${GREEN}${BOLD}${GATEWAY_MAC}${NC}"
    print_info "Local IP:    ${GREEN}${BOLD}${LOCAL_IP}${NC}"
}

# $1 = port number
step_configure_iptables() {
    local port="$1"
    print_section "iptables Rules"
    start_spinner "Applying rules for port ${port}..."
    $SUDO_CMD iptables -t raw    -A PREROUTING -p tcp --dport "${port}" -j NOTRACK
    $SUDO_CMD iptables -t raw    -A OUTPUT     -p tcp --sport "${port}" -j NOTRACK
    $SUDO_CMD iptables -t mangle -A OUTPUT     -p tcp --sport "${port}" --tcp-flags RST RST -j DROP
    $SUDO_CMD netfilter-persistent save -q 2>/dev/null || $SUDO_CMD netfilter-persistent save
    stop_spinner "iptables rules saved (port ${port})"

    # Persist the port so uninstall can find it without asking
    $SUDO_CMD mkdir -p "${PAQET_CONFIG_DIR}"
    echo "${port}" | $SUDO_CMD tee "${PAQET_PORT_FILE}" >/dev/null
    print_dim "Port recorded in ${PAQET_PORT_FILE}"
}

# $1 = config path,  $2 = role (server|client)
step_write_service() {
    local config_path="$1"
    local role="$2"
    print_section "systemd Service"

    if [ "${IS_ROOT}" = true ]; then
        $SUDO_CMD tee "${PAQET_SERVICE_FILE}" >/dev/null <<EOF
[Unit]
Description=paqet ${role^}
After=network.target

[Service]
ExecStart=${PAQET_INSTALL_PATH} run -c ${config_path}
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    else
        $SUDO_CMD tee "${PAQET_SERVICE_FILE}" >/dev/null <<EOF
[Unit]
Description=paqet ${role^}
After=network.target

[Service]
User=${CURRENT_USER}
ExecStart=${PAQET_INSTALL_PATH} run -c ${config_path}
Restart=always
RestartSec=2

AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    fi
    print_success "Service file written → ${PAQET_SERVICE_FILE}"
}

step_enable_service() {
    print_section "Start Service"
    start_spinner "Enabling and starting paqet..."
    $SUDO_CMD systemctl daemon-reload
    $SUDO_CMD systemctl enable paqet -q
    $SUDO_CMD systemctl start  paqet
    sleep 2
    stop_spinner "Service started"

    local status
    status=$($SUDO_CMD systemctl is-active paqet 2>/dev/null || echo "unknown")
    if [ "${status}" = "active" ]; then
        print_success "Service is ${GREEN}${BOLD}active${NC}"
    else
        print_warning "Service status: ${YELLOW}${status}${NC}"
        print_dim "Check logs: journalctl -u paqet -n 30 --no-pager"
    fi
}

# ============================================================================
#  Shared uninstall steps
# ============================================================================

step_stop_service() {
    print_section "Stop Service"
    if systemctl is-active --quiet paqet 2>/dev/null; then
        $SUDO_CMD systemctl stop paqet
        print_success "Service stopped"
    else
        print_dim "Service was not running"
    fi
    if systemctl is-enabled --quiet paqet 2>/dev/null; then
        $SUDO_CMD systemctl disable paqet -q
        print_success "Service disabled"
    else
        print_dim "Service was not enabled"
    fi
}

step_remove_service_file() {
    print_section "Remove systemd Service"
    if [ -f "${PAQET_SERVICE_FILE}" ]; then
        $SUDO_CMD rm -f "${PAQET_SERVICE_FILE}"
        $SUDO_CMD systemctl daemon-reload
        print_success "Service file removed"
    else
        print_dim "Service file not found — skipping"
    fi
}

step_remove_binary() {
    print_section "Remove Binary"
    if [ -f "${PAQET_INSTALL_PATH}" ]; then
        $SUDO_CMD rm -f "${PAQET_INSTALL_PATH}"
        print_success "Binary removed"
    else
        print_dim "Binary not found — skipping"
    fi
}

step_maybe_remove_config() {
    print_section "Configuration Files"
    echo ""
    if confirm "Remove config directory ${PAQET_CONFIG_DIR}?"; then
        if [ -d "${PAQET_CONFIG_DIR}" ]; then
            $SUDO_CMD rm -rf "${PAQET_CONFIG_DIR}"
            print_success "Configuration directory removed"
        else
            print_dim "Directory not found — skipping"
        fi
    else
        print_dim "Keeping config at ${PAQET_CONFIG_DIR}"
    fi
}

step_remove_secret_key() {
    local key_file
    [ "${IS_ROOT}" = true ] && key_file="/root/paqet-secret-key.txt" \
                             || key_file="${HOME}/paqet-secret-key.txt"
    if [ -f "${key_file}" ]; then
        rm -f "${key_file}"
        print_success "Secret key file removed"
    else
        print_dim "Secret key file not found — skipping"
    fi
}

step_maybe_remove_iptables() {
    print_section "iptables Rules"
    echo ""
    if ! confirm "Remove iptables rules?"; then
        print_dim "Keeping iptables rules"
        return
    fi

    # Read port from sidecar file written during install
    local RM_PORT=""
    if [ -f "${PAQET_PORT_FILE}" ]; then
        RM_PORT=$(cat "${PAQET_PORT_FILE}" 2>/dev/null | tr -d '[:space:]')
    fi

    if [ -n "${RM_PORT}" ]; then
        print_info "Found saved port: ${GREEN}${BOLD}${RM_PORT}${NC}"
    else
        print_warning "Port file not found (${PAQET_PORT_FILE})"
        ask "Enter the port that was used" "" RM_PORT
    fi

    if [ -z "${RM_PORT}" ]; then
        print_warning "No port provided — skipping iptables cleanup"
        return
    fi

    start_spinner "Removing iptables rules for port ${RM_PORT}..."
    $SUDO_CMD iptables -t raw    -D PREROUTING -p tcp --dport "${RM_PORT}" -j NOTRACK          2>/dev/null || true
    $SUDO_CMD iptables -t raw    -D OUTPUT     -p tcp --sport "${RM_PORT}" -j NOTRACK          2>/dev/null || true
    $SUDO_CMD iptables -t mangle -D OUTPUT     -p tcp --sport "${RM_PORT}" --tcp-flags RST RST -j DROP 2>/dev/null || true

    if command -v netfilter-persistent &>/dev/null; then
        $SUDO_CMD netfilter-persistent save -q 2>/dev/null || $SUDO_CMD netfilter-persistent save
        stop_spinner "Rules removed and saved (port ${RM_PORT})"
    else
        stop_spinner "Rules removed for this session"
        print_warning "netfilter-persistent not found — rules will not survive reboot"
    fi
}

# ============================================================================
#  Mode: install server
# ============================================================================

do_install_server() {
    _STEP=0; _TOTAL_STEPS=13
    print_banner "${GREEN}" "  paqet Server  —  Install" "  Ubuntu amd64"

    step_system_update
    step_install_essentials
    step_select_version
    step_download_binary
    step_install_dependencies
    step_test_binary

    # ── Secret key ──────────────────────────────────────────────────────────
    print_section "Generate Secret Key"
    SECRET_KEY=$(paqet secret | tail -n 1)
    print_success "Key generated"
    print_warning "Save this key — clients need it to connect"
    local key_file
    [ "${IS_ROOT}" = true ] && key_file="/root/paqet-secret-key.txt" \
                             || key_file="${HOME}/paqet-secret-key.txt"
    echo "${SECRET_KEY}" > "${key_file}"
    print_dim "Key saved → ${key_file}"

    # ── Network ─────────────────────────────────────────────────────────────
    step_discover_network

    # ── Port ────────────────────────────────────────────────────────────────
    print_section "Server Port"
    print_warning "Avoid standard ports (80, 443) — iptables rules can interfere"
    echo ""
    ask "Listen port" "9999" PAQET_PORT

    step_configure_iptables "${PAQET_PORT}"

    # ── Config ──────────────────────────────────────────────────────────────
    print_section "Write Config"
    $SUDO_CMD mkdir -p "${PAQET_CONFIG_DIR}"
    $SUDO_CMD tee "${PAQET_CONFIG_DIR}/server.yaml" >/dev/null <<EOF
# paqet Server Configuration — auto-generated by paqet-manage.sh

role: "server"

log:
  level: "info"

listen:
  addr: ":${PAQET_PORT}"

network:
  interface: "${INTERFACE}"
  ipv4:
    addr: "${LOCAL_IP}:${PAQET_PORT}"
    router_mac: "${GATEWAY_MAC}"

transport:
  protocol: "kcp"
  conn: 1
  kcp:
    mode: "fast"
    key: "${SECRET_KEY}"
EOF
    print_success "Config written → ${PAQET_CONFIG_DIR}/server.yaml"

    step_write_service "${PAQET_CONFIG_DIR}/server.yaml" "server"
    step_enable_service

    # ── Summary ─────────────────────────────────────────────────────────────
    echo ""
    print_banner "${GREEN}" "  Server Installation Complete"
    print_table_top
    kv_row "Version"       "${PAQET_VERSION}"
    kv_row "Running as"    "${CURRENT_USER}"
    kv_row "Server IP"     "${LOCAL_IP}"
    kv_row "Server Port"   "${PAQET_PORT}"
    kv_row "Interface"     "${INTERFACE}"
    kv_row "Gateway IP"    "${GATEWAY_IP}"
    kv_row "Gateway MAC"   "${GATEWAY_MAC}"
    print_table_divider
    kv_row "Secret Key"    "${SECRET_KEY}"
    print_table_divider
    kv_row_plain "Config"  "${PAQET_CONFIG_DIR}/server.yaml"
    kv_row_plain "Logs"    "journalctl -u paqet -f"
    kv_row_plain "Status"  "systemctl status paqet"
    print_table_bottom
    echo ""
    echo -e "  ${YELLOW}${BOLD}Client config snippet:${NC}"
    echo -e "  ${DIM}  server:"
    echo -e "        addr: \"${LOCAL_IP}:${PAQET_PORT}\""
    echo -e "      transport:"
    echo -e "        kcp:"
    echo -e "          key: \"${SECRET_KEY}\"${NC}"
    echo ""
}

# ============================================================================
#  Optional: 3x-ui panel
# ============================================================================

step_maybe_install_xui() {
    echo ""
    print_table_top
    printf "  ${DIM}│${NC}  ${CYAN}${BOLD}%-52s${NC}  ${DIM}│${NC}\n" "Optional: 3x-ui Panel"
    print_table_bottom
    print_dim "3x-ui is a web panel for managing Xray/V2Ray inbound proxies."
    echo ""
    if confirm "Install 3x-ui now?"; then
        print_section "Install 3x-ui"
        start_spinner "Downloading 3x-ui installer..."
        curl -fsSL https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh \
            -o /tmp/3x-ui-install.sh
        stop_spinner "Installer downloaded"
        $SUDO_CMD bash /tmp/3x-ui-install.sh
        rm -f /tmp/3x-ui-install.sh
        print_success "3x-ui installed"
    else
        print_dim "Skipping. Install later with:"
        echo -e "  ${GREEN}curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh | sudo bash${NC}"
    fi
}

# ============================================================================
#  Mode: install client
# ============================================================================

do_install_client() {
    _STEP=0; _TOTAL_STEPS=13
    print_banner "${CYAN}" "  paqet Client  —  Install" "  Ubuntu amd64"

    step_system_update
    step_install_essentials
    step_select_version
    step_download_binary
    step_install_dependencies
    step_test_binary

    # ── Server details ───────────────────────────────────────────────────────
    print_section "Server Details"
    print_dim "You need the server IP:PORT and the secret key from the server."
    echo ""
    ask "Server address (IP:PORT)" "" SERVER_ADDR
    ask "Secret key" "" SECRET_KEY
    if [ -z "${SERVER_ADDR}" ] || [ -z "${SECRET_KEY}" ]; then
        print_error "Server address and secret key are required."
        exit 1
    fi

    # ── Network ─────────────────────────────────────────────────────────────
    step_discover_network

    # ── SOCKS5 ──────────────────────────────────────────────────────────────
    print_section "SOCKS5 Proxy"
    ask "SOCKS5 listen address" "127.0.0.1:1080" SOCKS5_LISTEN

    # ── iptables port — derived from SERVER_ADDR, no separate prompt ────────
    CLIENT_PORT=$(echo "${SERVER_ADDR}" | grep -oP ':\K[0-9]+$' || true)
    if [ -z "${CLIENT_PORT}" ]; then
        print_error "Could not extract port from server address '${SERVER_ADDR}'. Use IP:PORT format."
        exit 1
    fi
    print_info "iptables port derived from server address: ${GREEN}${BOLD}${CLIENT_PORT}${NC}"

    step_configure_iptables "${CLIENT_PORT}"

    # ── Config ──────────────────────────────────────────────────────────────
    print_section "Write Config"
    $SUDO_CMD mkdir -p "${PAQET_CONFIG_DIR}"
    $SUDO_CMD tee "${PAQET_CONFIG_DIR}/client.yaml" >/dev/null <<EOF
# paqet Client Configuration — auto-generated by paqet-manage.sh

role: "client"

log:
  level: "info"

socks5:
  - listen: "${SOCKS5_LISTEN}"

network:
  interface: "${INTERFACE}"
  ipv4:
    addr: "${LOCAL_IP}:0"
    router_mac: "${GATEWAY_MAC}"

server:
  addr: "${SERVER_ADDR}"

transport:
  protocol: "kcp"
  conn: 1
  kcp:
    mode: "fast"
    key: "${SECRET_KEY}"
EOF
    print_success "Config written → ${PAQET_CONFIG_DIR}/client.yaml"

    step_write_service "${PAQET_CONFIG_DIR}/client.yaml" "client"
    step_enable_service

    # ── Summary ─────────────────────────────────────────────────────────────
    echo ""
    print_banner "${CYAN}" "  Client Installation Complete"
    print_table_top
    kv_row "Version"        "${PAQET_VERSION}"
    kv_row "Running as"     "${CURRENT_USER}"
    kv_row "Client IP"      "${LOCAL_IP}"
    kv_row "Interface"      "${INTERFACE}"
    kv_row "Gateway IP"     "${GATEWAY_IP}"
    kv_row "Gateway MAC"    "${GATEWAY_MAC}"
    kv_row "Server Address" "${SERVER_ADDR}"
    kv_row "SOCKS5 Listen"  "${SOCKS5_LISTEN}"
    kv_row "iptables Port"  "${CLIENT_PORT}"
    print_table_divider
    kv_row_plain "Config"   "${PAQET_CONFIG_DIR}/client.yaml"
    kv_row_plain "Logs"     "journalctl -u paqet -f"
    kv_row_plain "Status"   "systemctl status paqet"
    print_table_bottom
    echo ""
    echo -e "  ${YELLOW}${BOLD}Test the proxy:${NC}"
    echo -e "  ${GREEN}  curl https://httpbin.org/ip --proxy socks5h://${SOCKS5_LISTEN}${NC}"
    echo ""

    step_maybe_install_xui
}

# ============================================================================
#  Mode: reinstall
# ============================================================================

do_reinstall() {
    local role="$1"
    print_banner "${YELLOW}" "  paqet ${role^}  —  Reinstall" "  Full uninstall + fresh install"
    print_warning "You will be asked about config & iptables during the uninstall step."
    echo ""
    if ! confirm "Continue with reinstall?"; then
        print_dim "Reinstall cancelled."
        exit 0
    fi
    [ "${role}" = "server" ] && do_uninstall_server || do_uninstall_client
    [ "${role}" = "server" ] && do_install_server   || do_install_client
}

# ============================================================================
#  Mode: uninstall server
# ============================================================================

do_uninstall_server() {
    _STEP=0; _TOTAL_STEPS=6
    print_banner "${RED}" "  paqet Server  —  Uninstall"

    echo ""
    print_table_top
    kv_row_plain "Will remove" "systemd service"
    kv_row_plain ""            "binary (${PAQET_INSTALL_PATH})"
    kv_row_plain ""            "config (${PAQET_CONFIG_DIR}/)"
    kv_row_plain ""            "iptables rules"
    [ "${IS_ROOT}" = true ] \
        && kv_row_plain "" "/root/paqet-secret-key.txt" \
        || kv_row_plain "" "~/paqet-secret-key.txt"
    kv_row_plain "Will keep"  "libpcap, iptables-persistent"
    print_table_bottom
    echo ""

    if ! confirm "Proceed with uninstall?"; then
        print_dim "Uninstall cancelled."
        exit 0
    fi

    step_stop_service
    step_remove_service_file
    step_remove_binary
    step_remove_secret_key
    step_maybe_remove_config
    step_maybe_remove_iptables

    echo ""
    print_banner "${GREEN}" "  Server Uninstall Complete"
}

# ============================================================================
#  Mode: uninstall client
# ============================================================================

do_uninstall_client() {
    _STEP=0; _TOTAL_STEPS=5
    print_banner "${RED}" "  paqet Client  —  Uninstall"

    echo ""
    print_table_top
    kv_row_plain "Will remove" "systemd service"
    kv_row_plain ""            "binary (${PAQET_INSTALL_PATH})"
    kv_row_plain ""            "config (${PAQET_CONFIG_DIR}/)"
    kv_row_plain ""            "iptables rules"
    kv_row_plain "Will keep"  "libpcap, iptables-persistent"
    print_table_bottom
    echo ""

    if ! confirm "Proceed with uninstall?"; then
        print_dim "Uninstall cancelled."
        exit 0
    fi

    step_stop_service
    step_remove_service_file
    step_remove_binary
    step_maybe_remove_config
    step_maybe_remove_iptables

    echo ""
    print_banner "${GREEN}" "  Client Uninstall Complete"
}

# ============================================================================
#  Mode: status
# ============================================================================

do_status() {
    local role="${1:-server}"
    print_banner "${CYAN}" "  paqet ${role^}  —  Status"

    # Service
    print_section "systemd Service"
    $SUDO_CMD systemctl status paqet --no-pager 2>/dev/null || true

    # Binary
    print_section "Binary"
    if [ -f "${PAQET_INSTALL_PATH}" ]; then
        print_success "${PAQET_INSTALL_PATH}"
        paqet version 2>/dev/null || true
    else
        print_warning "Not found: ${PAQET_INSTALL_PATH}"
    fi

    # Config
    print_section "Configuration"
    local cfg_file="${PAQET_CONFIG_DIR}/${role}.yaml"
    if [ -f "${cfg_file}" ]; then
        print_success "${cfg_file}"
    else
        print_warning "Not found: ${cfg_file}"
    fi

    if [ -f "${PAQET_PORT_FILE}" ]; then
        print_info "Saved iptables port: ${GREEN}$(cat "${PAQET_PORT_FILE}")${NC}"
    fi

    # iptables
    print_section "iptables Rules"
    local got_rules=false
    local r
    r=$($SUDO_CMD iptables -t raw    -L PREROUTING -n --line-numbers 2>/dev/null | grep NOTRACK || true)
    [ -n "${r}" ] && { echo -e "  ${DIM}raw PREROUTING:${NC}  ${r}"; got_rules=true; }
    r=$($SUDO_CMD iptables -t raw    -L OUTPUT     -n --line-numbers 2>/dev/null | grep NOTRACK || true)
    [ -n "${r}" ] && { echo -e "  ${DIM}raw OUTPUT:${NC}      ${r}"; got_rules=true; }
    r=$($SUDO_CMD iptables -t mangle -L OUTPUT     -n --line-numbers 2>/dev/null | grep DROP    || true)
    [ -n "${r}" ] && { echo -e "  ${DIM}mangle OUTPUT:${NC}   ${r}"; got_rules=true; }
    ${got_rules} || print_dim "No paqet iptables rules found"

    # Logs
    print_section "Recent Logs (last 20 lines)"
    $SUDO_CMD journalctl -u paqet --no-pager -n 20 2>/dev/null || true
}

# ============================================================================
#  Interactive menu
# ============================================================================

interactive_menu() {
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}  ║                                                      ║${NC}"
    echo -e "${CYAN}${BOLD}  ║        ██████╗  █████╗  ██████╗ ███████╗████████╗   ║${NC}"
    echo -e "${CYAN}${BOLD}  ║        ██╔══██╗██╔══██╗██╔═══██╗██╔════╝╚══██╔══╝   ║${NC}"
    echo -e "${CYAN}${BOLD}  ║        ██████╔╝███████║██║   ██║█████╗     ██║      ║${NC}"
    echo -e "${CYAN}${BOLD}  ║        ██╔═══╝ ██╔══██║██║▄▄ ██║██╔══╝     ██║      ║${NC}"
    echo -e "${CYAN}${BOLD}  ║        ██║     ██║  ██║╚██████╔╝███████╗   ██║      ║${NC}"
    echo -e "${CYAN}${BOLD}  ║        ╚═╝     ╚═╝  ╚═╝ ╚══▀▀═╝ ╚══════╝   ╚═╝      ║${NC}"
    echo -e "${CYAN}${BOLD}  ║                                                      ║${NC}"
    echo -e "${CYAN}${BOLD}  ║        Bidirectional KCP Proxy  —  Manager          ║${NC}"
    echo -e "${CYAN}${BOLD}  ║                                       Ubuntu amd64  ║${NC}"
    echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Role
    echo -e "  ${WHITE}${BOLD}Which role is this machine?${NC}"
    echo ""
    echo -e "  ${CYAN}  1${NC}  ${WHITE}Server${NC}  ${DIM}(the proxy endpoint — needs a public IP)${NC}"
    echo -e "  ${CYAN}  2${NC}  ${WHITE}Client${NC}  ${DIM}(the device that routes traffic through the server)${NC}"
    echo ""
    echo -ne "  ${WHITE}${BOLD}›${NC} "
    read -r ROLE_CHOICE
    case "${ROLE_CHOICE}" in
        1) ROLE="server" ;;
        2) ROLE="client" ;;
        *) print_error "Invalid choice."; exit 1 ;;
    esac

    echo ""
    echo -e "  ${WHITE}${BOLD}What would you like to do with paqet ${CYAN}${ROLE}${WHITE}?${NC}"
    echo ""
    echo -e "  ${GREEN}  1${NC}  ${WHITE}Install${NC}"
    echo -e "  ${YELLOW}  2${NC}  ${WHITE}Reinstall${NC}      ${DIM}(full uninstall + fresh install)${NC}"
    echo -e "  ${RED}  3${NC}  ${WHITE}Uninstall${NC}"
    echo -e "  ${CYAN}  4${NC}  ${WHITE}Status${NC}"
    echo ""
    echo -ne "  ${WHITE}${BOLD}›${NC} "
    read -r ACTION_CHOICE
    case "${ACTION_CHOICE}" in
        1) ACTION="install"   ;;
        2) ACTION="reinstall" ;;
        3) ACTION="uninstall" ;;
        4) ACTION="status"    ;;
        *) print_error "Invalid choice."; exit 1 ;;
    esac

    run_mode "${ROLE}-${ACTION}"
}

# ============================================================================
#  Dispatch
# ============================================================================

run_mode() {
    local mode="$1"
    case "${mode}" in
        install-server|server-install)     do_install_server ;;
        install-client|client-install)     do_install_client ;;
        reinstall-server|server-reinstall) do_reinstall "server" ;;
        reinstall-client|client-reinstall) do_reinstall "client" ;;
        uninstall-server|server-uninstall) do_uninstall_server ;;
        uninstall-client|client-uninstall) do_uninstall_client ;;
        status-server|server-status)       do_status "server" ;;
        status-client|client-status)       do_status "client" ;;
        *)
            print_error "Unknown mode: ${mode}"
            echo ""
            echo -e "  Valid modes:"
            echo -e "  ${DIM}install-server   install-client"
            echo -e "  reinstall-server reinstall-client"
            echo -e "  uninstall-server uninstall-client"
            echo -e "  status-server    status-client${NC}"
            exit 1
            ;;
    esac
}

# ============================================================================
#  Entry point
# ============================================================================

detect_user

if [ $# -ge 1 ]; then
    run_mode "$1"
else
    interactive_menu
fi
