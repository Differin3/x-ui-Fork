#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

# Don't edit this config
b_source="${BASH_SOURCE[0]}"
while [ -h "$b_source" ]; do
	b_dir="$(cd -P "$(dirname "$b_source")" >/dev/null 2>&1 && pwd || pwd -P)"
	b_source="$(readlink "$b_source")"
	[[ $b_source != /* ]] && b_source="$b_dir/$b_source"
done
cur_dir="$(cd -P "$(dirname "$b_source")" >/dev/null 2>&1 && pwd || pwd -P)"
script_name=$(basename "$0")

# Check command exist function
_command_exists() {
	type "$1" &>/dev/null
}

# Fail, log and exit script function
_fail() {
	local msg=${1}
	echo -e "${red}${msg}${plain}"
	exit 2
}

# check root
[[ $EUID -ne 0 ]] && _fail "FATAL ERROR: Please run this script with root privilege."

if _command_exists wget; then
	wget_bin=$(which wget)
else
	_fail "ERROR: Command 'wget' not found."
fi

if _command_exists curl; then
	curl_bin=$(which curl)
else
	_fail "ERROR: Command 'curl' not found."
fi

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
	source /etc/os-release
	release=$ID
elif [[ -f /usr/lib/os-release ]]; then
	source /usr/lib/os-release
	release=$ID
else
	_fail "Failed to check the system OS, please contact the author!"
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
	*) echo -e "${red}Unsupported CPU architecture!${plain}" && rm -f "${cur_dir}/${script_name}" >/dev/null 2>&1 && exit 2;;
	esac
}

echo "Arch: $(arch)"

install_base() {
	echo -e "${green}Updating and install dependency packages...${plain}"
	case "${release}" in
	ubuntu | debian | armbian)
		apt-get update >/dev/null 2>&1 && apt-get install -y -q wget curl tar tzdata unzip >/dev/null 2>&1
		;;
	centos | rhel | almalinux | rocky | ol)
		yum -y update >/dev/null 2>&1 && yum install -y -q wget curl tar tzdata unzip >/dev/null 2>&1
		;;
	fedora | amzn | virtuozzo)
		dnf -y update >/dev/null 2>&1 && dnf install -y -q wget curl tar tzdata unzip >/dev/null 2>&1
		;;
	arch | manjaro | parch)
		pacman -Syu >/dev/null 2>&1 && pacman -Syu --noconfirm wget curl tar tzdata unzip >/dev/null 2>&1
		;;
	opensuse-tumbleweed | opensuse-leap)
		zypper refresh >/dev/null 2>&1 && zypper -q install -y wget curl tar timezone unzip >/dev/null 2>&1
		;;
	alpine)
		apk update >/dev/null 2>&1 && apk add wget curl tar tzdata unzip >/dev/null 2>&1
		;;
	*)
		apt-get update >/dev/null 2>&1 && apt install -y -q wget curl tar tzdata unzip >/dev/null 2>&1
		;;
	esac
}

config_after_update() {
	echo -e "${yellow}x-ui settings:${plain}"
	/usr/local/x-ui/x-ui setting -show true
	/usr/local/x-ui/x-ui migrate
}

update_x-ui() {
	cd /usr/local/

	if [ -f "/usr/local/x-ui/x-ui" ]; then
		current_xui_version=$(/usr/local/x-ui/x-ui -v)
		echo -e "${green}Current x-ui version: ${current_xui_version}${plain}"
	else
		_fail "ERROR: Current x-ui version: unknown"
	fi

	echo -e "${green}Downloading new x-ui version (Differin3 fork)...${plain}"

	# Try to fetch latest release from Differin3 fork first
	tag_version=$(${curl_bin} -Ls "https://api.github.com/repos/Differin3/x-ui-Fork/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
	if [[ ! -n "$tag_version" ]]; then
		echo -e "${yellow}Trying to fetch version with IPv4...${plain}"
		tag_version=$(${curl_bin} -4 -Ls "https://api.github.com/repos/Differin3/x-ui-Fork/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
	fi

	build_from_source=false
	if [[ -n "$tag_version" ]]; then
		echo -e "Got x-ui latest fork version: ${tag_version}, beginning the installation..."
		${wget_bin} -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/Differin3/x-ui-Fork/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz 2>/dev/null || ${wget_bin} --inet4-only -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/Differin3/x-ui-Fork/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz 2>/dev/null
		if [[ $? -ne 0 ]]; then
			echo -e "${yellow}Fork release not available for this arch; will build from source...${plain}"
			build_from_source=true
		fi
	else
		echo -e "${yellow}Could not get fork release. Falling back to build from main branch...${plain}"
		build_from_source=true
	fi

	if [[ -e /usr/local/x-ui/ ]]; then
		echo -e "${green}Stopping x-ui...${plain}"
		if [[ $release == "alpine" ]]; then
			if [ -f "/etc/init.d/x-ui" ]; then
				rc-service x-ui stop >/dev/null 2>&1
				rc-update del x-ui >/dev/null 2>&1
				echo -e "${green}Removing old service unit version...${plain}"
				rm -f /etc/init.d/x-ui >/dev/null 2>&1
			else
				rm x-ui-linux-$(arch).tar.gz -f >/dev/null 2>&1
				_fail "ERROR: x-ui service unit not installed."
			fi
		else
			if [ -f "/etc/systemd/system/x-ui.service" ]; then
				systemctl stop x-ui >/dev/null 2>&1
				systemctl disable x-ui >/dev/null 2>&1
				echo -e "${green}Removing old systemd unit version...${plain}"
				rm /etc/systemd/system/x-ui.service -f >/dev/null 2>&1
				systemctl daemon-reload >/dev/null 2>&1
			else
				rm x-ui-linux-$(arch).tar.gz -f >/dev/null 2>&1
				_fail "ERROR: x-ui systemd unit not installed."
			fi
		fi
		echo -e "${green}Removing old x-ui version...${plain}"
		rm /usr/bin/x-ui -f >/dev/null 2>&1
		rm /usr/local/x-ui/x-ui.service -f >/dev/null 2>&1
		rm /usr/local/x-ui/x-ui -f >/dev/null 2>&1
		rm /usr/local/x-ui/x-ui.sh -f >/dev/null 2>&1
		echo -e "${green}Removing old xray version...${plain}"
		rm /usr/local/x-ui/bin/xray-linux-amd64 -f >/dev/null 2>&1
		echo -e "${green}Removing old README and LICENSE file...${plain}"
		rm /usr/local/x-ui/bin/README.md -f >/dev/null 2>&1
		rm /usr/local/x-ui/bin/LICENSE -f >/dev/null 2>&1
	else
		rm x-ui-linux-$(arch).tar.gz -f >/dev/null 2>&1
		_fail "ERROR: x-ui not installed."
	fi

	if [[ "$build_from_source" == true ]]; then
		echo -e "${green}Building from main branch...${plain}"
		cd /usr/local || _fail "Cannot cd to /usr/local"
		rm -rf x-ui-source >/dev/null 2>&1
		echo -e "Cloning repository..."
		git clone --depth 1 https://github.com/Differin3/x-ui-Fork.git x-ui-source >/dev/null 2>&1 || _fail "Failed to clone Differin3/x-ui-Fork"
		cd x-ui-source || _fail "Source dir missing"
		# install minimal build deps
		if ! command -v go >/dev/null 2>&1; then
			echo -e "${yellow}Installing Go (build dependency)...${plain}"
			case "${release}" in
			ubuntu|debian|armbian)
				apt-get update >/dev/null 2>&1 && apt-get install -y -q golang git >/dev/null 2>&1 ;;
			centos|rhel|almalinux|rocky|ol)
				yum -y install golang git >/dev/null 2>&1 ;;
			fedora|amzn)
				dnf -y install golang git >/dev/null 2>&1 ;;
			arch|manjaro|parch)
				pacman -Syu --noconfirm go git >/dev/null 2>&1 ;;
			alpine)
				apk add go git >/dev/null 2>&1 ;;
			*)
				echo -e "${yellow}Unknown OS, attempting golang install via package manager...${plain}"
				apt-get update >/dev/null 2>&1 && apt-get install -y -q golang git >/dev/null 2>&1 || true ;;
			esac
		fi
		echo -e "Building x-ui..."
		go build -o x-ui . >/dev/null 2>&1 || _fail "Go build failed"
		# prepare target layout
		rm -rf /usr/local/x-ui >/dev/null 2>&1
		mkdir -p /usr/local/x-ui/bin >/dev/null 2>&1
		mkdir -p /usr/local/x-ui/web/translation >/dev/null 2>&1
		cp -r web /usr/local/x-ui/ >/dev/null 2>&1
		cp -r web/translation/*.toml /usr/local/x-ui/web/translation/ >/dev/null 2>&1
		cp -r web/html /usr/local/x-ui/web/ >/dev/null 2>&1
		cp -r database /usr/local/x-ui/ >/dev/null 2>&1
		cp -r config /usr/local/x-ui/ 2>/dev/null || true
		cp -r x-ui.service /usr/local/x-ui/ 2>/dev/null || true
		cp x-ui /usr/local/x-ui/x-ui >/dev/null 2>&1
	else
		echo -e "${green}Installing new x-ui version from release...${plain}"
		tar zxvf x-ui-linux-$(arch).tar.gz >/dev/null 2>&1
		rm x-ui-linux-$(arch).tar.gz -f >/dev/null 2>&1
		cd x-ui >/dev/null 2>&1
		chmod +x x-ui >/dev/null 2>&1
		# ensure target tree
		mkdir -p /usr/local/x-ui/bin >/dev/null 2>&1
		cp -r . /usr/local/x-ui/ >/dev/null 2>&1
	fi

	# Ensure Xray-core exists in bin/
	echo -e "${green}Ensuring Xray-core binary is present...${plain}"
	cd /usr/local/x-ui || _fail "x-ui install dir missing"
	mkdir -p bin >/dev/null 2>&1
	cpu_arch=$(arch)
	xray_target="bin/xray-linux-${cpu_arch}"
	if [[ "${cpu_arch}" == "armv5" || "${cpu_arch}" == "armv6" || "${cpu_arch}" == "armv7" ]]; then
		xray_target="bin/xray-linux-arm"
	fi
	if [[ ! -x "${xray_target}" ]]; then
		echo -e "${yellow}Xray binary missing, downloading...${plain}"
		xr_ver=$(${curl_bin} -Ls https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
		xr_pkg_arch=${cpu_arch}
		[[ "${cpu_arch}" == armv5 || "${cpu_arch}" == armv6 || "${cpu_arch}" == armv7 ]] && xr_pkg_arch=arm
		mkdir -p /tmp/xray >/dev/null 2>&1
		${wget_bin} -O /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${xr_ver}/Xray-linux-${xr_pkg_arch}.zip" >/dev/null 2>&1 \
		|| ${curl_bin} -4 -Lso /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${xr_ver}/Xray-linux-${xr_pkg_arch}.zip" >/dev/null 2>&1 \
		|| ${wget_bin} -O /tmp/xray.zip "https://ghproxy.com/https://github.com/XTLS/Xray-core/releases/download/${xr_ver}/Xray-linux-${xr_pkg_arch}.zip" >/dev/null 2>&1 \
		|| true
		unzip -o /tmp/xray.zip -d /tmp/xray >/dev/null 2>&1 || true
		if [[ -f /tmp/xray/xray ]]; then
			cp /tmp/xray/xray "${xray_target}" >/dev/null 2>&1
			chmod +x "${xray_target}" >/dev/null 2>&1
		else
			echo -e "${red}Failed to fetch Xray-core. You may install it manually later.${plain}"
		fi
		rm -rf /tmp/xray /tmp/xray.* >/dev/null 2>&1
	fi

	# Ensure geoip.dat and geosite.dat exist (multi-mirror fallbacks)
	mkdir -p /usr/local/x-ui/bin >/dev/null 2>&1
	if [[ ! -s /usr/local/x-ui/bin/geoip.dat ]]; then
		echo -e "${green}Fetching geoip.dat ...${plain}"
		${wget_bin} -O /usr/local/x-ui/bin/geoip.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" >/dev/null 2>&1 \
		|| ${curl_bin} -4 -Lso /usr/local/x-ui/bin/geoip.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" >/dev/null 2>&1 \
		|| ${wget_bin} -O /usr/local/x-ui/bin/geoip.dat "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geoip.dat" >/dev/null 2>&1 \
		|| ${wget_bin} -O /usr/local/x-ui/bin/geoip.dat "https://ghproxy.com/https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" >/dev/null 2>&1 \
		|| true
		chmod 644 /usr/local/x-ui/bin/geoip.dat >/dev/null 2>&1 || true
	fi
	if [[ ! -s /usr/local/x-ui/bin/geosite.dat ]]; then
		echo -e "${green}Fetching geosite.dat ...${plain}"
		${wget_bin} -O /usr/local/x-ui/bin/geosite.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" >/dev/null 2>&1 \
		|| ${curl_bin} -4 -Lso /usr/local/x-ui/bin/geosite.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" >/dev/null 2>&1 \
		|| ${wget_bin} -O /usr/local/x-ui/bin/geosite.dat "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat" >/dev/null 2>&1 \
		|| ${wget_bin} -O /usr/local/x-ui/bin/geosite.dat "https://ghproxy.com/https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" >/dev/null 2>&1 \
		|| true
		chmod 644 /usr/local/x-ui/bin/geosite.dat >/dev/null 2>&1 || true
	fi

	echo -e "${green}Downloading and installing x-ui.sh script from Differin3...${plain}"
	${wget_bin} -O /usr/bin/x-ui https://raw.githubusercontent.com/Differin3/x-ui-Fork/main/x-ui.sh >/dev/null 2>&1 || ${wget_bin} --inet4-only -O /usr/bin/x-ui https://raw.githubusercontent.com/Differin3/x-ui-Fork/main/x-ui.sh >/dev/null 2>&1 || _fail "ERROR: Failed to download x-ui.sh script"

	chmod +x /usr/bin/x-ui >/dev/null 2>&1

	echo -e "${green}Changing owner...${plain}"
	chown -R root:root /usr/local/x-ui >/dev/null 2>&1

	if [ -f "/usr/local/x-ui/bin/config.json" ]; then
		echo -e "${green}Changing on config file permissions...${plain}"
		chmod 640 /usr/local/x-ui/bin/config.json >/dev/null 2>&1
	fi

	if [[ $release == "alpine" ]]; then
		echo -e "${green}Downloading and installing startup unit x-ui.rc...${plain}"
		${wget_bin} -O /etc/init.d/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.rc >/dev/null 2>&1
		if [[ $? -ne 0 ]]; then
			${wget_bin} --inet4-only -O /etc/init.d/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.rc >/dev/null 2>&1
			if [[ $? -ne 0 ]]; then
				_fail "ERROR: Failed to download startup unit x-ui.rc, please be sure that your server can access GitHub"
			fi
		fi
		chmod +x /etc/init.d/x-ui >/dev/null 2>&1
		chown root:root /etc/init.d/x-ui >/dev/null 2>&1
		rc-update add x-ui >/dev/null 2>&1
		rc-service x-ui start >/dev/null 2>&1
	else
		echo -e "${green}Installing systemd unit...${plain}"
		if [[ -f x-ui.service ]]; then
			cp -f x-ui.service /etc/systemd/system/ >/dev/null 2>&1
		elif [[ -f /usr/local/x-ui/x-ui.service ]]; then
			cp -f /usr/local/x-ui/x-ui.service /etc/systemd/system/ >/dev/null 2>&1
		else
			echo -e "${yellow}Systemd unit not found in package, proceeding...${plain}"
		fi
		chown root:root /etc/systemd/system/x-ui.service >/dev/null 2>&1
		systemctl daemon-reload >/dev/null 2>&1
		systemctl enable x-ui >/dev/null 2>&1
		systemctl start x-ui >/dev/null 2>&1
	fi

	config_after_update

	echo -e "${green}x-ui ${tag_version}${plain} updating finished, it is running now..."
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
update_x-ui $1
