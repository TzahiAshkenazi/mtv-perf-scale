<#
.SYNOPSIS
    Interactive VM verification script - replaces all Verification_Template-*.ps1 scripts.
.DESCRIPTION
    Connects to vCenter, finds VMs by prefix, and shows a full deployment report:
    total count, per-host distribution, per-datastore distribution, and power state.
    Auto-discovers VM prefixes from vCenter.
.PARAMETER Server
    vCenter server FQDN (default: $env:VCENTER_HOSTNAME).
.PARAMETER User
    vCenter username (default: administrator@vsphere.local).
.PARAMETER Help
    Show this help message.
.EXAMPLE
    ./Verify-VMs.ps1
.EXAMPLE
    ./Verify-VMs.ps1 -Help
#>

[CmdletBinding()]
param(
    [string]$Server = $env:VCENTER_HOSTNAME,
    [string]$User   = "administrator@vsphere.local",
    [Alias("h","?")]
    [switch]$Help
)

if (-not $Server) {
    Write-Host "ERROR: VCENTER_HOSTNAME environment variable not set." -ForegroundColor Red
    Write-Host "Current user: $env:USER" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Run with bws (recommended):" -ForegroundColor White
    Write-Host "  cd /home/$env:USER/git/mpqe-scale-scripts/MTV" -ForegroundColor White
    Write-Host "  ./run-with-secrets.sh pwsh ./Vmware_PowerShell/Verify-VMs.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "Or: bws run -- pwsh ./Verify-VMs.ps1 (from this directory)" -ForegroundColor White
    exit 1
}

if ($Help) {
    Write-Host ""
    Write-Host "  Verify-VMs.ps1 -- Interactive VM Verification" -ForegroundColor Cyan
    Write-Host "  ================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Replaces all Verification_Template-*.ps1 scripts." -ForegroundColor White
    Write-Host "  Connects to vCenter, finds VMs by prefix, and verifies" -ForegroundColor White
    Write-Host "  distribution across hosts and datastores." -ForegroundColor White
    Write-Host ""
    Write-Host "  USAGE:" -ForegroundColor Yellow
    Write-Host "    ./Verify-VMs.ps1                        Interactive wizard" -ForegroundColor White
    Write-Host "    ./Verify-VMs.ps1 -Server <vcenter>      Use different vCenter" -ForegroundColor White
    Write-Host "    ./Verify-VMs.ps1 -Help                  Show this help" -ForegroundColor White
    Write-Host ""
    Write-Host "  WHAT IT CHECKS:" -ForegroundColor Yellow
    Write-Host "    - Total VM count for the prefix" -ForegroundColor White
    Write-Host "    - VMs per ESXi host (equal distribution)" -ForegroundColor White
    Write-Host "    - VMs per datastore" -ForegroundColor White
    Write-Host "    - Power state of all VMs" -ForegroundColor White
    Write-Host "    - VM names listed one per line per host" -ForegroundColor White
    Write-Host ""
    exit 0
}

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
$ErrorActionPreference = "Stop"
$sep = "=" * 80

# Sort VM objects by trailing -<number> in Name (1,2,…,10 not 1,10,11,2).
function Sort-VMsByTrailingNumber {
    param([object[]]$VM)
    @($VM) | Sort-Object `
        @{ Expression = {
            $n = $_.Name
            if ($n -match '-(\d+)$') { [int64]$Matches[1] } else { [int64]::MaxValue }
        }; Ascending = $true },
        @{ Expression = 'Name'; Ascending = $true }
}

# ═══════════════════════════════════════════════════════════════════════════════
# CONNECT TO VCENTER
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host $sep -ForegroundColor Cyan
Write-Host "  VM VERIFICATION" -ForegroundColor Cyan
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
# STEP 1: PICK VM PREFIX
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host "`n  Discovering VMs..." -ForegroundColor Yellow
$allVMs = Get-VM | Where-Object {
    $_.Name -notmatch '^vCLS-' -and
    $_.Name -notmatch '^VMware vCenter' -and
    $_.Name -notmatch '(?i)backup' -and
    $_.Name -notmatch '(?i)template'
} | Sort-Object Name

$grouped = $allVMs | ForEach-Object {
    if ($_.Name -match '^(.+?-)\d+$') {
        [PSCustomObject]@{ VM = $_.Name; Prefix = $Matches[1]; IsNumbered = $true }
    } else {
        [PSCustomObject]@{ VM = $_.Name; Prefix = $_.Name; IsNumbered = $false }
    }
}
$prefixes = $grouped | Group-Object Prefix | Sort-Object Count -Descending | ForEach-Object {
    [PSCustomObject]@{
        Prefix = $_.Name
        Count  = $_.Count
    }
}

if ($prefixes.Count -eq 0) {
    Write-Host "  No VMs with numbered prefixes found." -ForegroundColor Yellow
    $manualPrefix = Read-Host "  Enter VM prefix to search for"
    $prefixes = @([PSCustomObject]@{ Prefix = $manualPrefix; Count = 0 })
    $selectedPrefix = $prefixes[0].Prefix
} else {
    Write-Host ""
    Write-Host "  Discovered VM Prefixes" -ForegroundColor Cyan
    Write-Host "  ----------------------" -ForegroundColor Cyan
    for ($i = 0; $i -lt $prefixes.Count; $i++) {
        $p = $prefixes[$i].Prefix
        $pVMs = $allVMs | Where-Object { $_.Name -like "${p}*" }
        $pOnHost = $pVMs | Where-Object { $_.VMHost }
        $pUnassigned = $pVMs.Count - $pOnHost.Count
        $pHostGroups = $pOnHost | Group-Object { $_.VMHost.Name }
        $nHosts = $pHostGroups.Count
        if ($nHosts -gt 0) {
            $hostCounts = $pHostGroups | ForEach-Object { $_.Count }
            $minH = ($hostCounts | Measure-Object -Minimum).Minimum
            $maxH = ($hostCounts | Measure-Object -Maximum).Maximum
            $spread = if ($minH -eq $maxH) { "$minH per ESXi host" } else { "$minH–$maxH per ESXi host (uneven)" }
            $orphan = if ($pUnassigned -gt 0) { ", $pUnassigned not on host" } else { "" }
            Write-Host "    $($i + 1). $p ($($prefixes[$i].Count) VMs, $nHosts ESXi$orphan — $spread)" -ForegroundColor White
        } elseif ($pUnassigned -gt 0) {
            Write-Host "    $($i + 1). $p ($($prefixes[$i].Count) VMs, none on an ESXi host)" -ForegroundColor Yellow
        } else {
            Write-Host "    $($i + 1). $p ($($prefixes[$i].Count) VMs)" -ForegroundColor White
        }
    }
    Write-Host "    M. Enter prefix manually" -ForegroundColor DarkGray
    Write-Host ""

    $selectedPrefix = ""
    while (-not $selectedPrefix) {
        $pickInput = Read-Host "  Select number (or M for manual)"
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

Write-Host "  -> Prefix: $selectedPrefix" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: FIND AND ANALYZE VMs
# ═══════════════════════════════════════════════════════════════════════════════

$matchedVMs = $allVMs | Where-Object { $_.Name -like "${selectedPrefix}*" }
$totalFound = $matchedVMs.Count

Write-Host ""
Write-Host $sep -ForegroundColor Cyan
Write-Host "  VERIFICATION REPORT: ${selectedPrefix}*" -ForegroundColor Cyan
Write-Host $sep -ForegroundColor Cyan

if ($totalFound -eq 0) {
    Write-Host "`n  No VMs found with prefix '$selectedPrefix'." -ForegroundColor Red
    exit 0
}

Write-Host "`n  Total VMs found: $totalFound" -ForegroundColor White

# ── ESXi host counts (compact table before details) ─────────────────────────

$hostGroups = $matchedVMs | Group-Object -Property {
    if ($_.VMHost) { $_.VMHost.Name } else { "(not on host)" }
} | Sort-Object Name
if ($hostGroups.Count -eq 0) {
    Write-Host ""
    Write-Host "  ESXi distribution: no VMs to group." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "  ESXi distribution (count per host):" -ForegroundColor Cyan
    Write-Host "  $("-" * 60)" -ForegroundColor DarkGray
    $maxLen = 0
    foreach ($g in $hostGroups) {
        $L = ([string]$g.Name).Length
        if ($L -gt $maxLen) { $maxLen = $L }
    }
    $colW = [math]::Max(8, [math]::Min($maxLen, 48))
    foreach ($hg in $hostGroups) {
        $hName = [string]$hg.Name
        $short = if ($hName -eq "(not on host)") { $hName } else { $hName.Split('.')[0] }
        $lineColor = if ($hName -eq "(not on host)") { "Yellow" } else { "White" }
        Write-Host ("    {0,-$colW}  {1,4} VMs  ({2})" -f $hName, $hg.Count, $short) -ForegroundColor $lineColor
    }
}

# ── Power State ─────────────────────────────────────────────────────────────

$powerGroups = $matchedVMs | Group-Object PowerState
Write-Host ""
Write-Host "  Power State:" -ForegroundColor Cyan
foreach ($pg in $powerGroups) {
    $color = if ($pg.Name -eq "PoweredOn") { "Green" } elseif ($pg.Name -eq "PoweredOff") { "Yellow" } else { "Red" }
    Write-Host "    $($pg.Name): $($pg.Count)" -ForegroundColor $color
}

# ── Per Host Distribution ───────────────────────────────────────────────────

Write-Host ""
Write-Host "  Distribution per ESXi Host (detail):" -ForegroundColor Cyan
Write-Host "  $("-" * 60)" -ForegroundColor DarkGray

$esxiHostGroups = $hostGroups | Where-Object { [string]$_.Name -ne "(not on host)" }
$vmOnEsxi = ($matchedVMs | Where-Object { $_.VMHost }).Count
$expectedPerHost = if ($esxiHostGroups.Count -gt 0) { [math]::Floor($vmOnEsxi / $esxiHostGroups.Count) } else { 0 }
$orphanGroupInfo = $hostGroups | Where-Object { [string]$_.Name -eq "(not on host)" } | Select-Object -First 1
$orphanVmCount = if ($orphanGroupInfo) { $orphanGroupInfo.Count } else { 0 }
$allEqual = $true
if ($orphanVmCount -gt 0) { $allEqual = $false }

$hostIdx = 1
foreach ($hg in $hostGroups) {
    $hLabel = [string]$hg.Name
    $vmCount = $hg.Count
    if ($hLabel -eq "(not on host)") {
        $hostShort = $hLabel
        $status = if ($vmCount -gt 0) { "[--]" } else { "[OK]" }
        $color = if ($vmCount -gt 0) { "Yellow" } else { "Green" }
    } else {
        $hostShort = $hLabel.Split('.')[0]
        $isOK = ($vmCount -ge $expectedPerHost -and $vmCount -le ($expectedPerHost + 1))
        $status = if ($isOK) { "[OK]" } else { "[!!]" }
        $color = if ($isOK) { "Green" } else { "Red" }
        if (-not $isOK) { $allEqual = $false }
    }

    $vmNames = Sort-VMsByTrailingNumber -VM @($hg.Group) | ForEach-Object { $_.Name }

    Write-Host ""
    Write-Host "    Host $hostIdx ($hostShort): $vmCount VMs $status" -ForegroundColor $color
    foreach ($vmName in $vmNames) {
        Write-Host "      $vmName" -ForegroundColor White
    }
    $hostIdx++
}

Write-Host ""
if ($allEqual -and $esxiHostGroups.Count -gt 0) {
    Write-Host "  [OK] ESXi distribution looks correct (~$expectedPerHost VMs per ESXi host, $vmOnEsxi VMs on $($esxiHostGroups.Count) hosts)" -ForegroundColor Green
} elseif ($esxiHostGroups.Count -eq 0) {
    Write-Host "  [!!] No VMs are placed on an ESXi host." -ForegroundColor Yellow
} else {
    Write-Host "  [!!] ESXi distribution is UNEVEN (expected ~$expectedPerHost per host for $vmOnEsxi VMs on $($esxiHostGroups.Count) hosts)" -ForegroundColor Red
}

# ── Per Datastore Distribution ──────────────────────────────────────────────

Write-Host ""
Write-Host "  Distribution per Datastore:" -ForegroundColor Cyan
Write-Host "  $("-" * 60)" -ForegroundColor DarkGray

$dsGroups = $matchedVMs | ForEach-Object {
    $vm = $_
    $vmView = $vm | Get-View -Property Config.DatastoreUrl
    $dsName = $vmView.Config.DatastoreUrl[0].Name
    [PSCustomObject]@{
        VMName    = $vm.Name
        PrimaryDS = $dsName
    }
} | Group-Object PrimaryDS | Sort-Object Count -Descending

foreach ($dg in $dsGroups) {
    $pct = [math]::Round(($dg.Count / $totalFound) * 100, 0)
    Write-Host "    $($dg.Name): $($dg.Count) VMs ($pct%)" -ForegroundColor White
}

# ── Overall Summary ─────────────────────────────────────────────────────────

Write-Host ""
Write-Host $sep -ForegroundColor Cyan
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host $sep -ForegroundColor Cyan
Write-Host "  Prefix          : $selectedPrefix" -ForegroundColor White
Write-Host "  Total VMs       : $totalFound" -ForegroundColor White
$hostLine = "$($esxiHostGroups.Count) ESXi host(s)"
if ($orphanVmCount -gt 0) { $hostLine += ", $orphanVmCount VM(s) not on a host" }
Write-Host "  Hosts           : $hostLine" -ForegroundColor White
Write-Host "  ESXi VM counts  :" -ForegroundColor White
foreach ($hg in $hostGroups) {
    $hn = [string]$hg.Name
    $hs = if ($hn -eq "(not on host)") { $hn } else { $hn.Split('.')[0] }
    Write-Host "    - $hs : $($hg.Count) VMs" -ForegroundColor White
}
Write-Host "  Datastores      : $($dsGroups.Count)" -ForegroundColor White
foreach ($dg in $dsGroups) {
    Write-Host "    - $($dg.Name): $($dg.Count) VMs" -ForegroundColor White
}

$poweredOn = ($powerGroups | Where-Object { $_.Name -eq "PoweredOn" }).Count
if (-not $poweredOn) { $poweredOn = 0 }
Write-Host "  Powered On      : $poweredOn / $totalFound" -ForegroundColor White

if ($allEqual) {
    Write-Host "  Host Distribution: [OK] Even" -ForegroundColor Green
} else {
    Write-Host "  Host Distribution: [!!] Uneven" -ForegroundColor Red
}
Write-Host $sep -ForegroundColor Cyan
Write-Host ""

} finally {
    Disconnect-VIServer -Server $Server -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Disconnected from $Server." -ForegroundColor Yellow
}
