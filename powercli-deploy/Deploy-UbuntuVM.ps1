# Deploy-UbuntuVM.ps1
# PowerCLI script to download Ubuntu ISO and deploy a VM on vSphere
# -vCenterServer "vc-mgmt-a.site-a.vcf.lab" -VMName "Ubuntu-VM" -ClusterName "cluster-mgmt-01a" -DatastoreName "vsan-mgmt-01a"

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
    [string]$ISOPath = "$PSScriptRoot/ubuntu.iso",
    
    [Parameter(Mandatory=$false)]
    [string]$UbuntuVersion = "24.04.2",
    
    [Parameter(Mandatory=$false)]
    [string]$UbuntuURL = "https://releases.ubuntu.com/noble/ubuntu-24.04.2-live-server-amd64.iso"
)

# Import PowerCLI module
try {
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
} catch {
    Write-Error "Failed to import VMware PowerCLI module. Please install it using: Install-Module -Name VMware.PowerCLI"
    exit 1
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
        # Check if ISO already exists
        if (Test-Path $OutputPath) {
            Write-Host "ISO file already exists at $OutputPath. Skipping download." -ForegroundColor Yellow
            return $true
        }
        
        # Download with progress
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri $URL -OutFile $OutputPath -UseBasicParsing
        
        Write-Host "Download completed successfully!" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Failed to download ISO: $_"
        return $false
    }
}

# Function to create or get content library
function Get-OrCreateContentLibrary {
    param(
        [string]$LibraryName = "Ubuntu-ISO-Library",
        [string]$DatastoreName,
        [string]$Description = "Content Library for Ubuntu ISOs"
    )
    
    try {
        # Check if library already exists
        $library = Get-ContentLibrary -Name $LibraryName -ErrorAction SilentlyContinue
        
        if ($library) {
            Write-Host "Content library '$LibraryName' already exists" -ForegroundColor Yellow
            return $library
        }
        
        # Create new content library
        Write-Host "Creating content library: $LibraryName" -ForegroundColor Green
        $datastore = Get-Datastore -Name $DatastoreName
        
        $library = New-ContentLibrary -Name $LibraryName `
                                    -Datastore $datastore `
                                    -Description $Description 
        
        Write-Host "Content library created successfully!" -ForegroundColor Green
        return $library
    } catch {
        Write-Error "Failed to create content library: $_"
        return $null
    }
}

# Function to upload ISO to content library
function Upload-ISOToContentLibrary {
    param(
        [string]$LocalPath,
        [object]$ContentLibrary,
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
    $connection = Connect-VIServer -Server $vCenterServer -ErrorAction Stop
    
    # Download Ubuntu ISO
    if (-not (Download-UbuntuISO -URL $UbuntuURL -OutputPath $ISOPath)) {
        throw "Failed to download Ubuntu ISO"
    }
    
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
                 -Version "v18"
    
    # Configure VM settings
    Write-Host "Configuring VM settings..." -ForegroundColor Green
    
    # Add CD/DVD drive and mount ISO from content library
    # First, we need to get the ISO file from the content library item
    $isoFiles = $libraryItem | Get-ContentLibraryItemFile
    $isoFile = $isoFiles | Where-Object {$_.Name -like "*.iso"} | Select-Object -First 1
    
    if (-not $isoFile) {
        throw "No ISO file found in content library item"
    }
    
    # Mount the ISO from content library
    $cd = New-CDDrive -VM $vm -ContentLibraryIso $libraryItem -StartConnected
    
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
    
    # Apply configuration
    $vm.ExtensionData.ReconfigVM($spec)
    
    # Enable UEFI if needed for newer Ubuntu versions
    Set-VM -VM $vm -GuestId "ubuntu64Guest" -Confirm:$false | Out-Null
    
    # Power on VM
    Write-Host "Powering on VM..." -ForegroundColor Green
    Start-VM -VM $vm -Confirm:$false | Out-Null
    
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
        Disconnect-VIServer -Server $vCenterServer -Confirm:$false
    }
}
