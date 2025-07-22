# Install-NginxOnVM.ps1
# PowerCLI script to install nginx on an Ubuntu VM using VMware Guest Operations

param(
    [Parameter(Mandatory=$true)]
    [string]$vCenterServer,
    
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    
    [Parameter(Mandatory=$true)]
    [string]$GuestUsername,
    
    [Parameter(Mandatory=$true)]
    [SecureString]$GuestPassword,
    
    [Parameter(Mandatory=$false)]
    [switch]$StartService = $true,
    
    [Parameter(Mandatory=$false)]
    [switch]$EnableFirewall = $true
)

# Import PowerCLI module
try {
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
} catch {
    Write-Error "Failed to import VMware PowerCLI module. Please install it using: Install-Module -Name VMware.PowerCLI"
    exit 1
}

# Function to execute command in guest
function Invoke-GuestCommand {
    param(
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$VM,
        [string]$Command,
        [string]$Username,
        [SecureString]$Password,
        [string]$Description = "Executing command"
    )
    
    Write-Host "$Description..." -ForegroundColor Green
    
    try {
        $result = Invoke-VMScript -VM $VM `
                                 -ScriptText $Command `
                                 -GuestUser $Username `
                                 -GuestPassword $Password `
                                 -ScriptType Bash `
                                 -ErrorAction Stop
        
        if ($result.ScriptOutput) {
            Write-Host $result.ScriptOutput -ForegroundColor Gray
        }
        
        if ($result.ExitCode -ne 0) {
            throw "Command failed with exit code: $($result.ExitCode)"
        }
        
        return $result
    } catch {
        Write-Error "Failed to execute command: $_"
        throw
    }
}

# Main script execution
try {
    # Connect to vCenter
    Write-Host "Connecting to vCenter Server: $vCenterServer" -ForegroundColor Green
    $connection = Connect-VIServer -Server $vCenterServer -ErrorAction Stop
    
    # Get VM
    Write-Host "Getting VM: $VMName" -ForegroundColor Green
    $vm = Get-VM -Name $VMName -ErrorAction Stop
    
    # Check if VM is powered on
    if ($vm.PowerState -ne "PoweredOn") {
        throw "VM must be powered on to install software. Current state: $($vm.PowerState)"
    }
    
    # Check if VMware Tools is running
    if ($vm.Guest.ToolsStatus -ne "toolsOk" -and $vm.Guest.ToolsStatus -ne "toolsOld") {
        throw "VMware Tools is not running on the VM. Tools status: $($vm.Guest.ToolsStatus)"
    }
    
    Write-Host "`nStarting nginx installation on $VMName" -ForegroundColor Cyan
    
    # Update package list
    Invoke-GuestCommand -VM $vm `
                       -Command "sudo apt-get update" `
                       -Username $GuestUsername `
                       -Password $GuestPassword `
                       -Description "Updating package list"
    
    # Install nginx
    Invoke-GuestCommand -VM $vm `
                       -Command "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx" `
                       -Username $GuestUsername `
                       -Password $GuestPassword `
                       -Description "Installing nginx"
    
    # Start and enable nginx service
    if ($StartService) {
        Invoke-GuestCommand -VM $vm `
                           -Command "sudo systemctl start nginx && sudo systemctl enable nginx" `
                           -Username $GuestUsername `
                           -Password $GuestPassword `
                           -Description "Starting and enabling nginx service"
    }
    
    # Configure firewall
    if ($EnableFirewall) {
        # Check if ufw is installed
        $ufwCheck = Invoke-GuestCommand -VM $vm `
                                       -Command "which ufw" `
                                       -Username $GuestUsername `
                                       -Password $GuestPassword `
                                       -Description "Checking for ufw"
        
        if ($ufwCheck.ScriptOutput) {
            Invoke-GuestCommand -VM $vm `
                               -Command "sudo ufw allow 'Nginx Full' && sudo ufw allow 'OpenSSH' && sudo ufw --force enable" `
                               -Username $GuestUsername `
                               -Password $GuestPassword `
                               -Description "Configuring firewall for nginx"
        }
    }
    
    # Verify nginx installation
    $nginxStatus = Invoke-GuestCommand -VM $vm `
                                      -Command "sudo systemctl is-active nginx" `
                                      -Username $GuestUsername `
                                      -Password $GuestPassword `
                                      -Description "Checking nginx status"
    
    # Get nginx version
    $nginxVersion = Invoke-GuestCommand -VM $vm `
                                       -Command "nginx -v 2>&1" `
                                       -Username $GuestUsername `
                                       -Password $GuestPassword `
                                       -Description "Getting nginx version"
    
    # Get VM IP address
    $vmIP = $vm.Guest.IPAddress | Where-Object { $_ -match '\d+\.\d+\.\d+\.\d+' } | Select-Object -First 1
    
    # Create a simple test page
    $testPageContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Nginx on $VMName</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f0f0f0; }
        .container { background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; }
        .info { background-color: #e7f3ff; padding: 10px; border-radius: 4px; margin: 10px 0; }
    </style>
</head>
<body>
    <div class='container'>
        <h1>Welcome to Nginx on $VMName!</h1>
        <div class='info'>
            <p><strong>Installation successful!</strong></p>
            <p>This page confirms that nginx has been successfully installed and configured on your Ubuntu VM.</p>
            <p>VM Name: $VMName</p>
            <p>Installed via PowerCLI automation</p>
        </div>
    </div>
</body>
</html>
"@
    
    # Create test page
    Invoke-GuestCommand -VM $vm `
                       -Command "echo '$testPageContent' | sudo tee /var/www/html/test.html > /dev/null" `
                       -Username $GuestUsername `
                       -Password $GuestPassword `
                       -Description "Creating test page"
    
    # Display results
    Write-Host "`n==================== Installation Complete ====================" -ForegroundColor Green
    Write-Host "Nginx has been successfully installed on $VMName!" -ForegroundColor Green
    Write-Host "Version: $($nginxVersion.ScriptOutput)" -ForegroundColor Cyan
    Write-Host "Status: $($nginxStatus.ScriptOutput)" -ForegroundColor Cyan
    if ($vmIP) {
        Write-Host "VM IP Address: $vmIP" -ForegroundColor Cyan
        Write-Host "`nYou can access nginx at:" -ForegroundColor Yellow
        Write-Host "  Default page: http://$vmIP/" -ForegroundColor White
        Write-Host "  Test page: http://$vmIP/test.html" -ForegroundColor White
    }
    Write-Host "==============================================================" -ForegroundColor Green
    
} catch {
    Write-Error "Script execution failed: $_"
    exit 1
} finally {
    # Disconnect from vCenter
    if ($connection) {
        Disconnect-VIServer -Server $vCenterServer -Confirm:$false
    }
}