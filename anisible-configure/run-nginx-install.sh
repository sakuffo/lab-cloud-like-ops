#!/bin/bash
# run-nginx-install.sh
# Wrapper script to run the Ansible playbook for nginx installation

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 [-l <limit>] [-k] [-K] [-v]"
    echo ""
    echo "Options:"
    echo "  -l  Limit execution to specific hosts (comma-separated)"
    echo "  -k  Ask for SSH password"
    echo "  -K  Ask for sudo password"
    echo "  -v  Verbose mode (can be used multiple times for more verbosity)"
    echo "  -h  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Run on all hosts in inventory"
    echo "  $0 -l vm1,vm2         # Run only on vm1 and vm2"
    echo "  $0 -K                 # Run with sudo password prompt"
    echo "  $0 -k -K              # Ask for both SSH and sudo passwords"
    echo "  $0 -vvv               # Run with maximum verbosity"
    exit 1
}

# Default values
LIMIT=""
ASK_PASS=""
ASK_BECOME_PASS=""
VERBOSE=""
EXTRA_ARGS=""

# Parse command line arguments
while getopts "l:kKvh" opt; do
    case ${opt} in
        l )
            LIMIT="--limit $OPTARG"
            ;;
        k )
            ASK_PASS="--ask-pass"
            ;;
        K )
            ASK_BECOME_PASS="--ask-become-pass"
            ;;
        v )
            VERBOSE="${VERBOSE}v"
            ;;
        h )
            usage
            ;;
        \? )
            usage
            ;;
    esac
done

# Add verbose flag if specified
if [ -n "$VERBOSE" ]; then
    EXTRA_ARGS="-${VERBOSE}"
fi

echo -e "${CYAN}==================== Ansible Nginx Installation ====================${NC}"
echo -e "${CYAN}Playbook: playbooks/install-nginx.yml${NC}"
echo -e "${CYAN}Inventory: inventory/vsphere_hosts.yml${NC}"
echo -e "${CYAN}=================================================================${NC}\n"

# Check if ansible is installed
if ! command -v ansible-playbook &> /dev/null; then
    echo -e "${RED}Error: ansible-playbook command not found${NC}"
    echo -e "${YELLOW}Please install Ansible first:${NC}"
    echo -e "  sudo apt update && sudo apt install ansible -y"
    exit 1
fi

# Check if inventory file exists
if [ ! -f "inventory/vsphere_hosts.yml" ]; then
    echo -e "${RED}Error: Inventory file not found${NC}"
    echo -e "${YELLOW}Please ensure inventory/vsphere_hosts.yml exists and contains your VM hosts${NC}"
    exit 1
fi

# Check if playbook exists
if [ ! -f "playbooks/install-nginx.yml" ]; then
    echo -e "${RED}Error: Playbook not found${NC}"
    echo -e "${YELLOW}Please ensure playbooks/install-nginx.yml exists${NC}"
    exit 1
fi

# Run the ansible playbook
echo -e "${GREEN}Running Ansible playbook...${NC}\n"

ansible-playbook \
    playbooks/install-nginx.yml \
    $LIMIT \
    $ASK_PASS \
    $ASK_BECOME_PASS \
    $EXTRA_ARGS

# Check exit status
if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}==================== Playbook Execution Complete ====================${NC}"
    echo -e "${GREEN}Nginx installation playbook completed successfully!${NC}"
    echo -e "${GREEN}====================================================================${NC}"
else
    echo -e "\n${RED}Playbook execution failed. Please check the error messages above.${NC}"
    exit 1
fi