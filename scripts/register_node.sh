#!/bin/bash

# Script to register a remote 3x-ui node with the master panel
# This script automates the process of adding a node with auto-filled External API Key

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
MASTER_HOST=""
MASTER_PORT="5050"
MASTER_PROTOCOL="http"
NODE_NAME=""
NODE_HOST=""
NODE_PORT="5050"
NODE_PROTOCOL="https"
ADMIN_USERNAME="admin"
ADMIN_PASSWORD=""
EXTERNAL_API_KEY=""
SKIP_SSL_VERIFY=false

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Register a remote 3x-ui node with the master panel.

OPTIONS:
    -m, --master-host HOST        Master panel hostname or IP (required)
    -p, --master-port PORT        Master panel port (default: 5050)
    -P, --master-protocol PROTO   Master panel protocol: http or https (default: http)
    -n, --node-name NAME          Node name (required)
    -h, --node-host HOST          Remote node hostname or IP (required)
    -o, --node-port PORT          Remote node port (default: 5050)
    -O, --node-protocol PROTO     Remote node protocol: http or https (default: https)
    -u, --username USER            Master panel admin username (default: admin)
    -w, --password PASS            Master panel admin password (required)
    -k, --api-key KEY              External API Key (if not provided, will be fetched from node)
    -s, --skip-ssl-verify          Skip SSL certificate verification
    --help                         Show this help message

EXAMPLES:
    # Basic usage
    $0 -m master.example.com -n "Node 1" -h node1.example.com -w admin123

    # With custom ports
    $0 -m master.example.com -p 8080 -n "Node 2" -h node2.example.com -o 2096 -w admin123

    # With explicit API key
    $0 -m master.example.com -n "Node 3" -h node3.example.com -w admin123 -k "MY_API_KEY"

EOF
}

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--master-host)
                MASTER_HOST="$2"
                shift 2
                ;;
            -p|--master-port)
                MASTER_PORT="$2"
                shift 2
                ;;
            -P|--master-protocol)
                MASTER_PROTOCOL="$2"
                shift 2
                ;;
            -n|--node-name)
                NODE_NAME="$2"
                shift 2
                ;;
            -h|--node-host)
                NODE_HOST="$2"
                shift 2
                ;;
            -o|--node-port)
                NODE_PORT="$2"
                shift 2
                ;;
            -O|--node-protocol)
                NODE_PROTOCOL="$2"
                shift 2
                ;;
            -u|--username)
                ADMIN_USERNAME="$2"
                shift 2
                ;;
            -w|--password)
                ADMIN_PASSWORD="$2"
                shift 2
                ;;
            -k|--api-key)
                EXTERNAL_API_KEY="$2"
                shift 2
                ;;
            -s|--skip-ssl-verify)
                SKIP_SSL_VERIFY=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                usage
                exit 1
                ;;
        esac
    done
}

# Function to check if required commands are available
check_dependencies() {
    local missing=()
    
    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing[*]}${NC}"
        echo "Please install them and try again."
        exit 1
    fi
}

# Function to login to master panel and get session
login_to_master() {
    local master_url="${MASTER_PROTOCOL}://${MASTER_HOST}:${MASTER_PORT}"
    local login_url="${master_url}/login"
    
    echo -e "${YELLOW}Logging in to master panel...${NC}"
    
    local curl_opts=()
    if [ "$SKIP_SSL_VERIFY" = true ]; then
        curl_opts+=("-k")
    fi
    
    # Login and get session cookie
    local response=$(curl -s -c /tmp/xui_cookie.txt -b /tmp/xui_cookie.txt \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"${ADMIN_USERNAME}\",\"password\":\"${ADMIN_PASSWORD}\"}" \
        "${curl_opts[@]}" \
        "${login_url}")
    
    if echo "$response" | jq -e '.success == true' > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Successfully logged in${NC}"
        return 0
    else
        echo -e "${RED}✗ Login failed${NC}"
        echo "Response: $response"
        return 1
    fi
}

# Function to get External API Key from node settings
get_external_api_key() {
    if [ -n "$EXTERNAL_API_KEY" ]; then
        echo "$EXTERNAL_API_KEY"
        return 0
    fi
    
    local node_url="${NODE_PROTOCOL}://${NODE_HOST}:${NODE_PORT}"
    local master_url="${MASTER_PROTOCOL}://${MASTER_HOST}:${MASTER_PORT}"
    
    echo -e "${YELLOW}Fetching External API Key from node settings...${NC}"
    
    local curl_opts=()
    if [ "$SKIP_SSL_VERIFY" = true ]; then
        curl_opts+=("-k")
    fi
    
    # Try to get settings from master panel (if we can access node through master)
    # Or we need to login to node panel directly
    # For now, we'll require the API key to be provided or set manually
    
    echo -e "${YELLOW}Note: External API Key not provided.${NC}"
    echo -e "${YELLOW}Please set it manually in the master panel after registration.${NC}"
    echo -e "${YELLOW}Or provide it with -k/--api-key option.${NC}"
    
    return 1
}

# Function to register node
register_node() {
    local master_url="${MASTER_PROTOCOL}://${MASTER_HOST}:${MASTER_PORT}"
    local api_url="${master_url}/panel/api/nodes"
    
    echo -e "${YELLOW}Registering node...${NC}"
    
    local curl_opts=()
    if [ "$SKIP_SSL_VERIFY" = true ]; then
        curl_opts+=("-k")
    fi
    
    # Build JSON payload
    local payload=$(jq -n \
        --arg name "$NODE_NAME" \
        --arg host "$NODE_HOST" \
        --argjson port "$NODE_PORT" \
        --arg protocol "$NODE_PROTOCOL" \
        --arg apiKey "$EXTERNAL_API_KEY" \
        --argjson enable true \
        '{
            name: $name,
            host: $host,
            port: $port,
            protocol: $protocol,
            apiKey: $apiKey,
            enable: $enable
        }')
    
    # Register node
    local response=$(curl -s -b /tmp/xui_cookie.txt \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "${curl_opts[@]}" \
        "${api_url}")
    
    if echo "$response" | jq -e '.success == true' > /dev/null 2>&1; then
        local node_id=$(echo "$response" | jq -r '.obj.id // empty')
        echo -e "${GREEN}✓ Node registered successfully${NC}"
        if [ -n "$node_id" ]; then
            echo -e "${GREEN}  Node ID: $node_id${NC}"
        fi
        return 0
    else
        echo -e "${RED}✗ Failed to register node${NC}"
        echo "Response: $response"
        return 1
    fi
}

# Main function
main() {
    parse_args "$@"
    
    # Validate required arguments
    if [ -z "$MASTER_HOST" ] || [ -z "$NODE_NAME" ] || [ -z "$NODE_HOST" ] || [ -z "$ADMIN_PASSWORD" ]; then
        echo -e "${RED}Error: Missing required arguments${NC}"
        usage
        exit 1
    fi
    
    # Check dependencies
    check_dependencies
    
    # Cleanup on exit
    trap "rm -f /tmp/xui_cookie.txt" EXIT
    
    # Login to master
    if ! login_to_master; then
        exit 1
    fi
    
    # Get External API Key (optional)
    if ! get_external_api_key > /tmp/api_key.txt 2>&1; then
        EXTERNAL_API_KEY=""
    else
        EXTERNAL_API_KEY=$(cat /tmp/api_key.txt)
        rm -f /tmp/api_key.txt
    fi
    
    # Register node
    if ! register_node; then
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}Registration complete!${NC}"
    if [ -z "$EXTERNAL_API_KEY" ]; then
        echo -e "${YELLOW}Remember to set the External API Key in the node settings.${NC}"
        echo -e "${YELLOW}Go to: Settings → Security → External API Key${NC}"
    fi
}

# Run main function
main "$@"

