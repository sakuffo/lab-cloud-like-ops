# Install-NginxOnVM-PowerCLI.ps1
# PowerCLI script to install nginx on Ubuntu VM using VMware Guest Operations

param(
    [Parameter(Mandatory=$true)]
    [string]$vCenterServer,
    
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    
    [Parameter(Mandatory=$true)]
    [string]$GuestUsername,
    
    [Parameter(Mandatory=$true)]
    [string]$GuestPassword,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipFirewall = $false
)

# Import PowerCLI module
try {
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
} catch {
    Write-Error "Failed to import VMware PowerCLI module. Please install it using: Install-Module -Name VMware.PowerCLI"
    exit 1
}

# Main script execution
try {
    # Connect to vCenter
    Write-Host "Connecting to vCenter Server: $vCenterServer" -ForegroundColor Green
    $connection = Connect-VIServer -Server $vCenterServer -ErrorAction Stop
    
    # Get VM
    Write-Host "Getting VM: $VMName" -ForegroundColor Green
    $vm = Get-VM -Name $VMName -ErrorAction Stop
    
    # Check VM state
    if ($vm.PowerState -ne "PoweredOn") {
        throw "VM must be powered on. Current state: $($vm.PowerState)"
    }
    
    # Check VMware Tools
    $toolsStatus = $vm.Guest.ToolsStatus
    Write-Host "VMware Tools Status: $toolsStatus" -ForegroundColor Cyan
    
    if ($toolsStatus -ne "toolsOk" -and $toolsStatus -ne "toolsOld") {
        throw "VMware Tools is not running properly. Status: $toolsStatus"
    }
    
    # Convert password to secure string if needed
    if ($GuestPassword -is [string]) {
        $GuestPasswordSecure = ConvertTo-SecureString $GuestPassword -AsPlainText -Force
    } else {
        $GuestPasswordSecure = $GuestPassword
    }
    
    Write-Host "`nStarting nginx installation..." -ForegroundColor Green
    
    # Create a script that will handle the entire installation
    $installScript = @'
#!/bin/bash
# Nginx installation script

echo "Starting nginx installation process..."

# Update package list
echo "Updating package list..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update

# Install nginx
echo "Installing nginx..."
sudo apt-get install -y nginx

# Start and enable nginx
echo "Starting and enabling nginx service..."
sudo systemctl start nginx
sudo systemctl enable nginx

# Configure firewall if ufw is installed
if command -v ufw >/dev/null 2>&1; then
    echo "Configuring firewall..."
    sudo ufw allow 'Nginx Full'
    sudo ufw allow 'OpenSSH'
    # Note: Not enabling ufw automatically as it might disconnect SSH
    echo "Firewall rules added (ufw not enabled automatically)"
fi

# Create a test page
echo "Creating test page..."
sudo tee /var/www/html/powercli-test.html > /dev/null << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Nginx Installed via PowerCLI</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 40px; 
            background-color: #f0f0f0; 
            text-align: center;
        }
        .container { 
            background-color: white; 
            padding: 30px; 
            border-radius: 10px; 
            box-shadow: 0 4px 6px rgba(0,0,0,0.1); 
            max-width: 600px;
            margin: 0 auto;
        }
        h1 { color: #2c3e50; }
        .success { 
            color: #27ae60; 
            font-size: 24px;
            margin: 20px 0;
        }
        .info {
            background-color: #ecf0f1;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎉 Nginx Successfully Installed!</h1>
        <p class="success">✓ Installation completed via PowerCLI</p>
        <div class="info">
            <p><strong>Method:</strong> VMware Guest Operations (Invoke-VMScript)</p>
            <p><strong>Date:</strong> $(date)</p>
        </div>
    </div>
</body>
</html>
EOF

# Verify installation
echo "Verifying installation..."
nginx -v
systemctl is-active nginx

echo "Installation completed successfully!"
'@

    # Execute the installation script
    Write-Host "Executing installation script on guest OS..." -ForegroundColor Green
    
    $result = Invoke-VMScript -VM $vm `
                             -ScriptText $installScript `
                             -GuestUser $GuestUsername `
                             -GuestPassword $GuestPasswordSecure `
                             -ScriptType Bash `
                             -ErrorAction Stop
    
    # Display the output
    Write-Host "`nInstallation Output:" -ForegroundColor Yellow
    Write-Host $result.ScriptOutput
    
    if ($result.ExitCode -ne 0) {
        throw "Installation script failed with exit code: $($result.ExitCode)"
    }
    
    # Get VM IP addresses
    Write-Host "`nGetting VM network information..." -ForegroundColor Green
    $vmGuest = Get-VMGuest -VM $vm
    $ipAddresses = $vmGuest.IPAddress | Where-Object { $_ -match '\d+\.\d+\.\d+\.\d+' -and $_ -ne '127.0.0.1' }
    
    # Display success message
    Write-Host "`n==================== Installation Complete ====================" -ForegroundColor Green
    Write-Host "Nginx has been successfully installed on $VMName!" -ForegroundColor Green
    
    if ($ipAddresses) {
        Write-Host "`nYou can access nginx at:" -ForegroundColor Yellow
        foreach ($ip in $ipAddresses) {
            Write-Host "  Default page: http://$ip/" -ForegroundColor Cyan
            Write-Host "  PowerCLI test page: http://$ip/powercli-test.html" -ForegroundColor Cyan
        }
    }
    
    Write-Host "`nVM Details:" -ForegroundColor Yellow
    Write-Host "  VM Name: $($vm.Name)" -ForegroundColor Cyan
    Write-Host "  Power State: $($vm.PowerState)" -ForegroundColor Cyan
    Write-Host "  Guest OS: $($vmGuest.OSFullName)" -ForegroundColor Cyan
    Write-Host "  VMware Tools: $($vm.Guest.ToolsStatus)" -ForegroundColor Cyan
    
    Write-Host "==============================================================" -ForegroundColor Green
    
} catch {
    Write-Error "Script execution failed: $_"
    exit 1
} finally {
    # Disconnect from vCenter
    if ($connection) {
        Write-Host "`nDisconnecting from vCenter..." -ForegroundColor Yellow
        Disconnect-VIServer -Server $vCenterServer -Confirm:$false
    }
}