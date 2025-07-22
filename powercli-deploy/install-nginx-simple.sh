#!/bin/bash
# install-nginx-simple.sh
# Simple nginx installation script with better sudo handling

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 -h <host> -u <username> [-p <port>] [-k <keyfile>]"
    echo ""
    echo "Options:"
    echo "  -h  VM hostname or IP address (required)"
    echo "  -u  SSH username (required)"
    echo "  -p  SSH port (default: 22)"
    echo "  -k  SSH private key file (optional)"
    echo ""
    echo "Example:"
    echo "  $0 -h 192.168.1.100 -u ubuntu"
    exit 1
}

# Default values
SSH_PORT=22
SSH_KEY=""

# Parse command line arguments
while getopts "h:u:p:k:" opt; do
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
    SSH_CMD="ssh -i $SSH_KEY -p $SSH_PORT -o StrictHostKeyChecking=no"
else
    SSH_CMD="ssh -p $SSH_PORT -o StrictHostKeyChecking=no"
fi

echo -e "${CYAN}==================== Nginx Installation Script ====================${NC}"
echo -e "${CYAN}Target VM: $VM_HOST${NC}"
echo -e "${CYAN}SSH User: $SSH_USER${NC}"
echo -e "${CYAN}=================================================================${NC}\n"

# Test SSH connection
echo -e "${GREEN}Testing SSH connection...${NC}"
$SSH_CMD $SSH_USER@$VM_HOST "echo 'Connection successful'" >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to connect via SSH${NC}"
    exit 1
fi

echo -e "${GREEN}SSH connection successful${NC}\n"

# Ask for sudo password
echo -e "${YELLOW}Please enter the sudo password for user '$SSH_USER' on the remote VM:${NC}"
read -s SUDO_PASS
echo ""

# Create and execute installation commands
echo -e "${GREEN}Installing nginx on the remote VM...${NC}\n"

# Execute installation with sudo password
$SSH_CMD $SSH_USER@$VM_HOST << EOF
#!/bin/bash
# Pass sudo password via stdin

# Update package list
echo "Updating package list..."
echo '$SUDO_PASS' | sudo -S apt-get update

# Install nginx
echo -e "\nInstalling nginx..."
echo '$SUDO_PASS' | sudo -S DEBIAN_FRONTEND=noninteractive apt-get install -y nginx

# Start and enable nginx
echo -e "\nStarting nginx service..."
echo '$SUDO_PASS' | sudo -S systemctl start nginx
echo '$SUDO_PASS' | sudo -S systemctl enable nginx

# Configure firewall if ufw exists
if which ufw >/dev/null 2>&1; then
    echo -e "\nConfiguring firewall..."
    echo '$SUDO_PASS' | sudo -S ufw allow 'Nginx Full'
    echo '$SUDO_PASS' | sudo -S ufw allow 'OpenSSH'
fi

# Create test page
echo -e "\nCreating test page..."
TEST_PAGE='<!DOCTYPE html>
<html>
<head>
    <title>Nginx on $VM_HOST</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; text-align: center; }
        .success { color: #28a745; }
    </style>
</head>
<body>
    <h1 class="success">Nginx Successfully Installed!</h1>
    <p>Installation completed on $(date)</p>
</body>
</html>'

echo "\$TEST_PAGE" | sudo -S tee /var/www/html/test.html > /dev/null

# Get status
echo -e "\n=== Installation Status ==="
nginx -v 2>&1
echo "Service status: \$(systemctl is-active nginx)"
echo "IP addresses: \$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | tr '\n' ' ')"
EOF

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}==================== Installation Complete ====================${NC}"
    echo -e "${GREEN}Nginx has been successfully installed!${NC}"
    echo -e "${YELLOW}You can access nginx at:${NC}"
    echo -e "  ${CYAN}http://$VM_HOST/${NC}"
    echo -e "  ${CYAN}http://$VM_HOST/test.html${NC}"
    echo -e "${GREEN}=============================================================${NC}"
else
    echo -e "\n${RED}Installation failed. Please check the error messages above.${NC}"
    exit 1
fi