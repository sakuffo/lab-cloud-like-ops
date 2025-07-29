# Create-UbuntuAutoinstallISO.ps1
# Creates a custom Ubuntu ISO with autoinstall configuration embedded
# Requires: 7-Zip, mkisofs/genisoimage or Windows ADK

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceISO,
    
    [Parameter(Mandatory=$true)]
    [string]$OutputISO,
    
    [Parameter(Mandatory=$false)]
    [string]$Username = "ubuntu",
    
    [Parameter(Mandatory=$false)]
    [string]$Password = "Ubuntu123!",
    
    [Parameter(Mandatory=$false)]
    [string]$Hostname = "ubuntu-server",
    
    [Parameter(Mandatory=$false)]
    [string]$IPAddress,
    
    [Parameter(Mandatory=$false)]
    [string]$SubnetMask = "255.255.255.0",
    
    [Parameter(Mandatory=$false)]
    [string]$Gateway,
    
    [Parameter(Mandatory=$false)]
    [string]$DNS = "8.8.8.8",
    
    [Parameter(Mandatory=$false)]
    [string[]]$Packages = @("curl", "wget", "vim", "net-tools", "open-vm-tools"),
    
    [Parameter(Mandatory=$false)]
    [string]$PostInstallScript
)

# Check for required tools
function Test-Prerequisites {
    $7zipPath = Get-Command "7z.exe" -ErrorAction SilentlyContinue
    if (-not $7zipPath) {
        $7zipPath = "C:\Program Files\7-Zip\7z.exe"
        if (-not (Test-Path $7zipPath)) {
            Write-Error "7-Zip is required but not found. Please install from https://www.7-zip.org/"
            return $false
        }
    }
    
    return $true
}

# Function to generate autoinstall user-data
function New-UserData {
    param(
        [string]$Username,
        [string]$Password,
        [string]$Hostname,
        [string]$IPAddress,
        [string]$SubnetMask,
        [string]$Gateway,
        [string]$DNS,
        [string[]]$Packages,
        [string]$PostInstallScript
    )
    
    # Password hash (pre-generated for Ubuntu123!)
    $passwordHash = '$6$rounds=4096$J6OHN8qt8$4RJfAb5dQRkXg3X.M/vGfKHmY5VuOINJDfqPKNZYJVN0uNMv7YbYqVHFN7Lm8VzKZmHsxVzKZOH9L7lHsxVzK'
    
    # Calculate CIDR from subnet mask
    $cidr = 24  # Default for 255.255.255.0
    if ($SubnetMask) {
        $cidr = ([System.Net.IPAddress]::Parse($SubnetMask).GetAddressBytes() | ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') } | Join-String | Select-String -Pattern '1' -AllMatches).Matches.Count
    }
    
    # Network configuration
    if ($IPAddress) {
        $networkConfig = @"
    network:
      version: 2
      ethernets:
        ens160:
          dhcp4: no
          addresses:
            - $IPAddress/$cidr
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
    
    # Package list
    $packageList = $Packages | ForEach-Object { "    - $_" } | Join-String -Separator "`n"
    
    # Late commands
    $lateCommands = @"
    - echo '$Username ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/$Username
    - chmod 440 /target/etc/sudoers.d/$Username
    - curtin in-target --target=/target -- systemctl enable ssh
    - curtin in-target --target=/target -- systemctl enable open-vm-tools
"@
    
    if ($PostInstallScript) {
        $lateCommands += "`n    - curtin in-target --target=/target -- bash -c '$PostInstallScript'"
    }
    
    $userData = @"
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
    variant: ""
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
$packageList
  late-commands:
$lateCommands
  user-data:
    disable_root: false
"@
    
    return $userData
}

# Function to create custom ISO
function New-CustomISO {
    param(
        [string]$SourceISO,
        [string]$OutputISO,
        [string]$UserData,
        [string]$MetaData
    )
    
    try {
        $tempDir = "$PSScriptRoot\temp_iso_$(Get-Random)"
        $extractDir = "$tempDir\extract"
        
        Write-Host "Creating temporary directory: $tempDir" -ForegroundColor Green
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        New-Item -Path $extractDir -ItemType Directory -Force | Out-Null
        
        # Extract ISO
        Write-Host "Extracting ISO contents..." -ForegroundColor Green
        $7zipPath = "C:\Program Files\7-Zip\7z.exe"
        if (-not (Test-Path $7zipPath)) {
            $7zipPath = (Get-Command "7z.exe" -ErrorAction SilentlyContinue).Path
        }
        
        & $7zipPath x -y -o"$extractDir" "$SourceISO" | Out-Null
        
        # Create autoinstall directory
        $autoinstallDir = "$extractDir\autoinstall"
        New-Item -Path $autoinstallDir -ItemType Directory -Force | Out-Null
        
        # Write autoinstall files
        $UserData | Out-File -FilePath "$autoinstallDir\user-data" -Encoding UTF8 -NoNewline
        $MetaData | Out-File -FilePath "$autoinstallDir\meta-data" -Encoding UTF8 -NoNewline
        
        # Modify boot configuration
        $grubCfg = "$extractDir\boot\grub\grub.cfg"
        if (Test-Path $grubCfg) {
            Write-Host "Modifying GRUB configuration..." -ForegroundColor Green
            $grubContent = Get-Content $grubCfg -Raw
            
            # Add autoinstall parameter to the default menu entry
            $grubContent = $grubContent -replace '(linux\s+/casper/vmlinuz\s+[^\n]+)', '$1 autoinstall ds=nocloud;s=/cdrom/autoinstall/'
            
            $grubContent | Out-File -FilePath $grubCfg -Encoding UTF8 -NoNewline
        }
        
        # Modify isolinux configuration for BIOS boot
        $isolinuxCfg = "$extractDir\isolinux\txt.cfg"
        if (Test-Path $isolinuxCfg) {
            Write-Host "Modifying isolinux configuration..." -ForegroundColor Green
            $isolinuxContent = Get-Content $isolinuxCfg -Raw
            
            # Add autoinstall parameter
            $isolinuxContent = $isolinuxContent -replace '(append\s+[^\n]+)', '$1 autoinstall ds=nocloud;s=/cdrom/autoinstall/'
            
            $isolinuxContent | Out-File -FilePath $isolinuxCfg -Encoding UTF8 -NoNewline
        }
        
        # Create new ISO
        Write-Host "Creating new ISO: $OutputISO" -ForegroundColor Green
        
        # Check for available ISO creation tools
        $mkisofsPath = Get-Command "mkisofs.exe" -ErrorAction SilentlyContinue
        $genisoimagePath = Get-Command "genisoimage.exe" -ErrorAction SilentlyContinue
        $osicdimgPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
        
        if ($mkisofsPath) {
            & mkisofs -r -V "Ubuntu Server Autoinstall" `
                -cache-inodes -J -l `
                -b isolinux/isolinux.bin `
                -c isolinux/boot.cat `
                -no-emul-boot -boot-load-size 4 -boot-info-table `
                -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot `
                -o "$OutputISO" "$extractDir"
        } elseif ($genisoimagePath) {
            & genisoimage -r -V "Ubuntu Server Autoinstall" `
                -cache-inodes -J -l `
                -b isolinux/isolinux.bin `
                -c isolinux/boot.cat `
                -no-emul-boot -boot-load-size 4 -boot-info-table `
                -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot `
                -o "$OutputISO" "$extractDir"
        } elseif (Test-Path $osicdimgPath) {
            & "$osicdimgPath" -n -m -b"$extractDir\isolinux\isolinux.bin" "$extractDir" "$OutputISO"
        } else {
            Write-Error "No ISO creation tool found. Please install mkisofs, genisoimage, or Windows ADK."
            return $false
        }
        
        Write-Host "Custom ISO created successfully!" -ForegroundColor Green
        
        # Clean up
        Remove-Item -Path $tempDir -Recurse -Force
        
        return $true
    } catch {
        Write-Error "Failed to create custom ISO: $_"
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}

# Main execution
if (-not (Test-Prerequisites)) {
    exit 1
}

if (-not (Test-Path $SourceISO)) {
    Write-Error "Source ISO not found: $SourceISO"
    exit 1
}

Write-Host "Creating Ubuntu autoinstall ISO..." -ForegroundColor Green
Write-Host "Source ISO: $SourceISO" -ForegroundColor Cyan
Write-Host "Output ISO: $OutputISO" -ForegroundColor Cyan
Write-Host "Username: $Username" -ForegroundColor Cyan
Write-Host "Hostname: $Hostname" -ForegroundColor Cyan

if ($IPAddress) {
    Write-Host "IP Configuration: Static" -ForegroundColor Cyan
    Write-Host "  IP Address: $IPAddress" -ForegroundColor Cyan
    Write-Host "  Subnet Mask: $SubnetMask" -ForegroundColor Cyan
    Write-Host "  Gateway: $Gateway" -ForegroundColor Cyan
    Write-Host "  DNS: $DNS" -ForegroundColor Cyan
} else {
    Write-Host "IP Configuration: DHCP" -ForegroundColor Cyan
}

# Generate configurations
$userData = New-UserData -Username $Username -Password $Password -Hostname $Hostname `
                        -IPAddress $IPAddress -SubnetMask $SubnetMask -Gateway $Gateway -DNS $DNS `
                        -Packages $Packages -PostInstallScript $PostInstallScript

$metaData = @"
instance-id: iid-local01
local-hostname: $Hostname
"@

# Create custom ISO
if (New-CustomISO -SourceISO $SourceISO -OutputISO $OutputISO -UserData $userData -MetaData $metaData) {
    Write-Host "`nCustom autoinstall ISO created successfully!" -ForegroundColor Green
    Write-Host "You can now use this ISO to deploy Ubuntu VMs with automated installation." -ForegroundColor Green
    Write-Host "`nThe VM will automatically install with:" -ForegroundColor Yellow
    Write-Host "  Username: $Username" -ForegroundColor Yellow
    Write-Host "  Password: $Password" -ForegroundColor Yellow
} else {
    Write-Error "Failed to create custom ISO"
    exit 1
}