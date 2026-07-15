# ==============================================================================
#                      vCenter Connection Configuration
# ==============================================================================
# Credentials loaded from environment variables (set via bws run or .env)
$vcenter_server = if ($env:VCENTER_HOSTNAME) { $env:VCENTER_HOSTNAME } else { "vcenter.example.com" }
$user = if ($env:vsphere_user) { $env:vsphere_user } else { "administrator@vsphere.local" }
$pass = if ($env:vsphere_pw) { $env:vsphere_pw } else { throw "vsphere_pw environment variable not set" }

# ==============================================================================
#                          VM Deployment Parameters
# ==============================================================================
$Datastore = "$yourDS"
$VMNamePrefix = "$your_vm_prefix"
$StartIndex = $int      # Starting number for VM names
$NumVMs = $int        # Number of VMs to create


# ==============================================================================
#                             Main Script Logic
# ==============================================================================

# Connect to vCenter Server
Write-Host "Connecting to vCenter Server '$vcenter_server'..."
try {
    Connect-VIServer -Server $vcenter_server -User $user -Password $pass -ErrorAction Stop | Out-Null
    Write-Host "Successfully connected to vCenter Server." -ForegroundColor Green
}
catch {
    Write-Host "Error: Failed to connect to vCenter Server. Please check credentials and server name." -ForegroundColor Red
    return
}


# Get all the VMs in a single batch to avoid multiple Get-VM calls
Write-Host "Retrieving all VMs with prefix '$VMNamePrefix'..."
$vms = @()
for ($i = $StartIndex; $i -lt ($StartIndex + $NumVMs); $i++) {
    $vmName = $VMNamePrefix + $i
    $vms += Get-VM -Name $vmName
}

if ($vms.Count -eq 0) {
    Write-Host "Error: No VMs found with the specified prefix. Cannot proceed." -ForegroundColor Red
    Disconnect-VIServer -Server $vcenter_server -Confirm:$false
    return
}

# Process each VM to enable CBT
Write-Host "Starting CBT enablement process for $($vms.Count) VMs..." -ForegroundColor Cyan
$vmCounter = 0
foreach ($vm in $vms) {
    $vmCounter++
    $vmName = $vm.Name
    $progress = ($vmCounter / $vms.Count) * 100
    Write-Progress -Activity "Enabling CBT on VMs" -Status "Processing VM $vmName ($vmCounter of $($vms.Count))" -PercentComplete $progress

    Write-Host "--- Processing VM: $vmName ---"

    # Step 1: Check VM power state and power it off if necessary
    if ($vm.PowerState -eq "PoweredOn") {
        Write-Host "VM is powered on. Powering it off to enable CBT..."
        Stop-VM -VM $vm -Confirm:$false -RunAsync
        Get-Task -VM $vm | Where-Object {$_.Name -eq "Stop-VM"} | Wait-Task
        Write-Host "VM '$vmName' is now powered off."
    }
    else {
        Write-Host "VM is already powered off. Proceeding..."
    }

    # Step 2: Check CBT status and enable if needed
    $vmView = $vm | Get-View
    if ($vmView.Config.ChangeTrackingEnabled -eq $false) {
        Write-Host "CBT is currently disabled. Enabling it now..."
        $vmConfigSpec = New-Object VMware.Vim.VirtualMachineConfigSpec
        $vmConfigSpec.changeTrackingEnabled = $true
        
        # Apply the configuration change
        $vmView.ReconfigVM($vmConfigSpec)
        
        # Step 3: Take and remove a snapshot to activate CBT
        Write-Host "Creating temporary snapshot to activate CBT..."
        $snap = New-Snapshot -VM $vm -Name "CBTSnap" -Description "Temporary snapshot to enable CBT" -Confirm:$false
        Write-Host "Removing temporary snapshot..."
        Remove-Snapshot -Snapshot $snap -Confirm:$false
        Write-Host "CBT has been enabled and activated for VM '$vmName'." -ForegroundColor Green
    }
    else {
        Write-Host "CBT is already enabled on VM '$vmName'. No changes made." -ForegroundColor Yellow
    }
}
Write-Host "CBT enablement process completed for all VMs." -ForegroundColor Green


# ==============================================================================
#                       Verification and Final Report
# ==============================================================================
Write-Host ""
Write-Host "--- Final CBT Status Verification ---" -ForegroundColor Cyan
$cbtStatus = @()
$vmCounter = 0
foreach ($vm in $vms) {
    $vmCounter++
    $progress = ($vmCounter / $vms.Count) * 100
    Write-Progress -Activity "Verifying CBT Status" -Status "Checking VM $($vm.Name) ($vmCounter of $($vms.Count))" -PercentComplete $progress

    $vmView = $vm | Get-View
    $cbtStatus += [pscustomobject]@{
        VMName = $vm.Name
        CBTEnabled = $vmView.Config.ChangeTrackingEnabled
    }
}

$cbtStatus | Format-Table -AutoSize

# Check if all VMs have CBT enabled for a final summary
$allEnabled = ($cbtStatus | Where-Object {$_.CBTEnabled -eq $false}).Count -eq 0
if ($allEnabled) {
    Write-Host "SUCCESS: All $($vms.Count) VMs now have CBT enabled." -ForegroundColor Green
}
else {
    Write-Host "WARNING: Not all VMs have CBT enabled. Please review the report." -ForegroundColor Yellow
}


# ==============================================================================
#                       Disconnect from vCenter
# ==============================================================================
Write-Host "Disconnecting from vCenter Server..."
Disconnect-VIServer -Server $vcenter_server -Confirm:$false
Write-Host "Disconnected successfully." -ForegroundColor Green
