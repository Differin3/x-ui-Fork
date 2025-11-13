#!/bin/bash

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

echo "Arch: $(arch)"

install_base() {
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    centos | rhel | almalinux | rocky | ol)
        yum -y update && yum install -y -q wget curl tar tzdata
        ;;
    fedora | amzn | virtuozzo)
        dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata
        ;;
    opensuse-tumbleweed | opensuse-leap)
        zypper refresh && zypper -q install -y wget curl tar timezone
        ;;
    alpine)
        apk update && apk add wget curl tar tzdata
        ;;
    *)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    esac
}

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

config_after_install() {
    local existing_hasDefaultCredential=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}')
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    local creds_file="/usr/local/x-ui/INSTALL_CREDS"
    local URL_lists=(
        "https://api4.ipify.org"
		"https://ipv4.icanhazip.com"
		"https://v4.api.ipinfo.io/ip"
		"https://ipv4.myexternalip.com/raw"
		"https://4.ident.me"
		"https://check-host.net/ip"
    )
    local server_ip=""
    for ip_address in "${URL_lists[@]}"; do
        server_ip=$(curl -s --max-time 3 "${ip_address}" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "${server_ip}" ]]; then
            break
        fi
    done

    if [[ ${#existing_webBasePath} -lt 4 ]]; then
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_webBasePath=$(gen_random_string 18)
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}" -webBasePath "${config_webBasePath}"
            # persist credentials for summary output
            echo "USERNAME=${config_username}" > "${creds_file}"
            echo "PASSWORD=${config_password}" >> "${creds_file}"
            chmod 600 "${creds_file}" >/dev/null 2>&1
            echo -e "This is a fresh installation, generating random login info for security concerns:"
            echo -e "###############################################"
            echo -e "${green}Username: ${config_username}${plain}"
            echo -e "${green}Password: ${config_password}${plain}"
            echo -e "${green}WebBasePath: ${config_webBasePath}${plain}"
            echo -e "###############################################"
            existing_webBasePath="${config_webBasePath}"
        else
            local config_webBasePath=$(gen_random_string 18)
            echo -e "${yellow}WebBasePath is missing or too short. Generating a new one...${plain}"
            /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}"
            echo -e "${green}New WebBasePath: ${config_webBasePath}${plain}"
            existing_webBasePath="${config_webBasePath}"
        fi
    else
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            echo -e "${yellow}Default credentials detected. Security update required...${plain}"
            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}"
            # persist credentials for summary output
            echo "USERNAME=${config_username}" > "${creds_file}"
            echo "PASSWORD=${config_password}" >> "${creds_file}"
            chmod 600 "${creds_file}" >/dev/null 2>&1
            echo -e "Generated new random login credentials:"
            echo -e "###############################################"
            echo -e "${green}Username: ${config_username}${plain}"
            echo -e "${green}Password: ${config_password}${plain}"
            echo -e "###############################################"
        else
            echo -e "${green}Username, Password, and WebBasePath are properly set. Exiting...${plain}"
        fi
    fi

    # Prompt for panel port selection
    is_valid_port() {
        [[ $1 =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
    }

    local env_port=""
    if [[ -n "${X_UI_PORT:-}" ]]; then
        env_port="${X_UI_PORT}"
    elif [[ -n "${PANEL_PORT:-}" ]]; then
        env_port="${PANEL_PORT}"
    fi

    local default_port="${existing_port:-5050}"
    if [[ -n "${env_port}" ]] && is_valid_port "${env_port}"; then
        default_port="${env_port}"
    fi

    local config_port="${default_port}"
    if [[ -t 0 ]]; then
        echo -e ""
        read -rp "Enter the panel port [default: ${default_port}]: " input_port
        while [[ -n "${input_port}" ]] && ! is_valid_port "${input_port}"; do
            read -rp "Invalid port. Please enter a number between 1 and 65535: " input_port
        done
        if [[ -n "${input_port}" ]]; then
            config_port="${input_port}"
        fi
    fi
    if ! is_valid_port "${config_port}"; then
        config_port=5050
    fi
    /usr/local/x-ui/x-ui setting -port "${config_port}"
    echo -e "${green}Panel port set to: ${config_port}${plain}"

    /usr/local/x-ui/x-ui migrate
}

print_access_summary() {
    local creds_file="/usr/local/x-ui/INSTALL_CREDS"
    local show_info=$(/usr/local/x-ui/x-ui setting -show true)
    local port=$(echo "$show_info" | awk '/port:/{print $2}')
    local base=$(echo "$show_info" | awk '/webBasePath:/{print $2}')
    # fetch IP from multiple sources with short timeouts
    local URL_lists=(
        "https://api4.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://v4.api.ipinfo.io/ip"
        "https://ipv4.myexternalip.com/raw"
        "https://4.ident.me"
        "https://check-host.net/ip"
    )
    local server_ip=""
    for ip_address in "${URL_lists[@]}"; do
        server_ip=$(curl -s --max-time 3 "${ip_address}" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "${server_ip}" ]]; then
            break
        fi
    done
    # decide protocol based on cert presence
    local cert_info=$(/usr/local/x-ui/x-ui setting -getCert true 2>/dev/null)
    local cert_path=$(echo "$cert_info" | awk '/cert:/{print $2}')
    local proto="http"
    [[ -n "$cert_path" ]] && proto="https"

    echo -e ""
    echo -e "════════════════ Panel Access Information ════════════════"
    echo -e "  Panel Port      : ${green}${port}${plain}"
    echo -e "  Web Base Path   : ${green}${base}${plain}"
    echo -e "  Server IP       : ${green}${server_ip}${plain}"
    echo -e "  Entry URL       : ${green}${proto}://${server_ip}:${port}${base}${plain}"
    if [[ -f "${creds_file}" ]]; then
        # shellcheck disable=SC1090
        source "${creds_file}"
        echo -e "  Username        : ${green}${USERNAME}${plain}"
        echo -e "  Password        : ${green}${PASSWORD}${plain}"
    else
        echo -e "  Username        : ${yellow}<unchanged> (not modified by installer)${plain}"
        echo -e "  Password        : ${yellow}<unchanged> (not modified by installer)${plain}"
    fi
    echo -e "══════════════════════════════════════════════════════════"
}

install_x-ui() {
    cd /usr/local/

    # Download resources
    if [ $# == 0 ]; then
        # Try multiple methods to get latest version with timeouts
        echo -e "${yellow}Fetching latest version from releases...${plain}"
        tag_version=$(curl -s --max-time 10 "https://api.github.com/repos/Differin3/x-ui-Fork/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$tag_version" ]]; then
            echo -e "${yellow}Trying with IPv4...${plain}"
            tag_version=$(curl -4 -s --max-time 10 "https://api.github.com/repos/Differin3/x-ui-Fork/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        fi
        if [[ ! -n "$tag_version" ]]; then
            echo -e "${yellow}Trying tags API...${plain}"
            tag_version=$(curl -s --max-time 10 "https://api.github.com/repos/Differin3/x-ui-Fork/tags?per_page=1" 2>/dev/null | grep '"name":' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
        fi
        if [[ ! -n "$tag_version" ]]; then
            echo -e "${yellow}Trying releases page...${plain}"
            tag_version=$(curl -s --max-time 10 "https://github.com/Differin3/x-ui-Fork/releases" 2>/dev/null | grep -oE 'releases/tag/v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's|releases/tag/||')
        fi
        if [[ ! -n "$tag_version" ]]; then
            echo -e "${yellow}No releases found, will build from main branch...${plain}"
            tag_version="main"
            USE_BUILD_FROM_SOURCE=true
        else
            echo -e "Got x-ui latest version: ${tag_version}, beginning the installation..."
            wget --inet4-only -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/Differin3/x-ui-Fork/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
            if [[ $? -ne 0 ]]; then
                echo -e "${yellow}Download failed, will build from main branch...${plain}"
                tag_version="main"
                USE_BUILD_FROM_SOURCE=true
            else
                USE_BUILD_FROM_SOURCE=false
            fi
        fi
    else
        USE_BUILD_FROM_SOURCE=false
        tag_version=$1
        tag_version_numeric=${tag_version#v}
        min_version="2.3.5"

        if [[ "$(printf '%s\n' "$min_version" "$tag_version_numeric" | sort -V | head -n1)" != "$min_version" ]]; then
            echo -e "${red}Please use a newer version (at least v2.3.5). Exiting installation.${plain}"
            exit 1
        fi

        url="https://github.com/Differin3/x-ui-Fork/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz"
        echo -e "Beginning to install x-ui $1"
        wget --inet4-only -N -O /usr/local/x-ui-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download x-ui $1 failed, please check if the version exists ${plain}"
            exit 1
        fi
    fi
    wget --inet4-only -O /usr/bin/x-ui-temp https://raw.githubusercontent.com/Differin3/x-ui-Fork/main/x-ui.sh
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Failed to download x-ui.sh${plain}"
        exit 1
    fi

    # Stop x-ui service and remove old resources
    if [[ -e /usr/local/x-ui/ ]]; then
        if [[ $release == "alpine" ]]; then
            rc-service x-ui stop
        else
            systemctl stop x-ui
        fi
        rm /usr/local/x-ui/ -rf
    fi

    # Build from source if releases are not available
    if [[ "${USE_BUILD_FROM_SOURCE}" == "true" ]]; then
        echo -e "${yellow}Building from main branch...${plain}"
        BUILD_DIR="/tmp/x-ui-build-$$"
        mkdir -p ${BUILD_DIR}
        cd ${BUILD_DIR}
        
        # Check if git and go are installed
        if ! command -v git &> /dev/null; then
            echo -e "${yellow}Installing git...${plain}"
            case "${release}" in
            ubuntu | debian | armbian)
                apt-get install -y -q git
                ;;
            centos | rhel | almalinux | rocky | ol)
                yum install -y -q git
                ;;
            fedora | amzn | virtuozzo)
                dnf install -y -q git
                ;;
            alpine)
                apk add -q git
                ;;
            esac
        fi
        
        if ! command -v go &> /dev/null; then
            echo -e "${yellow}Installing Go...${plain}"
            GO_VERSION="1.23"
            GO_ARCH=$(arch)
            if [[ "${GO_ARCH}" == "armv5" || "${GO_ARCH}" == "armv6" || "${GO_ARCH}" == "armv7" ]]; then
                GO_ARCH="armv6l"
            fi
            wget --inet4-only -q "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -O go.tar.gz
            if [[ $? -eq 0 ]]; then
                tar -C /usr/local -xzf go.tar.gz
                export PATH=$PATH:/usr/local/go/bin
            else
                echo -e "${red}Failed to download Go. Please install Go manually.${plain}"
                exit 1
            fi
        fi
        
        # Clone and build
        echo -e "${yellow}Cloning repository...${plain}"
        git clone --depth 1 https://github.com/Differin3/x-ui-Fork.git x-ui-source
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Failed to clone repository${plain}"
            exit 1
        fi
        
        cd x-ui-source
        echo -e "${yellow}Building x-ui...${plain}"
        go build -o x-ui .
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Build failed${plain}"
            exit 1
        fi
        
        # Create x-ui directory structure
        mkdir -p /usr/local/x-ui/bin
        cp x-ui /usr/local/x-ui/
        cp x-ui.sh /usr/local/x-ui/
        cp x-ui.service /usr/local/x-ui/ 2>/dev/null || true
        
        # Download xray binary (try to get from releases or use existing)
        XRAY_ARCH=$(arch)
        XRAY_PKG_ARCH=""
        XRAY_BIN_NAME=""
        if [[ "${XRAY_ARCH}" == "armv5" || "${XRAY_ARCH}" == "armv6" || "${XRAY_ARCH}" == "armv7" ]]; then
            XRAY_PKG_ARCH="arm32-v7a"
            XRAY_BIN_NAME="arm"
        elif [[ "${XRAY_ARCH}" == "arm64" || "${XRAY_ARCH}" == "aarch64" ]]; then
            XRAY_PKG_ARCH="arm64-v8a"
            XRAY_BIN_NAME="arm64"
        elif [[ "${XRAY_ARCH}" == "x86_64" || "${XRAY_ARCH}" == "amd64" ]]; then
            XRAY_PKG_ARCH="64"
            XRAY_BIN_NAME="amd64"
        elif [[ "${XRAY_ARCH}" == "i386" || "${XRAY_ARCH}" == "i686" ]]; then
            XRAY_PKG_ARCH="32"
            XRAY_BIN_NAME="386"
        else
            XRAY_PKG_ARCH="64"
            XRAY_BIN_NAME="amd64"
        fi
        
        XRAY_VERSION=$(curl -s --max-time 5 "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/v//')
        if [[ -n "${XRAY_VERSION}" ]]; then
            echo -e "${yellow}Downloading Xray ${XRAY_VERSION}...${plain}"
            wget --inet4-only -q "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-${XRAY_PKG_ARCH}.zip" -O xray.zip
            if [[ $? -eq 0 ]]; then
                unzip -q xray.zip -d /usr/local/x-ui/bin/
                mv /usr/local/x-ui/bin/xray /usr/local/x-ui/bin/xray-linux-${XRAY_BIN_NAME} 2>/dev/null || true
                chmod +x /usr/local/x-ui/bin/xray-linux-${XRAY_BIN_NAME}
            fi
        fi
        
        cd /usr/local/x-ui
        chmod +x x-ui x-ui.sh
        rm -rf ${BUILD_DIR}
        echo -e "${green}Build completed successfully${plain}"
    else
        # Extract resources and set permissions
        tar zxvf x-ui-linux-$(arch).tar.gz
        rm x-ui-linux-$(arch).tar.gz -f
        
        cd x-ui
        chmod +x x-ui
        chmod +x x-ui.sh
    fi

    # Check the system's architecture and rename the file accordingly
    if [[ "${USE_BUILD_FROM_SOURCE}" != "true" ]]; then
        ARCH_NAME=$(arch)
        BIN_NAME=""
        if [[ "${ARCH_NAME}" == "armv5" || "${ARCH_NAME}" == "armv6" || "${ARCH_NAME}" == "armv7" ]]; then
            BIN_NAME="arm"
            if [[ -f "bin/xray-linux-${ARCH_NAME}" ]]; then
                mv bin/xray-linux-${ARCH_NAME} bin/xray-linux-${BIN_NAME}
                chmod +x bin/xray-linux-${BIN_NAME}
            fi
        elif [[ "${ARCH_NAME}" == "arm64" || "${ARCH_NAME}" == "aarch64" ]]; then
            BIN_NAME="arm64"
        elif [[ "${ARCH_NAME}" == "x86_64" || "${ARCH_NAME}" == "amd64" ]]; then
            BIN_NAME="amd64"
            if [[ -f "bin/xray-linux-${ARCH_NAME}" ]]; then
                mv bin/xray-linux-${ARCH_NAME} bin/xray-linux-${BIN_NAME}
                chmod +x bin/xray-linux-${BIN_NAME}
            fi
        elif [[ "${ARCH_NAME}" == "i386" || "${ARCH_NAME}" == "i686" ]]; then
            BIN_NAME="386"
        else
            BIN_NAME="amd64"
        fi
        if [[ -f "bin/xray-linux-${BIN_NAME}" ]]; then
            chmod +x bin/xray-linux-${BIN_NAME}
        fi
        chmod +x x-ui
    fi

    # Update x-ui cli and se set permission
    mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
    chmod +x /usr/bin/x-ui

    # Ensure runtime deps (xray binary, geo files) exist before first start
    /usr/bin/x-ui repair >/dev/null 2>&1 || true
    config_after_install

    if [[ $release == "alpine" ]]; then
        wget --inet4-only -O /etc/init.d/x-ui https://raw.githubusercontent.com/Differin3/x-ui-Fork/main/x-ui.rc
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Failed to download x-ui.rc${plain}"
            exit 1
        fi
        chmod +x /etc/init.d/x-ui
        rc-update add x-ui
        rc-service x-ui start
    else
        cp -f x-ui.service /etc/systemd/system/
        systemctl daemon-reload
        systemctl enable x-ui
        systemctl start x-ui
    fi

    echo -e "${green}x-ui ${tag_version}${plain} installation finished, it is running now..."
    # Print detected access summary
    print_access_summary
    echo -e ""
    echo -e "┌───────────────────────────────────────────────────────┐
│  ${blue}x-ui control menu usages (subcommands):${plain}              │
│                                                       │
│  ${blue}x-ui${plain}              - Admin Management Script          │
│  ${blue}x-ui start${plain}        - Start                            │
│  ${blue}x-ui stop${plain}         - Stop                             │
│  ${blue}x-ui restart${plain}      - Restart                          │
│  ${blue}x-ui status${plain}       - Current Status                   │
│  ${blue}x-ui settings${plain}     - Current Settings                 │
│  ${blue}x-ui enable${plain}       - Enable Autostart on OS Startup   │
│  ${blue}x-ui disable${plain}      - Disable Autostart on OS Startup  │
│  ${blue}x-ui log${plain}          - Check logs                       │
│  ${blue}x-ui banlog${plain}       - Check Fail2ban ban logs          │
│  ${blue}x-ui update${plain}       - Update                           │
│  ${blue}x-ui legacy${plain}       - Legacy version                   │
│  ${blue}x-ui install${plain}      - Install                          │
│  ${blue}x-ui uninstall${plain}    - Uninstall                        │
└───────────────────────────────────────────────────────┘"
}

echo -e "${green}Running...${plain}"
install_base
install_x-ui $1
