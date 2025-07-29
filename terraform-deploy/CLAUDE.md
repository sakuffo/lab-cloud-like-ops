# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Terraform project for provisioning Ubuntu VMs with nginx on vSphere infrastructure. The configuration creates a single VM from an Ubuntu 22.04 template and automatically installs nginx using remote provisioning.

## Common Commands

```bash
# Initialize Terraform (required before first use)
terraform init

# Validate configuration
terraform validate

# Format Terraform files
terraform fmt

# Plan infrastructure changes
terraform plan

# Apply infrastructure changes
terraform apply

# Destroy infrastructure
terraform destroy

# Show current state
terraform show

# List resources in state
terraform state list
```

## Architecture

The project uses the vSphere provider to manage virtual infrastructure:

- **Provider Configuration**: Uses hashicorp/vsphere provider v2.0+ with SSL verification disabled for self-signed certificates
- **Resource Creation**: Creates a single `vsphere_virtual_machine` resource cloned from an Ubuntu template
- **Post-Deployment**: Automatically installs and configures nginx via SSH provisioning
- **Network Configuration**: Uses DHCP for IP assignment
- **Outputs**: Provides VM IP address, name, and nginx URL after deployment

## Variable Configuration

All sensitive and environment-specific values are defined as variables in `main.tf` with defaults in `terraform.tfvars`. Key variables include:
- vSphere connection details (server, credentials)
- Infrastructure targets (datacenter, cluster, datastore, network)
- VM specifications (CPU, memory, disk size)
- SSH credentials for provisioning

## Security Considerations

- The `vsphere_password` and `ssh_password` variables are marked as sensitive
- SSL verification is currently disabled (`allow_unverified_ssl = true`)
- Firewall rules are configured to allow nginx traffic