# Ansible Nginx Installation

This directory contains Ansible playbooks and configuration for installing nginx on Ubuntu VMs.

## Files

- `install-nginx.yml` - Main playbook that installs and configures nginx
- `inventory.ini` - Inventory file listing your Ubuntu VMs
- `ansible.cfg` - Ansible configuration file

## Prerequisites

1. Install Ansible on your control machine:
   ```bash
   # Ubuntu/Debian
   sudo apt update
   sudo apt install ansible

   # Or via pip
   pip install ansible
   ```

2. Ensure SSH access to your Ubuntu VMs

## Configuration

1. Edit `inventory.ini` to add your Ubuntu VMs:
   ```ini
   [ubuntu_vms]
   ubuntu-vm ansible_host=YOUR_VM_IP ansible_user=ubuntu
   ```

2. Configure authentication in `inventory.ini`:
   - For SSH key: `ansible_ssh_private_key_file=~/.ssh/id_rsa`
   - For password: `ansible_ssh_pass=your_password`

## Usage

### Test connectivity
```bash
ansible ubuntu_vms -m ping
```

### Run the playbook
```bash
# With SSH key authentication
ansible-playbook install-nginx.yml

# With password authentication
ansible-playbook install-nginx.yml --ask-pass --ask-become-pass

# Run on specific host
ansible-playbook install-nginx.yml --limit ubuntu-vm

# Dry run (check mode)
ansible-playbook install-nginx.yml --check
```

### Verify installation
After running the playbook, nginx will be accessible at:
- Default page: `http://YOUR_VM_IP/`
- Ansible test page: `http://YOUR_VM_IP/ansible-test.html`

## Features

The playbook will:
- Update apt package cache
- Install nginx
- Start and enable nginx service
- Create a custom test page with system information
- Configure UFW firewall rules (if UFW is installed)
- Display installation results

## Troubleshooting

1. **Connection issues**: Ensure SSH access works manually first
   ```bash
   ssh ubuntu@YOUR_VM_IP
   ```

2. **Permission denied**: Make sure sudo password is correct
   ```bash
   ansible-playbook install-nginx.yml --ask-become-pass
   ```

3. **Python not found**: The playbook assumes Python 3 is installed on Ubuntu VMs