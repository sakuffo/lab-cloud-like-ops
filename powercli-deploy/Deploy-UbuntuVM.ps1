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
    [string]$ISOPath = "$PSScriptRoot\ubuntu.iso",
    
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

# Function to upload ISO to datastore
function Upload-ISOToDatastore {
    param(
        [string]$LocalPath,
        [string]$DatastoreName,
        [string]$RemotePath = "ISO"
    )
    
    try {
        $datastore = Get-Datastore -Name $DatastoreName
        $datastoreDrive = Get-PSDrive | Where-Object {$_.Provider.Name -eq "VimDatastore" -and $_.Root -like "*$DatastoreName*"}
        
        if (-not $datastoreDrive) {
            $datastoreDrive = New-PSDrive -Name "ds" -PSProvider VimDatastore -Root "\" -Datastore $datastore
        }
        
        # Create ISO folder if it doesn't exist
        $isoFolder = "$($datastoreDrive.Name):\$RemotePath"
        if (-not (Test-Path $isoFolder)) {
            New-Item -Path $isoFolder -ItemType Directory | Out-Null
        }
        
        # Upload ISO
        $fileName = Split-Path $LocalPath -Leaf
        $destinationPath = "$isoFolder\$fileName"
        if (-not (Test-Path $isoFolder)) {
            Write-Host "Uploading ISO to datastore: $destinationPath" -ForegroundColor Green
            Copy-DatastoreItem -Item $LocalPath -Destination $destinationPath -Force
            
            Write-Host "ISO uploaded successfully!" -ForegroundColor Green
        }
        

        return "[$DatastoreName] $RemotePath/$fileName"
    } catch {
        Write-Error "Failed to upload ISO to datastore: $_"
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
    
    # Upload ISO to datastore
    $datastoreISOPath = Upload-ISOToDatastore -LocalPath $ISOPath -DatastoreName $DatastoreName
    if (-not $datastoreISOPath) {
        throw "Failed to upload ISO to datastore"
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
    
    # Add CD/DVD drive and mount ISO
    $cd = New-CDDrive -VM $vm -IsoPath $datastoreISOPath -StartConnected
    
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
    Write-Host "ISO: $datastoreISOPath" -ForegroundColor Cyan
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
