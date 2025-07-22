#!/bin/bash
# install-nginx-ssh.sh
# Bash script to install nginx on Ubuntu VM via SSH

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
    echo "  -k  SSH private key file (optional, will use password if not provided)"
    echo "  -s  Skip nginx service start (optional)"
    echo "  -f  Skip firewall configuration (optional)"
    echo ""
    echo "Examples:"
    echo "  $0 -h 192.168.1.100 -u ubuntu"
    echo "  $0 -h ubuntu-vm.local -u ubuntu -k ~/.ssh/id_rsa"
    echo "  $0 -h 192.168.1.100 -u ubuntu -p 2222 -s -f"
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

# Build SSH command
if [ -n "$SSH_KEY" ]; then
    SSH_CMD="ssh -i $SSH_KEY -p $SSH_PORT -o StrictHostKeyChecking=no -t"
    SCP_CMD="scp -i $SSH_KEY -P $SSH_PORT -o StrictHostKeyChecking=no"
else
    SSH_CMD="ssh -p $SSH_PORT -o StrictHostKeyChecking=no -t"
    SCP_CMD="scp -P $SSH_PORT -o StrictHostKeyChecking=no"
fi

# Function to execute remote command
execute_remote() {
    local command=$1
    local description=$2
    
    echo -e "${GREEN}${description}...${NC}"
    $SSH_CMD $SSH_USER@$VM_HOST "$command"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to execute: $description${NC}"
        return 1
    fi
    return 0
}

# Function to check SSH connectivity
check_ssh_connection() {
    echo -e "${GREEN}Testing SSH connection to $VM_HOST...${NC}"
    $SSH_CMD $SSH_USER@$VM_HOST "echo 'SSH connection successful'" > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to connect to $VM_HOST via SSH${NC}"
        echo -e "${YELLOW}Please ensure:${NC}"
        echo "  - The VM is powered on and accessible"
        echo "  - SSH service is running on the VM"
        echo "  - Credentials are correct"
        echo "  - Network connectivity exists"
        exit 1
    fi
    echo -e "${GREEN}SSH connection successful${NC}"
}

# Main installation process
main() {
    echo -e "${CYAN}==================== Nginx Installation Script ====================${NC}"
    echo -e "${CYAN}Target VM: $VM_HOST${NC}"
    echo -e "${CYAN}SSH User: $SSH_USER${NC}"
    echo -e "${CYAN}SSH Port: $SSH_PORT${NC}"
    echo -e "${CYAN}=================================================================${NC}\n"
    
    # Check SSH connection
    check_ssh_connection
    
    # Get OS information
    echo -e "\n${GREEN}Checking OS information...${NC}"
    OS_INFO=$($SSH_CMD $SSH_USER@$VM_HOST "lsb_release -d 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME")
    echo -e "${CYAN}OS: $OS_INFO${NC}"
    
    # Update package list
    if ! execute_remote "sudo apt-get update" "Updating package list"; then
        exit 1
    fi
    
    # Install nginx
    if ! execute_remote "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx" "Installing nginx"; then
        exit 1
    fi
    
    # Start and enable nginx service
    if [ "$START_SERVICE" = true ]; then
        if ! execute_remote "sudo systemctl start nginx && sudo systemctl enable nginx" "Starting and enabling nginx service"; then
            echo -e "${YELLOW}Warning: Failed to start nginx service${NC}"
        fi
    fi
    
    # Configure firewall
    if [ "$CONFIGURE_FIREWALL" = true ]; then
        # Check if ufw is installed
        UFW_CHECK=$($SSH_CMD $SSH_USER@$VM_HOST "which ufw 2>/dev/null")
        
        if [ -n "$UFW_CHECK" ]; then
            echo -e "${GREEN}Configuring firewall...${NC}"
            execute_remote "sudo ufw allow 'Nginx Full' && sudo ufw allow 'OpenSSH' && echo 'y' | sudo ufw enable" "Configuring firewall for nginx"
        else
            echo -e "${YELLOW}UFW firewall not found, skipping firewall configuration${NC}"
        fi
    fi
    
    # Verify nginx installation
    echo -e "\n${GREEN}Verifying nginx installation...${NC}"
    NGINX_STATUS=$($SSH_CMD $SSH_USER@$VM_HOST "sudo systemctl is-active nginx 2>/dev/null")
    NGINX_VERSION=$($SSH_CMD $SSH_USER@$VM_HOST "nginx -v 2>&1")
    
    # Create test page
    echo -e "${GREEN}Creating test page...${NC}"
    
    TEST_PAGE_CONTENT='<!DOCTYPE html>
<html>
<head>
    <title>Nginx on '"$VM_HOST"'</title>
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
        <h1>Welcome to Nginx!</h1>
        <div class="info">
            <p class="success">Installation successful!</p>
            <p>This page confirms that nginx has been successfully installed via SSH automation.</p>
            <p>Host: '"$VM_HOST"'</p>
            <p>Installed by: '"$SSH_USER"'</p>
            <p>Installation Date: '"$(date)"'</p>
        </div>
    </div>
</body>
</html>'
    
    $SSH_CMD $SSH_USER@$VM_HOST "echo '$TEST_PAGE_CONTENT' | sudo tee /var/www/html/test.html > /dev/null"
    
    # Get IP addresses
    echo -e "\n${GREEN}Getting network information...${NC}"
    IP_ADDRESSES=$($SSH_CMD $SSH_USER@$VM_HOST "ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1'")
    
    # Display results
    echo -e "\n${GREEN}==================== Installation Complete ====================${NC}"
    echo -e "${GREEN}Nginx has been successfully installed!${NC}"
    echo -e "${CYAN}Version: $NGINX_VERSION${NC}"
    echo -e "${CYAN}Service Status: $NGINX_STATUS${NC}"
    echo -e "\n${YELLOW}Access nginx at:${NC}"
    
    if [ -n "$IP_ADDRESSES" ]; then
        for ip in $IP_ADDRESSES; do
            echo -e "  ${CYAN}Default page: http://$ip/${NC}"
            echo -e "  ${CYAN}Test page: http://$ip/test.html${NC}"
        done
    else
        echo -e "  ${CYAN}Default page: http://$VM_HOST/${NC}"
        echo -e "  ${CYAN}Test page: http://$VM_HOST/test.html${NC}"
    fi
    
    echo -e "${GREEN}=============================================================${NC}"
    
    # Test nginx response
    echo -e "\n${GREEN}Testing nginx response...${NC}"
    CURL_CHECK=$($SSH_CMD $SSH_USER@$VM_HOST "which curl 2>/dev/null")
    
    if [ -n "$CURL_CHECK" ]; then
        HTTP_RESPONSE=$($SSH_CMD $SSH_USER@$VM_HOST "curl -s -o /dev/null -w '%{http_code}' http://localhost/")
        if [ "$HTTP_RESPONSE" = "200" ]; then
            echo -e "${GREEN}✓ Nginx is responding correctly (HTTP $HTTP_RESPONSE)${NC}"
        else
            echo -e "${YELLOW}⚠ Nginx returned HTTP $HTTP_RESPONSE${NC}"
        fi
    fi
}

# Run main function
main