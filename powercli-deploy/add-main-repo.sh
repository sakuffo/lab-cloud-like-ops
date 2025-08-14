#!/bin/bash

# Script to add "main" component to existing Ubuntu sources
# This script modifies the existing ubuntu.sources file to include main repository

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}This script must be run with sudo${NC}"
    exit 1
fi

# Check if the file exists
if [ ! -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    echo -e "${RED}File /etc/apt/sources.list.d/ubuntu.sources not found!${NC}"
    exit 1
fi

# Backup the existing file
echo -e "${YELLOW}Creating backup of ubuntu.sources...${NC}"
cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak.$(date +%Y%m%d_%H%M%S)

# Modify the file to add "main" to Components lines
echo -e "${GREEN}Adding 'main' component to repository entries...${NC}"

# Use sed to replace "Components: multiverse" with "Components: main multiverse"
# This handles both entries in the file
sed -i 's/^Components: multiverse$/Components: main multiverse/g' /etc/apt/sources.list.d/ubuntu.sources

# Show the changes
echo -e "${GREEN}Modified content:${NC}"
echo "----------------------------------------"
cat /etc/apt/sources.list.d/ubuntu.sources
echo "----------------------------------------"

# Update package lists
echo -e "${GREEN}Updating package lists...${NC}"
apt update

echo -e "${GREEN}Done! The main repository has been added successfully.${NC}"
echo -e "${YELLOW}Both archive.ubuntu.com and security.ubuntu.com now include 'main' component.${NC}"