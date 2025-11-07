#!/bin/bash

# VPN Master Panel Installation Script
# Форк 3x-ui с поддержкой многонодовой архитектуры

set -euo pipefail

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS, please contact the author!" >&2
    exit 1
fi
echo "The OS release is: $release"

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    *) echo -e "${green}Unsupported CPU architecture! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "arch: $(arch)"

os_version=""
os_version=$(grep "^VERSION_ID" /etc/os-release | cut -d '=' -f2 | tr -d '"' | tr -d '.')

if [[ "${release}" == "arch" ]]; then
    echo "Your OS is Arch Linux"
elif [[ "${release}" == "parch" ]]; then
    echo "Your OS is Parch Linux"
elif [[ "${release}" == "manjaro" ]]; then
    echo "Your OS is Manjaro"
elif [[ "${release}" == "armbian" ]]; then
    echo "Your OS is Armbian"
elif [[ "${release}" == "alpine" ]]; then
    echo "Your OS is Alpine Linux"
elif [[ "${release}" == "opensuse-tumbleweed" ]]; then
    echo "Your OS is OpenSUSE Tumbleweed"
elif [[ "${release}" == "openEuler" ]]; then
    if [[ ${os_version} -lt 2203 ]]; then
        echo -e "${red} Please use OpenEuler 22.03 or higher ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "centos" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red} Please use CentOS 8 or higher ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "ubuntu" ]]; then
    if [[ ${os_version} -lt 2004 ]]; then
        echo -e "${red} Please use Ubuntu 20 or higher version!${plain}\n" && exit 1
    fi
elif [[ "${release}" == "fedora" ]]; then
    if [[ ${os_version} -lt 36 ]]; then
        echo -e "${red} Please use Fedora 36 or higher version!${plain}\n" && exit 1
    fi
elif [[ "${release}" == "amzn" ]]; then
    if [[ ${os_version} != "2023" ]]; then
        echo -e "${red} Please use Amazon Linux 2023!${plain}\n" && exit 1
    fi
elif [[ "${release}" == "debian" ]]; then
    if [[ ${os_version} -lt 11 ]]; then
        echo -e "${red} Please use Debian 11 or higher ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "almalinux" ]]; then
    if [[ ${os_version} -lt 80 ]]; then
        echo -e "${red} Please use AlmaLinux 8.0 or higher ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "rocky" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red} Please use Rocky Linux 8 or higher ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "ol" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red} Please use Oracle Linux 8 or higher ${plain}\n" && exit 1
    fi
else
    echo -e "${red}Your operating system is not supported by this script.${plain}\n"
    echo "Please ensure you are using one of the following supported operating systems:"
    echo "- Ubuntu 20.04+"
    echo "- Debian 11+"
    echo "- CentOS 8+"
    echo "- OpenEuler 22.03+"
    echo "- Fedora 36+"
    echo "- Arch Linux"
    echo "- Parch Linux"
    echo "- Manjaro"
    echo "- Armbian"
    echo "- AlmaLinux 8.0+"
    echo "- Rocky Linux 8+"
    echo "- Oracle Linux 8+"
    echo "- OpenSUSE Tumbleweed"
    echo "- Amazon Linux 2023"
    exit 1
fi

install_base() {
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -y -q wget curl tar tzdata git
        ;;
    centos | almalinux | rocky | ol)
        yum -y update && yum install -y -q wget curl tar tzdata git
        ;;
    fedora | amzn)
        dnf -y update && dnf install -y -q wget curl tar tzdata git
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata git
        ;;
    opensuse-tumbleweed)
        zypper refresh && zypper -q install -y wget curl tar timezone git
        ;;
    *)
        apt-get update && apt install -y -q wget curl tar tzdata git
        ;;
    esac
}

check_go() {
    if ! command -v go &> /dev/null; then
        echo -e "${yellow}Go is not installed. Installing Go 1.23+...${plain}"
        GO_VERSION="1.23.5"
        ARCH=$(arch)
        case "${ARCH}" in
        amd64) GO_ARCH="amd64" ;;
        arm64) GO_ARCH="arm64" ;;
        armv7) GO_ARCH="armv6" ;;
        *) GO_ARCH="amd64" ;;
        esac
        
        wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -O /tmp/go.tar.gz
        rm -rf /usr/local/go
        tar -C /usr/local -xzf /tmp/go.tar.gz
        rm /tmp/go.tar.gz
        export PATH=$PATH:/usr/local/go/bin
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    fi
    echo -e "${green}Go version: $(go version)${plain}"
}

install_master() {
    echo -e "${green}Installing VPN Master Panel...${plain}"
    
    INSTALL_DIR="/opt/vpn-master"
    DATA_DIR="/var/lib/vpn-master"
    BIN_PATH="/usr/local/bin/vpn-master"
    
    mkdir -p "${INSTALL_DIR}"
    mkdir -p "${DATA_DIR}"
    
    # Build from source if we're in the repo, otherwise clone
    if [[ -f "${cur_dir}/go.mod" && -d "${cur_dir}/cmd/master" ]]; then
        echo -e "${green}Building from current directory...${plain}"
        cd "${cur_dir}"
        go mod download
        go build -o "${BIN_PATH}" ./cmd/master
    else
        echo -e "${yellow}Cloning repository...${plain}"
        REPO_URL="https://github.com/Differin3/x-ui-Fork.git"
        if [[ -d "${INSTALL_DIR}/.git" ]]; then
            git -C "${INSTALL_DIR}" pull
        else
            git clone "${REPO_URL}" "${INSTALL_DIR}"
        fi
        cd "${INSTALL_DIR}"
        go mod download
        go build -o "${BIN_PATH}" ./cmd/master
    fi
    
    chmod +x "${BIN_PATH}"
    
    # Generate HMAC secret
    SECRET=$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p -c 32)
    
    ENV_FILE="/etc/vpn-master.env"
    cat >"${ENV_FILE}" <<EOF
MASTER_HTTP_PORT=8085
MASTER_DB_DRIVER=sqlite
MASTER_DB_DSN=${DATA_DIR}/master.db
MASTER_DB_AUTO_MIGRATE=true
MASTER_HMAC_SECRET=${SECRET}
EOF
    
    chmod 600 "${ENV_FILE}"
    
    SERVICE_FILE="/etc/systemd/system/vpn-master.service"
    cat >"${SERVICE_FILE}" <<EOF
[Unit]
Description=VPN Master Control Panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
EnvironmentFile=${ENV_FILE}
ExecStart=${BIN_PATH}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable --now vpn-master.service
    
    echo -e "${green}VPN Master Panel installed successfully!${plain}"
    echo -e "${green}Service: vpn-master${plain}"
    echo -e "${green}Port: 8085${plain}"
    echo -e "${green}Database: ${DATA_DIR}/master.db${plain}"
    echo -e "${green}Config: ${ENV_FILE}${plain}"
    echo ""
    echo -e "${yellow}To check status: systemctl status vpn-master${plain}"
    echo -e "${yellow}To view logs: journalctl -u vpn-master -f${plain}"
}

echo -e "${green}Running installation...${plain}"
install_base
check_go
install_master

echo -e "${green}Installation completed!${plain}"
echo ""
echo -e "┌───────────────────────────────────────────────────────┐"
echo -e "│  ${blue}VPN Master Panel Control:${plain}                        │"
echo -e "│                                                       │"
echo -e "│  ${blue}systemctl start vpn-master${plain}   - Start            │"
echo -e "│  ${blue}systemctl stop vpn-master${plain}    - Stop             │"
echo -e "│  ${blue}systemctl restart vpn-master${plain} - Restart          │"
echo -e "│  ${blue}systemctl status vpn-master${plain}  - Status           │"
echo -e "│  ${blue}journalctl -u vpn-master -f${plain}  - View logs        │"
echo -e "└───────────────────────────────────────────────────────┘"
