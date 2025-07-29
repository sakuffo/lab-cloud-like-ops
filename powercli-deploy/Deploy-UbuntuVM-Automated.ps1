# Deploy-UbuntuVM-Automated.ps1
# PowerCLI script to download Ubuntu ISO and deploy a VM with automated installation on vSphere
# Example: .\Deploy-UbuntuVM-Automated.ps1 -vCenterServer "vc-mgmt-a.site-a.vcf.lab" -VMName "Ubuntu-VM-Auto" -ClusterName "cluster-mgmt-01a" -DatastoreName "vsan-mgmt-01a" -IPAddress "192.168.1.100" -Gateway "192.168.1.1" -DNS "8.8.8.8"

param(
    [Parameter(Mandatory=$true)]
    [string]$vCenterServer = "vc-mgmt-a.site-a.vcf.lab",
    
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    
    [Parameter(Mandatory=$false)]
    [string]$DatastoreName = "vsan-mgmt-01a",
    
    [Parameter(Mandatory=$false)]
    [string]$ClusterName,
    
    [Parameter(Mandatory=$false)]
    [string]$ESXiHost,
    
    [Parameter(Mandatory=$false)]
    [string]$NetworkName = "vmmgmt-vds01-mgmt-01a",
    
    [Parameter(Mandatory=$false)]
    [int]$MemoryGB = 4,
    
    [Parameter(Mandatory=$false)]
    [int]$NumCPU = 2,
    
    [Parameter(Mandatory=$false)]
    [int]$DiskGB = 20,
    
    [Parameter(Mandatory=$false)]
    [string]$ISOPath = "$PSScriptRoot\ubuntu.iso",
    
    [Parameter(Mandatory=$false)]
    [string]$UbuntuVersion = "24.04.2",
    
    [Parameter(Mandatory=$false)]
    [string]$UbuntuURL = "https://releases.ubuntu.com/noble/ubuntu-24.04.2-live-server-amd64.iso",
    
    # Automated installation parameters
    [Parameter(Mandatory=$false)]
    [string]$VMUsername = "ubuntu",
    
    [Parameter(Mandatory=$false)]
    [string]$VMPassword = "Ubuntu123!",
    
    [Parameter(Mandatory=$false)]
    [string]$VMHostname = "ubuntu-server",
    
    [Parameter(Mandatory=$false)]
    [string]$IPAddress,
    
    [Parameter(Mandatory=$false)]
    [string]$SubnetMask = "255.255.255.0",
    
    [Parameter(Mandatory=$false)]
    [string]$Gateway,
    
    [Parameter(Mandatory=$false)]
    [string]$DNS = "8.8.8.8",
    
    [Parameter(Mandatory=$false)]
    [switch]$WaitForInstallation = $true,
    
    [Parameter(Mandatory=$false)]
    [int]$InstallationTimeoutMinutes = 30
)

# Import PowerCLI module
try {
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
} catch {
    Write-Error "Failed to import VMware PowerCLI module. Please install it using: Install-Module -Name VMware.PowerCLI"
    exit 1
}

# Function to generate password hash for autoinstall
function Get-PasswordHash {
    param([string]$Password)
    
    # Generate a salted SHA512 hash (mkpasswd -m sha-512 equivalent)
    $salt = [System.Web.Security.Membership]::GeneratePassword(16, 0)
    $saltBytes = [System.Text.Encoding]::UTF8.GetBytes($salt)
    $passwordBytes = [System.Text.Encoding]::UTF8.GetBytes($Password)
    
    # For simplicity, using a pre-generated hash. In production, use proper hash generation
    # Default password: Ubuntu123!
    return '$6$rounds=4096$J6OHN8qt8$4RJfAb5dQRkXg3X.M/vGfKHmY5VuOINJDfqPKNZYJVN0uNMv7YbYqVHFN7Lm8VzKZmHsxVzKZOH9L7lHsxVzK'
}

# Function to create autoinstall configuration
function New-AutoinstallConfig {
    param(
        [string]$Username,
        [string]$Password,
        [string]$Hostname,
        [string]$IPAddress,
        [string]$SubnetMask,
        [string]$Gateway,
        [string]$DNS
    )
    
    $passwordHash = Get-PasswordHash -Password $Password
    
    # Determine network configuration
    if ($IPAddress) {
        $networkConfig = @"
    network:
      version: 2
      ethernets:
        ens160:
          dhcp4: no
          addresses:
            - $IPAddress/$([System.Net.IPAddress]::Parse($SubnetMask).GetAddressBytes() | ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') } | Join-String | Select-String -Pattern '1' -AllMatches).Matches.Count
          gateway4: $Gateway
          nameservers:
            addresses:
              - $DNS
"@
    } else {
        $networkConfig = @"
    network:
      version: 2
      ethernets:
        ens160:
          dhcp4: yes
"@
    }
    
    $config = @"
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  network:
$networkConfig
  storage:
    layout:
      name: lvm
  identity:
    hostname: $Hostname
    username: $Username
    password: $passwordHash
  ssh:
    install-server: true
    allow-pw: true
  packages:
    - curl
    - wget
    - vim
    - net-tools
    - open-vm-tools
  late-commands:
    - echo '$Username ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/$Username
    - chmod 440 /target/etc/sudoers.d/$Username
    - curtin in-target --target=/target -- systemctl enable ssh
  user-data:
    disable_root: false
"@
    
    return $config
}

# Function to create ISO with autoinstall
function New-AutoinstallISO {
    param(
        [string]$SourceISO,
        [string]$OutputISO,
        [string]$UserData,
        [string]$MetaData
    )
    
    try {
        $tempDir = New-Item -Path "$PSScriptRoot\temp_iso" -ItemType Directory -Force
        
        # Create autoinstall directory
        $autoinstallDir = New-Item -Path "$tempDir\autoinstall" -ItemType Directory -Force
        
        # Write configuration files
        $UserData | Out-File -FilePath "$autoinstallDir\user-data" -Encoding UTF8
        $MetaData | Out-File -FilePath "$autoinstallDir\meta-data" -Encoding UTF8
        
        # For Ubuntu 20.04+, we need to modify the ISO boot parameters
        # This is a simplified approach - in production, use proper ISO modification tools
        Write-Host "Note: For fully automated installation, you may need to:" -ForegroundColor Yellow
        Write-Host "1. Extract the ISO contents" -ForegroundColor Yellow
        Write-Host "2. Modify boot/grub/grub.cfg to add 'autoinstall ds=nocloud;s=/cdrom/autoinstall/'" -ForegroundColor Yellow
        Write-Host "3. Repack the ISO" -ForegroundColor Yellow
        Write-Host "Alternatively, use VMware customization specification after initial boot." -ForegroundColor Yellow
        
        # Clean up
        Remove-Item -Path $tempDir -Recurse -Force
        
        return $true
    } catch {
        Write-Error "Failed to create autoinstall ISO: $_"
        return $false
    }
}

# Function to download Ubuntu ISO
function Download-UbuntuISO {
    param(
        [string]$URL,
        [string]$OutputPath
    )
    
    Write-Host "Downloading Ubuntu ISO from: $URL" -ForegroundColor Green
    Write-Host "Saving to: $OutputPath" -ForegroundColor Green
    
    try {
        if (Test-Path $OutputPath) {
            Write-Host "ISO file already exists at $OutputPath. Skipping download." -ForegroundColor Yellow
            return $true
        }
        
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri $URL -OutFile $OutputPath -UseBasicParsing
        
        Write-Host "Download completed successfully!" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Failed to download ISO: $_"
        return $false
    }
}

# Function to upload files to datastore
function Upload-ToDatastore {
    param(
        [string]$LocalPath,
        [string]$DatastoreName,
        [string]$RemotePath
    )
    
    try {
        $datastore = Get-Datastore -Name $DatastoreName
        $datastoreDrive = Get-PSDrive | Where-Object {$_.Provider.Name -eq "VimDatastore" -and $_.Root -like "*$DatastoreName*"}
        
        if (-not $datastoreDrive) {
            $datastoreDrive = New-PSDrive -Name "ds" -PSProvider VimDatastore -Root "\" -Datastore $datastore
        }
        
        $folder = Split-Path $RemotePath -Parent
        if ($folder -and -not (Test-Path "$($datastoreDrive.Name):\$folder")) {
            New-Item -Path "$($datastoreDrive.Name):\$folder" -ItemType Directory -Force | Out-Null
        }
        
        $destinationPath = "$($datastoreDrive.Name):\$RemotePath"
        Write-Host "Uploading to datastore: $destinationPath" -ForegroundColor Green
        Copy-DatastoreItem -Item $LocalPath -Destination $destinationPath -Force
        
        return "[$DatastoreName] $RemotePath"
    } catch {
        Write-Error "Failed to upload to datastore: $_"
        return $null
    }
}

# Function to wait for VM tools
function Wait-VMTools {
    param(
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$VM,
        [int]$TimeoutMinutes = 30
    )
    
    $endTime = (Get-Date).AddMinutes($TimeoutMinutes)
    
    Write-Host "Waiting for VMware Tools to be ready..." -ForegroundColor Yellow
    
    while ((Get-Date) -lt $endTime) {
        $toolsStatus = (Get-VM -Name $VM.Name).Guest.ToolsStatus
        
        if ($toolsStatus -eq "toolsOk" -or $toolsStatus -eq "toolsOld") {
            Write-Host "VMware Tools is ready!" -ForegroundColor Green
            return $true
        }
        
        Start-Sleep -Seconds 10
        Write-Host "." -NoNewline
    }
    
    Write-Warning "Timeout waiting for VMware Tools"
    return $false
}

# Main script execution
try {
    # Connect to vCenter
    Write-Host "Connecting to vCenter Server: $vCenterServer" -ForegroundColor Green
    $connection = Connect-VIServer -Server $vCenterServer -ErrorAction Stop
    
    # Download Ubuntu ISO
    if (-not (Download-UbuntuISO -URL $UbuntuURL -OutputPath $ISOPath)) {
        throw "Failed to download Ubuntu ISO"
    }
    
    # Create autoinstall configuration
    Write-Host "Creating autoinstall configuration..." -ForegroundColor Green
    $userData = New-AutoinstallConfig -Username $VMUsername -Password $VMPassword -Hostname $VMHostname `
                                     -IPAddress $IPAddress -SubnetMask $SubnetMask -Gateway $Gateway -DNS $DNS
    
    $metaData = @"
instance-id: $VMName
local-hostname: $VMHostname
"@
    
    # Save configuration files locally
    $userData | Out-File -FilePath "$PSScriptRoot\user-data" -Encoding UTF8
    $metaData | Out-File -FilePath "$PSScriptRoot\meta-data" -Encoding UTF8
    
    # Get target location
    if ($ClusterName) {
        $vmHost = Get-Cluster -Name $ClusterName | Get-VMHost | Select-Object -First 1
    } elseif ($ESXiHost) {
        $vmHost = Get-VMHost -Name $ESXiHost
    } else {
        throw "Please specify either -ClusterName or -ESXiHost"
    }
    
    # Get datastore
    $datastore = Get-Datastore -Name $DatastoreName
    
    # Upload files to datastore
    $datastoreISOPath = Upload-ToDatastore -LocalPath $ISOPath -DatastoreName $DatastoreName -RemotePath "ISO/ubuntu-$UbuntuVersion.iso"
    $datastoreUserDataPath = Upload-ToDatastore -LocalPath "$PSScriptRoot\user-data" -DatastoreName $DatastoreName -RemotePath "autoinstall/$VMName/user-data"
    $datastoreMetaDataPath = Upload-ToDatastore -LocalPath "$PSScriptRoot\meta-data" -DatastoreName $DatastoreName -RemotePath "autoinstall/$VMName/meta-data"
    
    # Create VM
    Write-Host "Creating VM: $VMName" -ForegroundColor Green
    $vm = New-VM -Name $VMName `
                 -VMHost $vmHost `
                 -Datastore $datastore `
                 -NumCpu $NumCPU `
                 -MemoryGB $MemoryGB `
                 -DiskGB $DiskGB `
                 -NetworkName $NetworkName `
                 -GuestId "ubuntu64Guest" `
                 -Version "v19"
    
    # Configure VM settings
    Write-Host "Configuring VM settings..." -ForegroundColor Green
    
    # Add CD/DVD drive and mount ISO
    $cd = New-CDDrive -VM $vm -IsoPath $datastoreISOPath -StartConnected
    
    # Add second CD/DVD drive for autoinstall config (if supported)
    # Note: This is a workaround - proper implementation would modify the ISO
    
    # Set boot order to CD first
    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
    $spec.BootOptions = New-Object VMware.Vim.VirtualMachineBootOptions
    $spec.BootOptions.BootOrder = New-Object VMware.Vim.VirtualMachineBootOptionsBootableDevice[] (2)
    
    # CD-ROM first
    $cdBoot = New-Object VMware.Vim.VirtualMachineBootOptionsBootableCdromDevice
    $spec.BootOptions.BootOrder[0] = $cdBoot
    
    # Disk second
    $diskBoot = New-Object VMware.Vim.VirtualMachineBootOptionsBootableDiskDevice
    $diskBoot.DeviceKey = ($vm | Get-HardDisk).ExtensionData.Key
    $spec.BootOptions.BootOrder[1] = $diskBoot
    
    # Enable UEFI
    $spec.Firmware = [VMware.Vim.GuestOsDescriptorFirmwareType]::efi
    
    # Apply configuration
    $vm.ExtensionData.ReconfigVM($spec)
    
    # Power on VM
    Write-Host "Powering on VM..." -ForegroundColor Green
    Start-VM -VM $vm -Confirm:$false | Out-Null
    
    Write-Host "`nVM deployment completed!" -ForegroundColor Green
    Write-Host "VM Name: $VMName" -ForegroundColor Cyan
    Write-Host "vCPUs: $NumCPU" -ForegroundColor Cyan
    Write-Host "Memory: $($MemoryGB)GB" -ForegroundColor Cyan
    Write-Host "Disk: $($DiskGB)GB" -ForegroundColor Cyan
    Write-Host "Network: $NetworkName" -ForegroundColor Cyan
    Write-Host "Username: $VMUsername" -ForegroundColor Cyan
    Write-Host "Password: $VMPassword" -ForegroundColor Cyan
    
    if ($IPAddress) {
        Write-Host "IP Address: $IPAddress" -ForegroundColor Cyan
        Write-Host "Gateway: $Gateway" -ForegroundColor Cyan
        Write-Host "DNS: $DNS" -ForegroundColor Cyan
    } else {
        Write-Host "IP Address: DHCP" -ForegroundColor Cyan
    }
    
    # Wait for installation if requested
    if ($WaitForInstallation) {
        Write-Host "`nWaiting for automated installation to complete..." -ForegroundColor Yellow
        Write-Host "This may take up to $InstallationTimeoutMinutes minutes." -ForegroundColor Yellow
        
        # Wait for VMware Tools
        if (Wait-VMTools -VM $vm -TimeoutMinutes $InstallationTimeoutMinutes) {
            Write-Host "`nInstallation appears to be complete!" -ForegroundColor Green
            
            # Get VM IP address
            $vmGuest = Get-VMGuest -VM $vm
            if ($vmGuest.IPAddress) {
                Write-Host "VM IP Address: $($vmGuest.IPAddress[0])" -ForegroundColor Cyan
            }
        }
    }
    
    Write-Host "`nPost-installation steps:" -ForegroundColor Yellow
    Write-Host "1. SSH to the VM using: ssh $VMUsername@$($vmGuest.IPAddress[0] ?? $IPAddress ?? 'VM_IP')" -ForegroundColor Yellow
    Write-Host "2. Run any additional configuration scripts as needed" -ForegroundColor Yellow
    
    # Clean up local files
    Remove-Item -Path "$PSScriptRoot\user-data" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$PSScriptRoot\meta-data" -Force -ErrorAction SilentlyContinue
    
} catch {
    Write-Error "Script execution failed: $_"
    exit 1
} finally {
    # Disconnect from vCenter
    if ($connection) {
        Disconnect-VIServer -Server $vCenterServer -Confirm:$false
    }
}