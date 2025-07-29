# Deploy-UbuntuVM.ps1
# PowerCLI script to download Ubuntu ISO and deploy a VM on vSphere
# -vCenterServer "vc-mgmt-a.site-a.vcf.lab" -VMName "Ubuntu-VM" -ClusterName "cluster-mgmt-01a" -DatastoreName "vsan-mgmt-01a"

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$vCenterServer = "vc-mgmt-a.site-a.vcf.lab",
    
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')]
    [string]$VMName,
    
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$DatastoreName = "vsan-mgmt-01a",
    
    [Parameter(Mandatory=$false, ParameterSetName='Cluster')]
    [ValidateNotNullOrEmpty()]
    [string]$ClusterName,
    
    [Parameter(Mandatory=$false, ParameterSetName='Host')]
    [ValidateNotNullOrEmpty()]
    [string]$ESXiHost,
    
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$NetworkName = "vmmgmt-vds01-mgmt-01a",
    
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 128)]
    [int]$MemoryGB = 4,
    
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 128)]
    [int]$NumCPU = 2,
    
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 62000)]
    [int]$DiskGB = 20,
    
    [Parameter(Mandatory=$false)]
    [ValidateScript({Test-Path (Split-Path $_ -Parent) -PathType Container})]
    [string]$ISOPath = "$PSScriptRoot/ubuntu.iso",
    
    [Parameter(Mandatory=$false)]
    [string]$UbuntuVersion = "24.04.2",
    
    [Parameter(Mandatory=$false)]
    [ValidatePattern('^https?://')]
    [string]$UbuntuURL = "https://releases.ubuntu.com/noble/ubuntu-24.04.2-live-server-amd64.iso"
)

# Import PowerCLI module
try {
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope User | Out-Null
    Set-PowerCLIConfiguration -ParticipateInCEIP $false -Confirm:$false -Scope User | Out-Null
} catch {
    Write-Error "Failed to import VMware PowerCLI module. Please install it using: Install-Module -Name VMware.PowerCLI"
    exit 1
}

# Set error action preference for better error handling
$ErrorActionPreference = 'Stop'

# Function to download Ubuntu ISO
function Download-UbuntuISO {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$URL,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    Write-Host "Downloading Ubuntu ISO from: $URL" -ForegroundColor Green
    Write-Host "Saving to: $OutputPath" -ForegroundColor Green
    
    try {
        # Check if ISO already exists
        if (Test-Path $OutputPath) {
            Write-Host "ISO file already exists at $OutputPath. Skipping download." -ForegroundColor Yellow
            return $true
        }
        
        # Download with progress
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri $URL -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop
        
        Write-Host "Download completed successfully!" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Failed to download ISO: $_"
        return $false
    }
}

# Function to create or get content library
function Get-OrCreateContentLibrary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LibraryName = "Ubuntu-ISO-Library",
        
        [Parameter(Mandatory=$true)]
        [string]$DatastoreName,
        
        [Parameter(Mandatory=$false)]
        [string]$Description = "Content Library for Ubuntu ISOs"
    )
    
    try {
        # Check if library already exists
        $library = Get-ContentLibrary -Name $LibraryName -ErrorAction SilentlyContinue | Where-Object {$_.Type -eq 'LOCAL'}
        
        if ($library) {
            Write-Host "Content library '$LibraryName' already exists" -ForegroundColor Yellow
            return $library
        }
        
        # Create new content library
        Write-Host "Creating content library: $LibraryName" -ForegroundColor Green
        $datastore = Get-Datastore -Name $DatastoreName
        
        $library = New-ContentLibrary -Name $LibraryName `
                                    -Datastore $datastore `
                                    -Description $Description `
                                    -Type Local 
        
        Write-Host "Content library created successfully!" -ForegroundColor Green
        return $library
    } catch {
        Write-Error "Failed to create content library: $_"
        return $null
    }
}

# Function to upload ISO to content library
function Upload-ISOToContentLibrary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$LocalPath,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [object]$ContentLibrary,
        
        [Parameter(Mandatory=$false)]
        [string]$ItemName = $null
    )
    
    try {
        if (-not $ItemName) {
            $ItemName = [System.IO.Path]::GetFileNameWithoutExtension($LocalPath)
        }
        
        # Check if item already exists
        $existingItem = Get-ContentLibraryItem -ContentLibrary $ContentLibrary -Name $ItemName -ErrorAction SilentlyContinue
        
        if ($existingItem) {
            Write-Host "Content library item '$ItemName' already exists. Skipping upload." -ForegroundColor Yellow
            return $existingItem
        }
        
        Write-Host "Uploading ISO to content library as: $ItemName" -ForegroundColor Green
        
        # Create library item
        $libraryItem = New-ContentLibraryItem -ContentLibrary $ContentLibrary `
                                             -Name $ItemName `
                                             -ItemType "iso" `
                                             -Files @($LocalPath)
        
        Write-Host "ISO uploaded to content library successfully!" -ForegroundColor Green
        return $libraryItem
    } catch {
        Write-Error "Failed to upload ISO to content library: $_"
        return $null
    }
}

# Main script execution
try {
    # Connect to vCenter
    Write-Host "Connecting to vCenter Server: $vCenterServer" -ForegroundColor Green
    try {
        $connection = Connect-VIServer -Server $vCenterServer -ErrorAction Stop
    } catch {
        Write-Error "Failed to connect to vCenter Server: $_"
        throw
    }
    
    # Download Ubuntu ISO
    if (-not (Download-UbuntuISO -URL $UbuntuURL -OutputPath $ISOPath)) {
        throw "Failed to download Ubuntu ISO"
    }
    
    # Get target location
    try {
        if ($ClusterName) {
            $cluster = Get-Cluster -Name $ClusterName -ErrorAction Stop
            $vmHost = $cluster | Get-VMHost -ErrorAction Stop | Where-Object {$_.ConnectionState -eq 'Connected'} | Select-Object -First 1
            if (-not $vmHost) {
                throw "No connected hosts found in cluster '$ClusterName'"
            }
        } elseif ($ESXiHost) {
            $vmHost = Get-VMHost -Name $ESXiHost -ErrorAction Stop
            if ($vmHost.ConnectionState -ne 'Connected') {
                throw "Host '$ESXiHost' is not in connected state"
            }
        } else {
            throw "Please specify either -ClusterName or -ESXiHost"
        }
    } catch {
        Write-Error "Failed to get target host: $_"
        throw
    }
    
    # Get datastore
    try {
        $datastore = Get-Datastore -Name $DatastoreName -ErrorAction Stop
        if ($datastore.FreeSpaceGB -lt ($DiskGB + 5)) {
            Write-Warning "Datastore '$DatastoreName' has only $($datastore.FreeSpaceGB)GB free space"
        }
    } catch {
        Write-Error "Failed to get datastore '$DatastoreName': $_"
        throw
    }
    
    # Create or get content library
    $contentLibrary = Get-OrCreateContentLibrary -LibraryName "Ubuntu-ISO-Library" -DatastoreName $DatastoreName
    if (-not $contentLibrary) {
        throw "Failed to create or get content library"
    }
    
    # Upload ISO to content library
    $libraryItem = Upload-ISOToContentLibrary -LocalPath $ISOPath -ContentLibrary $contentLibrary
    if (-not $libraryItem) {
        throw "Failed to upload ISO to content library"
    }
    
    # Get the port group
    try {
        $portGroup = Get-VDPortgroup -Name $NetworkName -ErrorAction SilentlyContinue
        if (-not $portGroup) {
            # Try standard port group
            $portGroup = Get-VirtualPortGroup -Name $NetworkName -VMHost $vmHost -ErrorAction Stop
        }
    } catch {
        Write-Error "Failed to get network port group '$NetworkName': $_"
        throw
    }
    
    # Create VM
    Write-Host "Creating VM: $VMName" -ForegroundColor Green
    $vm = New-VM -Name $VMName `
                 -VMHost $vmHost `
                 -Datastore $datastore `
                 -NumCpu $NumCPU `
                 -MemoryGB $MemoryGB `
                 -DiskGB $DiskGB `
                 -Portgroup $portGroup `
                 -GuestId "ubuntu64Guest" `
                 -HardwareVersion "vmx-18"
    
    # Configure VM settings
    Write-Host "Configuring VM settings..." -ForegroundColor Green
    
    # Add CD/DVD drive and mount ISO from content library
    # Mount the ISO from content library
    Write-Host "Adding CD/DVD drive with Ubuntu ISO..." -ForegroundColor Green
    $cd = New-CDDrive -VM $vm -ContentLibraryIso $libraryItem
    
    # Set boot order to CD first (must be done before power on)
    Write-Host "Setting boot order to CD-ROM first..." -ForegroundColor Green
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
    
    # Also ensure CD is set to connect at power on
    $spec.DeviceChange = New-Object VMware.Vim.VirtualDeviceConfigSpec[] (1)
    $spec.DeviceChange[0] = New-Object VMware.Vim.VirtualDeviceConfigSpec
    $spec.DeviceChange[0].Device = $cd.ExtensionData
    $spec.DeviceChange[0].Device.Connectable = New-Object VMware.Vim.VirtualDeviceConnectInfo
    $spec.DeviceChange[0].Device.Connectable.Connected = $true
    $spec.DeviceChange[0].Device.Connectable.StartConnected = $true
    $spec.DeviceChange[0].Device.Connectable.AllowGuestControl = $true
    $spec.DeviceChange[0].Operation = [VMware.Vim.VirtualDeviceConfigSpecOperation]::edit
    
    # Apply configuration
    $vm.ExtensionData.ReconfigVM($spec)
    
    # The GuestId is already set during VM creation, no need to set it again
    
    # Power on VM
    Write-Host "Powering on VM..." -ForegroundColor Green
    try {
        Start-VM -VM $vm -Confirm:$false -ErrorAction Stop | Out-Null
    } catch {
        Write-Warning "Failed to power on VM: $_"
        Write-Host "VM created successfully but not powered on. You can power it on manually." -ForegroundColor Yellow
    }
    
    Write-Host "`nVM deployment completed successfully!" -ForegroundColor Green
    Write-Host "VM Name: $VMName" -ForegroundColor Cyan
    Write-Host "vCPUs: $NumCPU" -ForegroundColor Cyan
    Write-Host "Memory: $($MemoryGB)GB" -ForegroundColor Cyan
    Write-Host "Disk: $($DiskGB)GB" -ForegroundColor Cyan
    Write-Host "Network: $NetworkName" -ForegroundColor Cyan
    Write-Host "ISO: $($libraryItem.Name) (Content Library)" -ForegroundColor Cyan
    Write-Host "Content Library: $($contentLibrary.Name)" -ForegroundColor Cyan
    Write-Host "`nThe VM is now powered on and should boot from the Ubuntu ISO." -ForegroundColor Yellow
    Write-Host "Please complete the Ubuntu installation manually through the VM console." -ForegroundColor Yellow
    
} catch {
    Write-Error "Script execution failed: $_"
    exit 1
} finally {
    # Disconnect from vCenter
    if ($connection) {
        Disconnect-VIServer -Server $vCenterServer -Confirm:$false -ErrorAction SilentlyContinue
    }
}
