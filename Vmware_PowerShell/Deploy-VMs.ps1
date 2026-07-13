<#
.SYNOPSIS
    Interactive VM deployment script - replaces all Popultion_Template-*.ps1 scripts.
.DESCRIPTION
    Connects to vCenter, auto-discovers templates/hosts/datastores, and deploys VMs
    interactively. Distributes VMs equally across hosts in sequential blocks.
    Supports single datastore or split FC + iSCSI deployments.

    The script walks you through 4 steps:
      1. Pick a template (auto-discovered from vCenter)
      2. Set VM name prefix, count, and starting index
      3. Pick ESXi hosts (auto-discovered, select all or specific ones)
      4. Pick datastores (single or split FC + iSCSI)

    VMs are distributed in equal sequential blocks:
      Host 1: vm-1..10, Host 2: vm-11..20, Host 3: vm-21..30, etc.
.PARAMETER Server
    vCenter server FQDN (default: $env:VCENTER_HOSTNAME).
.PARAMETER User
    vCenter username (default: administrator@vsphere.local).
.PARAMETER DryRun
    Show deployment plan without creating VMs.
.PARAMETER Help
    Show this help message.
.EXAMPLE
    ./Deploy-VMs.ps1
    Interactive wizard - prompts for all values.
.EXAMPLE
    ./Deploy-VMs.ps1 -DryRun
    Interactive wizard but only shows the plan, does not create VMs.
.EXAMPLE
    ./Deploy-VMs.ps1 -Server "other-vcenter.lab.local"
    Connect to a different vCenter server.
.EXAMPLE
    Get-Help ./Deploy-VMs.ps1 -Full
    Show full help documentation.
#>

[CmdletBinding()]
param(
    [string]$Server = $env:VCENTER_HOSTNAME,
    [string]$User   = "administrator@vsphere.local",
    [switch]$DryRun,
    [Alias("h","?")]
    [switch]$Help
)

if (-not $Server) {
    Write-Host "ERROR: VCENTER_HOSTNAME environment variable not set." -ForegroundColor Red
    Write-Host "Current user: $env:USER" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Run with bws (recommended):" -ForegroundColor White
    Write-Host "  cd /home/$env:USER/git/mpqe-scale-scripts/MTV" -ForegroundColor White
    Write-Host "  ./run-with-secrets.sh pwsh ./Vmware_PowerShell/Deploy-VMs.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "Or: bws run -- pwsh ./Deploy-VMs.ps1 (from this directory)" -ForegroundColor White
    exit 1
}

if ($Help) {
    Write-Host ""
    Write-Host "  Deploy-VMs.ps1 -- Interactive VM Deployment Wizard" -ForegroundColor Cyan
    Write-Host "  ==================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Replaces all Popultion_Template-*.ps1 scripts with one dynamic script." -ForegroundColor White
    Write-Host "  Connects to vCenter, auto-discovers templates/hosts/datastores," -ForegroundColor White
    Write-Host "  and deploys VMs interactively in equal blocks across hosts." -ForegroundColor White
    Write-Host ""
    Write-Host "  USAGE:" -ForegroundColor Yellow
    Write-Host "    ./Deploy-VMs.ps1                        Interactive wizard" -ForegroundColor White
    Write-Host "    ./Deploy-VMs.ps1 -DryRun                Preview plan, no deployment" -ForegroundColor White
    Write-Host "    ./Deploy-VMs.ps1 -Server <vcenter>      Use different vCenter" -ForegroundColor White
    Write-Host "    ./Deploy-VMs.ps1 -Help                  Show this help" -ForegroundColor White
    Write-Host "    Get-Help ./Deploy-VMs.ps1 -Full         Full PowerShell help" -ForegroundColor White
    Write-Host ""
    Write-Host "  WORKFLOW:" -ForegroundColor Yellow
    Write-Host "    Step 1: Pick template(s)    (auto-discovered, supports multiple)" -ForegroundColor White
    Write-Host "    Step 2: Set prefix/count    (per template, e.g. rhel79-vm- x5, win2019-vm- x5)" -ForegroundColor White
    Write-Host "    Step 3: Pick ESXi hosts     (type 'all' or pick by number)" -ForegroundColor White
    Write-Host "    Step 4: Pick datastores     (single DS or split FC + iSCSI)" -ForegroundColor White
    Write-Host ""
    Write-Host "  MULTI-TEMPLATE:" -ForegroundColor Yellow
    Write-Host "    Mix RHEL + Windows in one run:" -ForegroundColor White
    Write-Host "      Template 1: rhel79-vm, 5 VMs (rhel79-fc-vm-1..5)" -ForegroundColor White
    Write-Host "      Template 2: win2019-vm, 5 VMs (win2019-fc-vm-1..5)" -ForegroundColor White
    Write-Host ""
    Write-Host "  DISTRIBUTION:" -ForegroundColor Yellow
    Write-Host "    80 VMs / 8 hosts = 10 per host:" -ForegroundColor White
    Write-Host "      Host 1: vm-1..10,  Host 2: vm-11..20,  Host 3: vm-21..30, etc." -ForegroundColor White
    Write-Host ""
    Write-Host "  SPLIT MODE (FC + iSCSI):" -ForegroundColor Yellow
    Write-Host "    50 on FC + 30 on iSCSI:" -ForegroundColor White
    Write-Host "      vm-1..50 -> FC datastore,  vm-51..80 -> iSCSI datastore" -ForegroundColor White
    Write-Host ""
    exit 0
}

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
$ErrorActionPreference = "Stop"
$sep = "=" * 80

function Show-Menu($Title, $Items, $DisplayProperty, $ExtraColumns) {
    Write-Host ""
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "  $("-" * ($Title.Length))" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $label = $Items[$i].$DisplayProperty
        $extra = ""
        if ($ExtraColumns) {
            $parts = @()
            foreach ($col in $ExtraColumns) {
                $val = $Items[$i].$col
                if ($val) { $parts += "${col}: $val" }
            }
            if ($parts.Count -gt 0) { $extra = " ($($parts -join ', '))" }
        }
        Write-Host "    $($i + 1). $label$extra" -ForegroundColor White
    }
    Write-Host ""
}

function Pick-One($Title, $Items, $DisplayProperty, $ExtraColumns) {
    Show-Menu $Title $Items $DisplayProperty $ExtraColumns
    while ($true) {
        $input = Read-Host "  Select number"
        $idx = 0
        if ([int]::TryParse($input, [ref]$idx) -and $idx -ge 1 -and $idx -le $Items.Count) {
            return $Items[$idx - 1]
        }
        Write-Host "  Invalid selection. Enter 1-$($Items.Count)." -ForegroundColor Red
    }
}

function Pick-Many($Title, $Items, $DisplayProperty, $ExtraColumns) {
    Show-Menu $Title $Items $DisplayProperty $ExtraColumns
    while ($true) {
        $input = Read-Host "  Select numbers (comma-separated, or 'all')"
        if ($input -match '^[aA]') {
            return $Items
        }
        $indices = $input -split '[,\s]+' | ForEach-Object { $_.Trim() }
        $selected = @()
        $valid = $true
        foreach ($idx in $indices) {
            $n = 0
            if ([int]::TryParse($idx, [ref]$n) -and $n -ge 1 -and $n -le $Items.Count) {
                $selected += $Items[$n - 1]
            } else {
                $valid = $false
                break
            }
        }
        if ($valid -and $selected.Count -gt 0) {
            return @($selected | Sort-Object $DisplayProperty)
        }
        Write-Host "  Invalid. Use comma-separated numbers (e.g. 1,3,5) or 'all'." -ForegroundColor Red
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# CONNECT TO VCENTER
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host $sep -ForegroundColor Cyan
Write-Host "  VM DEPLOYMENT WIZARD" -ForegroundColor Cyan
Write-Host $sep -ForegroundColor Cyan
Write-Host ""
Write-Host "  Connecting to vCenter: $Server" -ForegroundColor Yellow

$cred = Get-Credential -UserName $User -Message "Enter vCenter credentials for $Server"

try {
    $viConn = Connect-VIServer -Server $Server -Credential $cred -ErrorAction Stop
    Write-Host "  Connected to $($viConn.Name) (v$($viConn.Version))" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Failed to connect: $_" -ForegroundColor Red
    exit 1
}

try {

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: PICK TEMPLATES AND VM DETAILS
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n  Discovering templates..." -ForegroundColor Yellow
$allTemplates = Get-Template | Sort-Object Name | ForEach-Object {
    $tmpl = $_
    $guestFull = $tmpl.ExtensionData.Config.GuestFullName
    $guestShort = $guestFull -replace 'Red Hat Enterprise Linux \d+.*', 'RHEL' `
                             -replace 'Microsoft Windows Server ', 'Windows Server ' `
                             -replace 'Microsoft Windows ', 'Windows '

    $disks = $tmpl.ExtensionData.Config.Hardware.Device |
        Where-Object { $_ -is [VMware.Vim.VirtualDisk] }
    $diskCount = $disks.Count
    $totalGB   = [math]::Round(($disks | Measure-Object -Property CapacityInKB -Sum).Sum / 1MB, 0)
    if (-not $diskCount) { $diskCount = 0; $totalGB = 0 }

    $dsName = (Get-Datastore -Id $tmpl.DatastoreIdList[0]).Name

    [PSCustomObject]@{
        Name      = $tmpl.Name
        GuestOS   = $guestShort
        Disks     = "${diskCount}x ${totalGB} GB"
        Datastore = $dsName
        _obj      = $tmpl
    }
}

if ($allTemplates.Count -eq 0) {
    Write-Host "  ERROR: No templates found in vCenter." -ForegroundColor Red
    exit 1
}

$templateGroups = @()
$addMore = $true

while ($addMore) {
    $groupNum = $templateGroups.Count + 1
    if ($groupNum -gt 1) {
        Write-Host ""
        Write-Host "  --- Adding template group $groupNum ---" -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Host "  Available Templates" -ForegroundColor Cyan
    Write-Host "  -------------------" -ForegroundColor Cyan
    $dsGroups = $allTemplates | Group-Object Datastore | Sort-Object Name
    $tIdx = 0
    foreach ($dsg in $dsGroups) {
        $dsShort = $dsg.Name -replace '^InfraTemplates_Global_?', ''
        if (-not $dsShort) { $dsShort = $dsg.Name }
        Write-Host ""
        Write-Host "  [$dsShort] $($dsg.Name)" -ForegroundColor Yellow
        foreach ($t in $dsg.Group) {
            $tIdx++
            Write-Host "    $tIdx. $($t.Name) ($($t.GuestOS), $($t.Disks))" -ForegroundColor White
        }
    }
    Write-Host ""
    $selectedTemplate = $null
    while (-not $selectedTemplate) {
        $tInput = Read-Host "  Select template number"
        $tNum = 0
        if ([int]::TryParse($tInput, [ref]$tNum) -and $tNum -ge 1 -and $tNum -le $allTemplates.Count) {
            $flatIdx = 0
            foreach ($dsg in $dsGroups) {
                foreach ($t in $dsg.Group) {
                    $flatIdx++
                    if ($flatIdx -eq $tNum) { $selectedTemplate = $t; break }
                }
                if ($selectedTemplate) { break }
            }
        } else {
            Write-Host "  Invalid. Enter 1-$($allTemplates.Count)." -ForegroundColor Red
        }
    }
    Write-Host "  -> Template: $($selectedTemplate.Name)" -ForegroundColor Green

    Write-Host ""
    $prefix = (Read-Host "  VM name prefix for '$($selectedTemplate.Name)' (e.g. rhel79-50gb-70usage-vm-)").Trim()
    if (-not $prefix.EndsWith("-")) {
        $addDash = Read-Host "  Add trailing dash to prefix? (y/n)"
        if ($addDash -match '^[yY]') { $prefix += "-" }
    }

    $count = 0
    while ($count -le 0) {
        $numInput = Read-Host "  How many VMs for '$($selectedTemplate.Name)'?"
        [int]::TryParse($numInput, [ref]$count) | Out-Null
    }

    $exactName = $false
    if ($count -eq 1 -and -not $prefix.EndsWith("-")) {
        $exactAnswer = Read-Host "  Use '$prefix' as exact VM name (no number suffix)? (y/n)"
        $exactName = $exactAnswer -match '^[yY]'
    }

    $startIdx = 1
    if (-not $exactName) {
        $startInput = Read-Host "  Starting index (default: 1)"
        if ($startInput -and [int]::TryParse($startInput, [ref]$startIdx)) {} else { $startIdx = 1 }
        Write-Host "  -> $count VMs: ${prefix}${startIdx} through ${prefix}$($startIdx + $count - 1)" -ForegroundColor Green
    } else {
        Write-Host "  -> 1 VM: $prefix" -ForegroundColor Green
    }

    $templateGroups += [PSCustomObject]@{
        TemplateName = $selectedTemplate.Name
        TemplateObj  = $selectedTemplate._obj
        VMNamePrefix = $prefix
        NumVMs       = $count
        StartIndex   = $startIdx
        ExactName    = $exactName
    }

    $moreAnswer = Read-Host "`n  Add another template? (y/n)"
    $addMore = $moreAnswer -match '^[yY]'
}

$totalVMs = ($templateGroups | Measure-Object -Property NumVMs -Sum).Sum
Write-Host ""
Write-Host "  Total: $totalVMs VMs across $($templateGroups.Count) template(s)" -ForegroundColor Green
foreach ($tg in $templateGroups) {
    if ($tg.ExactName) {
        Write-Host "    - $($tg.TemplateName): 1 VM ($($tg.VMNamePrefix))" -ForegroundColor White
    } else {
        Write-Host "    - $($tg.TemplateName): $($tg.NumVMs) VMs ($($tg.VMNamePrefix)$($tg.StartIndex)..$($tg.VMNamePrefix)$($tg.StartIndex + $tg.NumVMs - 1))" -ForegroundColor White
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: PICK ESXI HOSTS
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n  Discovering ESXi hosts..." -ForegroundColor Yellow
$allHosts = Get-VMHost | Sort-Object Name | ForEach-Object {
    [PSCustomObject]@{
        Name    = $_.Name
        State   = $_.ConnectionState
        Cluster = $_.Parent.Name
        MemGB   = "$([math]::Round($_.MemoryUsageGB,0))/$([math]::Round($_.MemoryTotalGB,0)) GB"
        _obj    = $_
    }
}

if ($allHosts.Count -eq 0) {
    Write-Host "  ERROR: No ESXi hosts found." -ForegroundColor Red
    exit 1
}

$selectedHosts = Pick-Many "ESXi Hosts (select hosts to deploy on)" $allHosts "Name" @("State","Cluster","MemGB")
$ESXiHosts     = @($selectedHosts | ForEach-Object { $_.Name })
$hostObjects   = @{}
$selectedHosts | ForEach-Object { $hostObjects[$_.Name] = $_._obj }
$hostCount     = $ESXiHosts.Count

Write-Host "  -> Selected $hostCount host(s)" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: PICK DATASTORES
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n  Discovering datastores..." -ForegroundColor Yellow
$rawDatastores = Get-Datastore | Where-Object { $_.Name -notmatch '^InfraTemplates_' }

$sharedDatastores = $rawDatastores | Where-Object {
    $_.ExtensionData.Host.Count -gt 1
} | Sort-Object Name | ForEach-Object {
    $hostCnt = $_.ExtensionData.Host.Count
    [PSCustomObject]@{
        Name       = $_.Name
        Free       = "$([math]::Round($_.FreeSpaceGB,0)) GB free"
        Capacity   = "$([math]::Round($_.CapacityGB,0)) GB"
        Hosts      = "$hostCnt hosts"
        _obj       = $_
    }
}

$localDatastores = $rawDatastores | Where-Object {
    $_.ExtensionData.Host.Count -le 1
} | Sort-Object Name | ForEach-Object {
    $shortHost = "N/A"
    if ($_.ExtensionData.Host.Count -gt 0) {
        $hostView = Get-View $_.ExtensionData.Host[0].Key -Property Name
        $shortHost = $hostView.Name.Split('.')[0]
    }
    [PSCustomObject]@{
        Name       = $_.Name
        Free       = "$([math]::Round($_.FreeSpaceGB,0)) GB free"
        Capacity   = "$([math]::Round($_.CapacityGB,0)) GB"
        Hosts      = $shortHost
        _obj       = $_
    }
}

if ($sharedDatastores.Count -eq 0 -and $localDatastores.Count -eq 0) {
    Write-Host "  ERROR: No datastores found." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  Shared Datastores (available to multiple hosts):" -ForegroundColor Cyan
Write-Host "  ------------------------------------------------" -ForegroundColor Cyan
$dsChoices = @()
$dsIndex = 1
foreach ($ds in $sharedDatastores) {
    Write-Host "    $dsIndex. $($ds.Name) ($($ds.Free), $($ds.Capacity), $($ds.Hosts))" -ForegroundColor White
    $dsChoices += $ds
    $dsIndex++
}

if ($localDatastores.Count -gt 0) {
    Write-Host ""
    Write-Host "  Local Datastores (single host):" -ForegroundColor DarkGray
    Write-Host "  -------------------------------" -ForegroundColor DarkGray
    foreach ($ds in $localDatastores) {
        Write-Host "    $dsIndex. $($ds.Name) ($($ds.Free), $($ds.Capacity), $($ds.Hosts))" -ForegroundColor DarkGray
        $dsChoices += $ds
        $dsIndex++
    }
}

Write-Host ""
$dsNum1 = 0
while ($dsNum1 -lt 1 -or $dsNum1 -gt $dsChoices.Count) {
    $dsInput = Read-Host "  Select PRIMARY datastore (number)"
    [int]::TryParse($dsInput, [ref]$dsNum1) | Out-Null
}
$selectedDS   = $dsChoices[$dsNum1 - 1]
$Datastore    = $selectedDS.Name
$datastoreObj = $selectedDS._obj
Write-Host "  -> Primary: $Datastore" -ForegroundColor Green

$splitMode       = $false
$Datastore2      = ""
$NumVMsDS1       = 0
$datastoreObj2   = $null

$splitAnswer = Read-Host "`n  Split VMs across 2 datastores? (y/n)"
if ($splitAnswer -match '^[yY]') {
    $dsNum2 = 0
    while ($dsNum2 -lt 1 -or $dsNum2 -gt $dsChoices.Count -or $dsNum2 -eq $dsNum1) {
        $dsInput2 = Read-Host "  Select SECONDARY datastore (number)"
        [int]::TryParse($dsInput2, [ref]$dsNum2) | Out-Null
        if ($dsNum2 -eq $dsNum1) {
            Write-Host "  Cannot be the same as primary. Pick a different one." -ForegroundColor Red
            $dsNum2 = 0
        }
    }
    $ds2Obj        = $dsChoices[$dsNum2 - 1]
    $Datastore2    = $ds2Obj.Name
    $datastoreObj2 = $ds2Obj._obj

    while ($NumVMsDS1 -le 0 -or $NumVMsDS1 -ge $totalVMs) {
        $ds1Input = Read-Host "  How many VMs on PRIMARY ($Datastore)? (1-$($totalVMs - 1))"
        [int]::TryParse($ds1Input, [ref]$NumVMsDS1) | Out-Null
    }
    $splitMode  = $true
    $NumVMsDS2  = $totalVMs - $NumVMsDS1
    Write-Host "  -> $NumVMsDS1 VMs on $Datastore + $NumVMsDS2 VMs on $Datastore2" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════════
# COMPUTE VM DISTRIBUTION
# ═══════════════════════════════════════════════════════════════════════════════

$allVMs = @()
$globalVMIndex = 0

foreach ($tg in $templateGroups) {
    $basePerHost = [math]::Floor($tg.NumVMs / $hostCount)
    $remainder   = $tg.NumVMs % $hostCount
    $vmCursor    = $tg.StartIndex

    for ($h = 0; $h -lt $hostCount; $h++) {
        $count = $basePerHost
        if ($h -lt $remainder) { $count++ }

        for ($v = $vmCursor; $v -lt ($vmCursor + $count); $v++) {
            $prefix = $tg.VMNamePrefix
            $vmName = if ($tg.ExactName) { $prefix } else { "${prefix}${v}" }

            if ($splitMode) {
                if ($globalVMIndex -lt $NumVMsDS1) {
                    $ds = $Datastore
                } else {
                    $ds = $Datastore2
                }
            } else {
                $ds = $Datastore
            }

            $allVMs += [PSCustomObject]@{
                VMName       = $vmName
                VMNumber     = $v
                Host         = $ESXiHosts[$h]
                Datastore    = $ds
                TemplateName = $tg.TemplateName
                TemplateObj  = $tg.TemplateObj
            }
            $globalVMIndex++
        }
        $vmCursor += $count
    }
}

$deploymentPlan = @()
foreach ($hostName in $ESXiHosts) {
    $hostVMs = $allVMs | Where-Object { $_.Host -eq $hostName }
    if ($hostVMs.Count -eq 0) { continue }

    $rangeDisplay = ($hostVMs | Group-Object TemplateName | ForEach-Object {
        $first = $_.Group[0].VMName
        $last  = $_.Group[-1].VMName
        if ($first -eq $last) { $first } else { "$first..$last" }
    }) -join ", "

    $dsDisplay = $Datastore
    if ($splitMode) {
        $ds1Count = ($hostVMs | Where-Object { $_.Datastore -eq $Datastore }).Count
        $ds2Count = ($hostVMs | Where-Object { $_.Datastore -eq $Datastore2 }).Count
        if ($ds1Count -gt 0 -and $ds2Count -gt 0) {
            $dsDisplay = "$Datastore x$ds1Count + $Datastore2 x$ds2Count"
        } elseif ($ds1Count -gt 0) {
            $dsDisplay = $Datastore
        } else {
            $dsDisplay = $Datastore2
        }
    }

    $hIdx = [array]::IndexOf($ESXiHosts, $hostName) + 1
    $deploymentPlan += [PSCustomObject]@{
        HostIndex  = $hIdx
        HostName   = $hostName
        VMCount    = $hostVMs.Count
        VMRange    = $rangeDisplay
        Datastores = $dsDisplay
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# DISPLAY DEPLOYMENT PLAN
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host $sep -ForegroundColor Cyan
Write-Host "  DEPLOYMENT PLAN" -ForegroundColor Cyan
Write-Host $sep -ForegroundColor Cyan
Write-Host ""
Write-Host "  vCenter       : $Server" -ForegroundColor White
Write-Host "  Templates     : $($templateGroups.Count)" -ForegroundColor White
foreach ($tg in $templateGroups) {
    Write-Host "    - $($tg.TemplateName): $($tg.NumVMs) VMs (prefix: $($tg.VMNamePrefix))" -ForegroundColor White
}
Write-Host "  Total VMs     : $totalVMs" -ForegroundColor White
Write-Host "  Hosts         : $hostCount" -ForegroundColor White
if ($splitMode) {
    Write-Host "  DS Primary    : $Datastore ($NumVMsDS1 VMs)" -ForegroundColor White
    Write-Host "  DS Secondary  : $Datastore2 ($NumVMsDS2 VMs)" -ForegroundColor White
} else {
    Write-Host "  Datastore     : $Datastore" -ForegroundColor White
}
Write-Host ""

$deploymentPlan | Select-Object HostIndex, HostName, VMCount, VMRange, Datastores |
    Format-Table -AutoSize | Out-String | Write-Host

foreach ($plan in $deploymentPlan) {
    $hostShort = $plan.HostName.Split('.')[0]
    $hostVMs   = $allVMs | Where-Object { $_.Host -eq $plan.HostName }

    Write-Host "  Host $($plan.HostIndex) ($hostShort) - $($plan.VMCount) VMs -> $($plan.Datastores)" -ForegroundColor Cyan
    Write-Host "  $("-" * 60)" -ForegroundColor DarkGray

    $hostVMs | Group-Object Datastore | ForEach-Object {
        $dsName = $_.Name
        $vmNames = $_.Group | ForEach-Object { $_.VMName }
        $cols = 4
        for ($r = 0; $r -lt $vmNames.Count; $r += $cols) {
            $row = $vmNames[$r..[math]::Min($r + $cols - 1, $vmNames.Count - 1)]
            Write-Host "    $($row -join '  ')" -ForegroundColor White
        }
    }
    Write-Host ""
}

if ($DryRun) {
    Write-Host $sep -ForegroundColor Yellow
    Write-Host "  DRY RUN -- No VMs were created." -ForegroundColor Yellow
    Write-Host $sep -ForegroundColor Yellow
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIRM AND DEPLOY
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host $sep -ForegroundColor Yellow
$confirm = Read-Host "  Deploy $totalVMs VMs now? (y/n)"
if ($confirm -notmatch '^[yY]') {
    Write-Host "  Cancelled." -ForegroundColor Yellow
    exit 0
}

$waitForClones = Read-Host "  Wait for all clones to complete? (y/n)"
$trackClones = $waitForClones -match '^[yY]'

Write-Host "`nDeploying..." -ForegroundColor Cyan
$totalCreated = 0
$totalFailed  = 0
$cloneTasks   = @()
$submitWatch  = [System.Diagnostics.Stopwatch]::StartNew()

$vmsByHost = $allVMs | Group-Object Host
foreach ($hostGroup in $vmsByHost) {
    $hostName = $hostGroup.Name
    $hostObj  = $hostObjects[$hostName]
    $hIdx     = [array]::IndexOf($ESXiHosts, $hostName) + 1

    Write-Host "`n--- Host ${hIdx}/${hostCount}: ${hostName} ($($hostGroup.Count) VMs) ---" -ForegroundColor Cyan

    foreach ($vm in $hostGroup.Group) {
        $vmDS = if ($splitMode -and $vm.Datastore -eq $Datastore2) { $datastoreObj2 } else { $datastoreObj }

        try {
            $task = New-VM -Name $vm.VMName -Template $vm.TemplateObj -Datastore $vmDS -VMHost $hostObj -RunAsync
            $cloneTasks += $task
            Write-Host "  [+] $($vm.VMName) ($($vm.TemplateName)) -> $($vm.Datastore)" -ForegroundColor Green
            $totalCreated++
        } catch {
            Write-Host "  [X] $($vm.VMName) FAILED: $_" -ForegroundColor Red
            $totalFailed++
        }
    }
}

$submitWatch.Stop()
$submitTime = $submitWatch.Elapsed

# ═══════════════════════════════════════════════════════════════════════════════
# WAIT FOR CLONE TASKS
# ═══════════════════════════════════════════════════════════════════════════════

$cloneTime = [TimeSpan]::Zero

if ($trackClones -and $cloneTasks.Count -gt 0) {
    Write-Host ""
    Write-Host $sep -ForegroundColor Yellow
    Write-Host "  Waiting for $($cloneTasks.Count) clone tasks to complete..." -ForegroundColor Yellow
    Write-Host $sep -ForegroundColor Yellow

    $cloneWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $taskIds      = @{}
    $cloneTasks | ForEach-Object { $taskIds[$_.Id] = "Running" }
    $total        = $cloneTasks.Count
    $doneCount    = 0
    $failCount    = 0

    while ($true) {
        $currentTasks = Get-Task | Where-Object { $taskIds.ContainsKey($_.Id) }
        foreach ($t in $currentTasks) {
            if ($t.State -eq "Success" -and $taskIds[$t.Id] -ne "Success") {
                $taskIds[$t.Id] = "Success"
                $doneCount++
            } elseif ($t.State -eq "Error" -and $taskIds[$t.Id] -ne "Error") {
                $taskIds[$t.Id] = "Error"
                $failCount++
            } elseif ($t.State -eq "Running") {
                $taskIds[$t.Id] = "Running"
            } elseif ($t.State -eq "Queued") {
                $taskIds[$t.Id] = "Queued"
            }
        }

        $running = ($taskIds.Values | Where-Object { $_ -eq "Running" }).Count
        $queued  = ($taskIds.Values | Where-Object { $_ -eq "Queued" }).Count
        $totalDone = $doneCount + $failCount
        $timestamp = Get-Date -Format "HH:mm:ss"
        $elapsed   = [math]::Round($cloneWatch.Elapsed.TotalSeconds, 0)
        $pctDone   = [math]::Round(($totalDone / $total) * 100, 0)

        $status = "  [$timestamp] $doneCount/$total completed"
        if ($running -gt 0) { $status += ", $running cloning" }
        if ($queued -gt 0)  { $status += ", $queued queued" }
        if ($failCount -gt 0) { $status += ", $failCount failed" }
        $status += " ($pctDone%) - ${elapsed}s"
        Write-Host $status -ForegroundColor Yellow

        if ($totalDone -ge $total) {
            break
        }
        if ($running -eq 0 -and $queued -eq 0 -and $currentTasks.Count -eq 0) {
            Write-Host "  No more active tasks found. Verifying VM count..." -ForegroundColor Yellow
            $actualVMs = 0
            foreach ($tg in $templateGroups) {
                $p = $tg.VMNamePrefix
                $actualVMs += (Get-VM -Name "${p}*" -ErrorAction SilentlyContinue).Count
            }
            if ($actualVMs -ge $total) {
                $doneCount = $total
                Write-Host "  All $total VMs confirmed." -ForegroundColor Green
                break
            }
        }
        Start-Sleep -Seconds 15
    }

    $cloneWatch.Stop()
    $cloneTime = $cloneWatch.Elapsed

    if ($failCount -gt 0) {
        Write-Host ""
        Write-Host "  $failCount clone task(s) failed." -ForegroundColor Red

        $failedVMNames = @()
        foreach ($entry in $taskIds.GetEnumerator()) {
            if ($entry.Value -eq "Error") {
                $t = Get-Task -Id $entry.Key -ErrorAction SilentlyContinue
                if ($t) {
                    Write-Host "    FAILED: $($t.ExtensionData.Info.EntityName) - $($t.ExtensionData.Info.Error.LocalizedMessage)" -ForegroundColor Red
                    $failedVMNames += $t.ExtensionData.Info.EntityName
                }
            }
        }

        $retryAnswer = Read-Host "`n  Retry $failCount failed clones? (y/n)"
        if ($retryAnswer -match '^[yY]') {
            Write-Host "  Retrying failed clones..." -ForegroundColor Yellow
            $retryTasks = @()
            foreach ($fName in $failedVMNames) {
                $origVM = $allVMs | Where-Object { $_.VMName -eq $fName }
                if ($origVM) {
                    $hostObj = $hostObjects[$origVM.Host]
                    $vmDS = if ($splitMode -and $origVM.Datastore -eq $Datastore2) { $datastoreObj2 } else { $datastoreObj }
                    try {
                        $rt = New-VM -Name $origVM.VMName -Template $origVM.TemplateObj -Datastore $vmDS -VMHost $hostObj -RunAsync
                        $retryTasks += $rt
                        $taskIds[$rt.Id] = "Running"
                        Write-Host "  [R] $fName -> retrying" -ForegroundColor Yellow
                    } catch {
                        Write-Host "  [X] $fName retry FAILED: $_" -ForegroundColor Red
                    }
                }
            }
            if ($retryTasks.Count -gt 0) {
                Write-Host "  Waiting for $($retryTasks.Count) retries..." -ForegroundColor Yellow
                $retryDone = 0
                while ($retryDone -lt $retryTasks.Count) {
                    Start-Sleep -Seconds 15
                    $retryDone = 0
                    foreach ($rt in $retryTasks) {
                        $st = (Get-Task -Id $rt.Id -ErrorAction SilentlyContinue).State
                        if ($st -eq "Success") {
                            if ($taskIds[$rt.Id] -ne "Success") {
                                $taskIds[$rt.Id] = "Success"
                                $doneCount++
                                $failCount--
                            }
                            $retryDone++
                        } elseif ($st -eq "Error") {
                            $retryDone++
                        }
                    }
                    $elapsed = [math]::Round($cloneWatch.Elapsed.TotalSeconds, 0)
                    Write-Host "  [$( Get-Date -Format 'HH:mm:ss')] Retries: $retryDone/$($retryTasks.Count) done - ${elapsed}s" -ForegroundColor Yellow
                }
            }
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

$totalTime = $submitTime + $cloneTime

function Format-Elapsed($ts) {
    if ($ts.TotalMinutes -ge 1) {
        return "$([math]::Floor($ts.TotalMinutes))m $($ts.Seconds)s"
    }
    return "$([math]::Round($ts.TotalSeconds, 1))s"
}

Write-Host ""
Write-Host $sep -ForegroundColor Cyan
Write-Host "  DEPLOYMENT COMPLETE" -ForegroundColor Cyan
Write-Host $sep -ForegroundColor Cyan
Write-Host "  Total requested : $totalVMs" -ForegroundColor White
foreach ($tg in $templateGroups) {
    Write-Host "    - $($tg.TemplateName): $($tg.NumVMs)" -ForegroundColor White
}
Write-Host "  Submitted       : $totalCreated" -ForegroundColor White
if ($totalFailed -gt 0) {
    Write-Host "  Submit failures : $totalFailed" -ForegroundColor Red
}
if ($trackClones -and $cloneTasks.Count -gt 0) {
    Write-Host "  Cloned OK       : $doneCount" -ForegroundColor Green
    if ($failCount -gt 0) {
        Write-Host "  Clone failed    : $failCount" -ForegroundColor Red
    }
    Write-Host "  Submit time     : $(Format-Elapsed $submitTime)" -ForegroundColor White
    Write-Host "  Clone time      : $(Format-Elapsed $cloneTime)" -ForegroundColor White
    Write-Host "  Total time      : $(Format-Elapsed $totalTime)" -ForegroundColor White
} else {
    Write-Host "  Submit time     : $(Format-Elapsed $submitTime)" -ForegroundColor White
    Write-Host "  Note            : Clone tasks running in background. Use Verify-VMs.ps1 to check." -ForegroundColor Yellow
}
Write-Host $sep -ForegroundColor Cyan
Write-Host ""

} finally {
    Disconnect-VIServer -Server $Server -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Disconnected from $Server." -ForegroundColor Yellow
}
