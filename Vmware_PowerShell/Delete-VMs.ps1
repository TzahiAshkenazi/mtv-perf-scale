<#
.SYNOPSIS
    Interactive VM deletion script - replaces all Delete_population-Template-*.ps1 scripts.
.DESCRIPTION
    Connects to vCenter, auto-discovers VMs by prefix, shows what will be deleted
    with per-host breakdown, and deletes after confirmation. Supports power-off
    before deletion for running VMs.
.PARAMETER Server
    vCenter server FQDN (default: $env:VCENTER_HOSTNAME).
.PARAMETER User
    vCenter username (default: administrator@vsphere.local).
.PARAMETER DryRun
    Show deletion plan without deleting any VMs.
.PARAMETER Help
    Show this help message.
.EXAMPLE
    ./Delete-VMs.ps1
.EXAMPLE
    ./Delete-VMs.ps1 -DryRun
.EXAMPLE
    ./Delete-VMs.ps1 -Help
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
    Write-Host "  ./run-with-secrets.sh pwsh ./Vmware_PowerShell/Delete-VMs.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "Or: bws run -- pwsh ./Delete-VMs.ps1 (from this directory)" -ForegroundColor White
    exit 1
}

if ($Help) {
    Write-Host ""
    Write-Host "  Delete-VMs.ps1 -- Interactive VM Deletion" -ForegroundColor Cyan
    Write-Host "  ===========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Replaces all Delete_population-Template-*.ps1 scripts." -ForegroundColor White
    Write-Host "  Connects to vCenter, finds VMs by prefix, shows deletion plan," -ForegroundColor White
    Write-Host "  and deletes after confirmation." -ForegroundColor White
    Write-Host ""
    Write-Host "  USAGE:" -ForegroundColor Yellow
    Write-Host "    ./Delete-VMs.ps1                        Interactive wizard" -ForegroundColor White
    Write-Host "    ./Delete-VMs.ps1 -DryRun                Preview plan, no deletion" -ForegroundColor White
    Write-Host "    ./Delete-VMs.ps1 -Server <vcenter>      Use different vCenter" -ForegroundColor White
    Write-Host "    ./Delete-VMs.ps1 -Help                  Show this help" -ForegroundColor White
    Write-Host ""
    Write-Host "  WORKFLOW:" -ForegroundColor Yellow
    Write-Host "    Step 1: Pick VM prefix     (auto-discovered from vCenter)" -ForegroundColor White
    Write-Host "    Step 2: Review VMs         (per-host breakdown with names)" -ForegroundColor White
    Write-Host "    Step 3: Confirm deletion   (type 'DELETE' to proceed)" -ForegroundColor White
    Write-Host ""
    Write-Host "  SAFETY:" -ForegroundColor Yellow
    Write-Host "    - Shows full list before deleting" -ForegroundColor White
    Write-Host "    - Requires typing 'DELETE' to confirm (not just y/n)" -ForegroundColor White
    Write-Host "    - Auto powers off running VMs before deletion" -ForegroundColor White
    Write-Host "    - DryRun mode to preview without deleting" -ForegroundColor White
    Write-Host ""
    exit 0
}

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
$ErrorActionPreference = "Stop"
$sep = "=" * 80

# ═══════════════════════════════════════════════════════════════════════════════
# CONNECT TO VCENTER
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host $sep -ForegroundColor Red
Write-Host "  VM DELETION WIZARD" -ForegroundColor Red
Write-Host $sep -ForegroundColor Red
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
# STEP 1: PICK VM PREFIX
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n  Discovering VMs..." -ForegroundColor Yellow
$allVMs = Get-VM | Where-Object {
    $_.Name -notmatch '^vCLS-' -and
    $_.Name -notmatch '^VMware vCenter' -and
    $_.Name -notmatch '(?i)backup' -and
    $_.Name -notmatch '(?i)template'
} | Sort-Object Name

$vmDsLookup = @{}
Get-View -ViewType VirtualMachine -Property Name, Config.DatastoreUrl | ForEach-Object {
    if ($_.Config.DatastoreUrl) {
        $vmDsLookup[$_.Name] = ($_.Config.DatastoreUrl | ForEach-Object { $_.Name }) -join ", "
    }
}

$grouped = $allVMs | ForEach-Object {
    if ($_.Name -match '^(.+?-)\d+$') {
        [PSCustomObject]@{ VM = $_.Name; Prefix = $Matches[1]; IsNumbered = $true }
    } else {
        [PSCustomObject]@{ VM = $_.Name; Prefix = $_.Name; IsNumbered = $false }
    }
}
$prefixes = $grouped | Group-Object Prefix | Sort-Object Count -Descending | ForEach-Object {
    $vmNames = $_.Group | ForEach-Object { $_.VM }
    $dsList = $vmNames | ForEach-Object { $vmDsLookup[$_] } |
        Where-Object { $_ } | Select-Object -Unique | Sort-Object
    [PSCustomObject]@{
        Prefix     = $_.Name
        Count      = $_.Count
        Datastores = ($dsList -join ", ")
    }
}

if ($prefixes.Count -eq 0) {
    Write-Host "  No VMs with numbered prefixes found." -ForegroundColor Yellow
    $manualPrefix = Read-Host "  Enter VM prefix to search for"
    $selectedPrefix = $manualPrefix
} else {
    Write-Host ""
    Write-Host "  Discovered VM Prefixes" -ForegroundColor Cyan
    Write-Host "  ----------------------" -ForegroundColor Cyan
    for ($i = 0; $i -lt $prefixes.Count; $i++) {
        Write-Host "    $($i + 1). $($prefixes[$i].Prefix) ($($prefixes[$i].Count) VMs) [$($prefixes[$i].Datastores)]" -ForegroundColor White
    }
    Write-Host "    M. Enter prefix manually" -ForegroundColor DarkGray
    Write-Host ""

    $selectedPrefix = ""
    while (-not $selectedPrefix) {
        $pickInput = Read-Host "  Select prefix to DELETE (number or M)"
        if ($pickInput -match '^[mM]') {
            $selectedPrefix = Read-Host "  Enter VM prefix"
        } else {
            $idx = 0
            if ([int]::TryParse($pickInput, [ref]$idx) -and $idx -ge 1 -and $idx -le $prefixes.Count) {
                $selectedPrefix = $prefixes[$idx - 1].Prefix
            } else {
                Write-Host "  Invalid selection." -ForegroundColor Red
            }
        }
    }
}

Write-Host "  -> Prefix: $selectedPrefix" -ForegroundColor Yellow

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: FIND AND DISPLAY VMs TO DELETE
# ═══════════════════════════════════════════════════════════════════════════════

$matchedVMs = $allVMs | Where-Object { $_.Name -like "${selectedPrefix}*" }
$totalFound = $matchedVMs.Count

if ($totalFound -eq 0) {
    Write-Host "`n  No VMs found with prefix '$selectedPrefix'. Nothing to delete." -ForegroundColor Yellow
    exit 0
}

$poweredOn  = ($matchedVMs | Where-Object { $_.PowerState -eq "PoweredOn" }).Count
$poweredOff = $totalFound - $poweredOn

Write-Host ""
Write-Host $sep -ForegroundColor Red
Write-Host "  DELETION PLAN: ${selectedPrefix}*" -ForegroundColor Red
Write-Host $sep -ForegroundColor Red
Write-Host ""
Write-Host "  Total VMs to delete : $totalFound" -ForegroundColor White
Write-Host "  Powered On          : $poweredOn" -ForegroundColor $(if ($poweredOn -gt 0) { "Yellow" } else { "Green" })
Write-Host "  Powered Off         : $poweredOff" -ForegroundColor White

if ($poweredOn -gt 0) {
    Write-Host ""
    Write-Host "  WARNING: $poweredOn VMs are powered on and will be stopped before deletion." -ForegroundColor Yellow
}

# Per-host breakdown
$hostGroups = $matchedVMs | Group-Object { $_.VMHost.Name } | Sort-Object Name

Write-Host ""
$hostIdx = 1
foreach ($hg in $hostGroups) {
    $hostShort = $hg.Name.Split('.')[0]
    $sortedVMs = $hg.Group | Sort-Object Name
    $onCount   = ($hg.Group | Where-Object { $_.PowerState -eq "PoweredOn" }).Count
    $stateInfo = if ($onCount -gt 0) { " ($onCount powered on)" } else { "" }

    Write-Host "  Host $hostIdx ($hostShort): $($hg.Count) VMs$stateInfo" -ForegroundColor Cyan
    Write-Host "  $("-" * 60)" -ForegroundColor DarkGray

    foreach ($vm in $sortedVMs) {
        $ds = if ($vmDsLookup[$vm.Name]) { $vmDsLookup[$vm.Name] } else { "unknown" }
        Write-Host "    $($vm.Name)  ->  $ds" -ForegroundColor White
    }
    Write-Host ""
    $hostIdx++
}

$dsGroups = $matchedVMs | ForEach-Object {
    [PSCustomObject]@{ VMName = $_.Name; DS = $(if ($vmDsLookup[$_.Name]) { $vmDsLookup[$_.Name] } else { "unknown" }) }
} | Group-Object DS | Sort-Object Count -Descending
Write-Host "  Datastores affected:" -ForegroundColor Cyan
foreach ($dg in $dsGroups) {
    Write-Host "    $($dg.Name): $($dg.Count) VMs" -ForegroundColor White
}

if ($DryRun) {
    Write-Host ""
    Write-Host $sep -ForegroundColor Yellow
    Write-Host "  DRY RUN -- No VMs were deleted." -ForegroundColor Yellow
    Write-Host $sep -ForegroundColor Yellow
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: CONFIRM AND DELETE
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host $sep -ForegroundColor Red
Write-Host "  WARNING: This will permanently delete $totalFound VMs!" -ForegroundColor Red
Write-Host $sep -ForegroundColor Red
Write-Host ""
$confirm = Read-Host "  Type 'DELETE' to confirm (anything else to cancel)"
if ($confirm -ne "DELETE") {
    Write-Host "  Cancelled. No VMs were deleted." -ForegroundColor Yellow
    exit 0
}

Write-Host "`n  Deleting VMs..." -ForegroundColor Red
$totalDeleted = 0
$totalFailed  = 0
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($hg in $hostGroups) {
    $hostShort = $hg.Name.Split('.')[0]
    Write-Host "`n  --- $hostShort ($($hg.Count) VMs) ---" -ForegroundColor Cyan

    foreach ($vm in ($hg.Group | Sort-Object Name)) {
        try {
            if ($vm.PowerState -eq "PoweredOn") {
                Stop-VM -VM $vm -Confirm:$false -ErrorAction Stop | Out-Null
                Write-Host "    [OFF] $($vm.Name)" -ForegroundColor Yellow
            }
            Remove-VM -VM $vm -DeletePermanently -Confirm:$false -ErrorAction Stop
            Write-Host "    [DEL] $($vm.Name)" -ForegroundColor Green
            $totalDeleted++
        } catch {
            Write-Host "    [X]   $($vm.Name) FAILED: $_" -ForegroundColor Red
            $totalFailed++
        }
    }
}

$stopwatch.Stop()

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host $sep -ForegroundColor Cyan
Write-Host "  DELETION COMPLETE" -ForegroundColor Cyan
Write-Host $sep -ForegroundColor Cyan
Write-Host "  Total targeted  : $totalFound" -ForegroundColor White
Write-Host "  Deleted         : $totalDeleted" -ForegroundColor Green
if ($totalFailed -gt 0) {
    Write-Host "  Failed          : $totalFailed" -ForegroundColor Red
}
Write-Host "  Elapsed         : $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s" -ForegroundColor White
Write-Host $sep -ForegroundColor Cyan
Write-Host ""

} finally {
    Disconnect-VIServer -Server $Server -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Disconnected from $Server." -ForegroundColor Yellow
}
