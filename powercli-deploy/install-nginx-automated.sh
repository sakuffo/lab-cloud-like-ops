#!/bin/bash
# install-nginx-automated.sh
# Automated nginx installation script for Ubuntu VMs with better sudo handling

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 -h <host> -u <username> [-p <port>] [-k <keyfile>] [-s] [-f]"
    echo ""
    echo "Options:"
    echo "  -h  VM hostname or IP address (required)"
    echo "  -u  SSH username (required)"
    echo "  -p  SSH port (default: 22)"
    echo "  -k  SSH private key file (optional, will prompt for password if not provided)"
    echo "  -s  Skip nginx service start (optional)"
    echo "  -f  Skip firewall configuration (optional)"
    echo ""
    echo "Examples:"
    echo "  $0 -h 192.168.1.100 -u ubuntu"
    echo "  $0 -h ubuntu-vm.local -u ubuntu -k ~/.ssh/id_rsa"
    exit 1
}

# Default values
SSH_PORT=22
START_SERVICE=true
CONFIGURE_FIREWALL=true
SSH_KEY=""

# Parse command line arguments
while getopts "h:u:p:k:sf" opt; do
    case ${opt} in
        h )
            VM_HOST=$OPTARG
            ;;
        u )
            SSH_USER=$OPTARG
            ;;
        p )
            SSH_PORT=$OPTARG
            ;;
        k )
            SSH_KEY=$OPTARG
            ;;
        s )
            START_SERVICE=false
            ;;
        f )
            CONFIGURE_FIREWALL=false
            ;;
        \? )
            usage
            ;;
    esac
done

# Check required parameters
if [ -z "$VM_HOST" ] || [ -z "$SSH_USER" ]; then
    echo -e "${RED}Error: Missing required parameters${NC}"
    usage
fi

# Create installation script in current directory
TEMP_SCRIPT="./nginx-install-script.tmp.sh"

# Create installation script
cat > "$TEMP_SCRIPT" << 'EOF'
#!/bin/bash

# Update package list
echo "Updating package list..."
sudo apt-get update

# Install nginx
echo "Installing nginx..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx

# Get installation status
if [ $? -eq 0 ]; then
    echo "NGINX_INSTALL_SUCCESS=true"
else
    echo "NGINX_INSTALL_SUCCESS=false"
    exit 1
fi

# Start and enable nginx
if [ "$1" = "true" ]; then
    echo "Starting and enabling nginx service..."
    sudo systemctl start nginx
    sudo systemctl enable nginx
fi

# Configure firewall
if [ "$2" = "true" ]; then
    if which ufw >/dev/null 2>&1; then
        echo "Configuring firewall..."
        sudo ufw allow 'Nginx Full'
        sudo ufw allow 'OpenSSH'
        echo "y" | sudo ufw enable
    else
        echo "UFW not found, skipping firewall configuration"
    fi
fi

# Get nginx status and version
echo "NGINX_STATUS=$(sudo systemctl is-active nginx 2>/dev/null || echo 'unknown')"
echo "NGINX_VERSION=$(nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+')"

# Create test page
TEST_PAGE='<!DOCTYPE html>
<html>
<head>
    <title>Nginx Installation Success</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f0f0f0; }
        .container { background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; }
        .info { background-color: #e7f3ff; padding: 10px; border-radius: 4px; margin: 10px 0; }
        .success { color: #28a745; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Nginx Successfully Installed!</h1>
        <div class="info">
            <p class="success">✓ Installation completed via SSH automation</p>
            <p>Installation Date: '"$(date)"'</p>
        </div>
    </div>
</body>
</html>'

echo "$TEST_PAGE" | sudo tee /var/www/html/test.html > /dev/null

# Test nginx
if which curl >/dev/null 2>&1; then
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost/)
    echo "HTTP_RESPONSE=$HTTP_CODE"
fi

# Get IP addresses
echo "IP_ADDRESSES=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | tr '\n' ' ')"
EOF

# Main installation process
main() {
    echo -e "${CYAN}==================== Nginx Installation Script ====================${NC}"
    echo -e "${CYAN}Target VM: $VM_HOST${NC}"
    echo -e "${CYAN}SSH User: $SSH_USER${NC}"
    echo -e "${CYAN}SSH Port: $SSH_PORT${NC}"
    echo -e "${CYAN}=================================================================${NC}\n"
    
    # Build SCP and SSH commands
    if [ -n "$SSH_KEY" ]; then
        SCP_CMD="scp -i $SSH_KEY -P $SSH_PORT -o StrictHostKeyChecking=no"
        SSH_CMD="ssh -i $SSH_KEY -p $SSH_PORT -o StrictHostKeyChecking=no"
    else
        SCP_CMD="scp -P $SSH_PORT -o StrictHostKeyChecking=no"
        SSH_CMD="ssh -p $SSH_PORT -o StrictHostKeyChecking=no"
    fi
    
    # Test SSH connection
    echo -e "${GREEN}Testing SSH connection...${NC}"
    $SSH_CMD $SSH_USER@$VM_HOST "echo 'Connection successful'" >/dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to connect via SSH. Please check:${NC}"
        echo "  - VM is powered on and accessible"
        echo "  - SSH credentials are correct"
        echo "  - Network connectivity exists"
        exit 1
    fi
    
    echo -e "${GREEN}SSH connection successful${NC}\n"
    
    # Get OS information
    echo -e "${GREEN}Checking OS information...${NC}"
    OS_INFO=$($SSH_CMD $SSH_USER@$VM_HOST "lsb_release -d 2>/dev/null | cut -f2 || grep PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '\"'")
    echo -e "${CYAN}OS: $OS_INFO${NC}\n"
    
    # Copy installation script
    echo -e "${GREEN}Copying installation script to VM...${NC}"
    $SCP_CMD "$TEMP_SCRIPT" $SSH_USER@$VM_HOST:/tmp/nginx-install-script.sh
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to copy installation script${NC}"
        exit 1
    fi
    
    # Execute installation script
    echo -e "${GREEN}Starting nginx installation...${NC}\n"
    
    # Run the script and capture output
    INSTALL_OUTPUT=$($SSH_CMD $SSH_USER@$VM_HOST "chmod +x /tmp/nginx-install-script.sh && /tmp/nginx-install-script.sh $START_SERVICE $CONFIGURE_FIREWALL")
    
    # Parse output
    eval "$INSTALL_OUTPUT"
    
    # Clean up
    $SSH_CMD $SSH_USER@$VM_HOST "rm -f /tmp/nginx-install-script.sh" 2>/dev/null
    
    # Check installation success
    if [ "$NGINX_INSTALL_SUCCESS" != "true" ]; then
        echo -e "${RED}Nginx installation failed${NC}"
        exit 1
    fi
    
    # Display results
    echo -e "\n${GREEN}==================== Installation Complete ====================${NC}"
    echo -e "${GREEN}Nginx has been successfully installed!${NC}"
    echo -e "${CYAN}Version: ${NGINX_VERSION:-Unknown}${NC}"
    echo -e "${CYAN}Service Status: ${NGINX_STATUS:-Unknown}${NC}"
    
    if [ -n "$IP_ADDRESSES" ]; then
        echo -e "\n${YELLOW}Access nginx at:${NC}"
        for ip in $IP_ADDRESSES; do
            echo -e "  ${CYAN}Default page: http://$ip/${NC}"
            echo -e "  ${CYAN}Test page: http://$ip/test.html${NC}"
        done
    fi
    
    if [ "$HTTP_RESPONSE" = "200" ]; then
        echo -e "\n${GREEN}✓ Nginx is responding correctly (HTTP 200)${NC}"
    fi
    
    echo -e "${GREEN}=============================================================${NC}"
}

# Function to cleanup temp files
cleanup() {
    if [ -f "$TEMP_SCRIPT" ]; then
        rm -f "$TEMP_SCRIPT"
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Run main function
main