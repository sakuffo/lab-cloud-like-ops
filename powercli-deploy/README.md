# PowerCLI Ubuntu VM Deployment

A PowerShell script that automates the deployment of Ubuntu Server virtual machines on VMware vSphere infrastructure using PowerCLI. The script handles ISO download, content library management, and VM provisioning with cloud-init support.

## Features

- **Automated ISO Download**: Downloads Ubuntu Server ISO directly from official Ubuntu releases
- **Content Library Integration**: Creates and manages VMware Content Library for ISO storage
- **Flexible VM Placement**: Deploy to specific clusters or ESXi hosts
- **Cloud-Init Support**: Includes cloud-init configuration for automated Ubuntu setup
- **Customizable VM Resources**: Configure CPU, memory, and disk specifications
- **Network Configuration**: Automatic network adapter setup with specified port groups

## Prerequisites

- **VMware PowerCLI**: Install using PowerShell:
  ```powershell
  Install-Module -Name VMware.PowerCLI -Scope CurrentUser
  ```
- **vSphere Access**: Valid credentials for vCenter Server
- **Network Access**: Internet connectivity for Ubuntu ISO download
- **vSphere Requirements**:
  - vCenter Server 6.7 or later
  - ESXi 6.7 or later
  - Sufficient datastore space for ISO and VM

## Installation

1. Clone or download this repository:
   ```bash
   git clone <repository-url>
   cd powercli-deploy
   ```

2. Ensure all files are in the same directory:
   - `Deploy-UbuntuVM.ps1` - Main deployment script
   - `user-data` - Cloud-init configuration
   - `meta-data` - Cloud-init metadata
   - `install-nginx-simple.sh` - Optional post-deployment script

## Usage

### Basic Deployment

Deploy a VM to a specific cluster:
```powershell
.\Deploy-UbuntuVM.ps1 -vCenterServer "vcenter.domain.com" -VMName "Ubuntu-VM-01" -ClusterName "Production-Cluster"
```

Deploy a VM to a specific ESXi host:
```powershell
.\Deploy-UbuntuVM.ps1 -vCenterServer "vcenter.domain.com" -VMName "Ubuntu-VM-02" -ESXiHost "esxi01.domain.com"
```

### Advanced Usage

Full parameter customization:
```powershell
.\Deploy-UbuntuVM.ps1 `
    -vCenterServer "vcenter.domain.com" `
    -VMName "Ubuntu-Web-Server" `
    -ClusterName "Web-Cluster" `
    -DatastoreName "SSD-Datastore-01" `
    -NetworkName "VM-Network-VLAN100" `
    -MemoryGB 8 `
    -NumCPU 4 `
    -DiskGB 100 `
    -UbuntuVersion "24.04.2"
```

### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-vCenterServer` | Yes | - | vCenter Server FQDN or IP address |
| `-VMName` | Yes | - | Name for the new virtual machine |
| `-ClusterName` | No* | - | Target cluster name (use this OR ESXiHost) |
| `-ESXiHost` | No* | - | Target ESXi host (use this OR ClusterName) |
| `-DatastoreName` | No | "vsan-mgmt-01a" | Datastore for VM files |
| `-NetworkName` | No | "vmmgmt-vds01-mgmt-01a" | Network port group name |
| `-MemoryGB` | No | 4 | VM memory in gigabytes (1-128) |
| `-NumCPU` | No | 2 | Number of vCPUs (1-128) |
| `-DiskGB` | No | 20 | VM disk size in gigabytes (1-62000) |
| `-ISOPath` | No | "./ubuntu.iso" | Local path for downloaded ISO |
| `-UbuntuVersion` | No | "24.04.2" | Ubuntu version to download |
| `-UbuntuURL` | No | (see script) | Custom Ubuntu ISO download URL |

*Either `-ClusterName` or `-ESXiHost` must be specified

## Cloud-Init Configuration

The included `user-data` file provides automated Ubuntu configuration:

- **Default User**: ubuntu (password: ubuntu)
- **SSH**: Enabled with password authentication
- **Packages**: curl, wget, vim, net-tools pre-installed
- **Sudo**: Passwordless sudo configured
- **Network**: DHCP on primary interface

### Customizing Cloud-Init

Edit `user-data` to customize the deployment:

```yaml
#cloud-config
autoinstall:
  identity:
    hostname: your-hostname
    username: your-username
    password: your-encrypted-password
  packages:
    - nginx
    - docker.io
    - python3
```

Generate encrypted passwords:
```bash
openssl passwd -6 -salt xyz YourPassword
```

## Script Workflow

1. **Connection**: Establishes connection to vCenter Server
2. **ISO Download**: Downloads Ubuntu ISO if not present locally
3. **Content Library**: Creates/uses content library for ISO storage
4. **ISO Upload**: Uploads ISO to content library
5. **VM Creation**: Creates VM with specified resources
6. **Configuration**: Sets boot order, mounts ISO
7. **Power On**: Starts VM for Ubuntu installation

## Post-Deployment

After VM creation:

1. **Console Access**: Connect via vSphere Console to complete installation
2. **Cloud-Init**: Ubuntu will auto-configure based on user-data
3. **SSH Access**: Once booted, SSH using configured credentials
4. **Further Configuration**: Run additional scripts like `install-nginx-simple.sh`

### Running Post-Deployment Scripts

```bash
# Copy script to VM
scp install-nginx-simple.sh ubuntu@vm-ip:/tmp/

# Execute on VM
ssh ubuntu@vm-ip 'bash /tmp/install-nginx-simple.sh'
```

## Troubleshooting

### Common Issues

**PowerCLI Not Found**
```powershell
# Install PowerCLI
Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force

# Import module
Import-Module VMware.PowerCLI
```

**Certificate Warnings**
```powershell
# Disable certificate validation (development only)
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
```

**Connection Failed**
- Verify vCenter Server address and credentials
- Check network connectivity
- Ensure firewall allows port 443

**VM Creation Failed**
- Verify sufficient resources (CPU, memory, storage)
- Check permissions on cluster/host
- Ensure network port group exists

**ISO Download Failed**
- Check internet connectivity
- Verify Ubuntu URL is accessible
- Ensure sufficient local disk space

### Debug Mode

Enable verbose output:
```powershell
$VerbosePreference = "Continue"
.\Deploy-UbuntuVM.ps1 -vCenterServer "vcenter.local" -VMName "Test-VM" -ClusterName "Cluster-01"
```

## Security Considerations

- **Credentials**: Use secure credential storage, not plaintext
- **Passwords**: Change default passwords immediately after deployment
- **Network**: Deploy VMs to appropriate network segments
- **ISO Source**: Verify ISO checksums for integrity

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test thoroughly in your environment
4. Submit a pull request with detailed description

## License

This project is provided as-is for educational and automation purposes. Ensure compliance with your organization's policies and VMware licensing requirements.

## Support

For issues and questions:
- Check the troubleshooting section
- Review vSphere and PowerCLI documentation
- Submit issues with detailed error messages and environment details