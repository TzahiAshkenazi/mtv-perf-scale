# Deploy-VMs.ps1 -- Interactive VM Deployment Wizard

Unified interactive script that replaces all `Popultion_Template-*.ps1` scripts.
Connects to vCenter, auto-discovers templates, ESXi hosts, and datastores,
then deploys VMs in equal sequential blocks across selected hosts.

## Quick Start

```bash
pwsh ./Deploy-VMs.ps1          # full interactive wizard
pwsh ./Deploy-VMs.ps1 -DryRun  # preview plan without deploying
```

## How It Works

The script connects to vCenter and walks you through 4 steps:

### Step 1: Pick a Template

```
  Available Templates:
    1. Template-A-new (Datastore: InfraTemplates_Global, GuestOS: Red Hat...)
    2. Template-B-new (Datastore: InfraTemplates_Global, GuestOS: Red Hat...)
    3. Template-D-new (Datastore: InfraTemplates_Global, GuestOS: Windows...)
  Select number: 1
```

Templates are auto-discovered from vCenter. Shows which datastore and guest OS each template uses.

### Step 2: VM Name and Count

```
  VM name prefix: rhel79-50gb-70usage-vm-
  How many VMs to create? 80
  Starting index (default: 1): 1
  -> VMs: rhel79-50gb-70usage-vm-1 through rhel79-50gb-70usage-vm-80
```

### Step 3: Pick ESXi Hosts

```
  ESXi Hosts:
    1. f01-h03-000-r640... (State: Connected, Cluster: Cluster1, Mem: 128/256 GB)
    2. f01-h09-000-r640... (State: Connected, Cluster: Cluster1, Mem: 95/256 GB)
    ...
  Select numbers (comma-separated, or 'all'): all
```

Type `all` for all hosts, or `1,3,5` to pick specific ones.

### Step 4: Pick Datastores

```
  Select PRIMARY datastore:
    1. PerfTest_VC7_1_FC_10TB (VMFS, 4200 GB free, 10240 GB total)
    2. PerfTest_VC7_1_ISCSI_24TB (VMFS, 18000 GB free, 24576 GB total)
  Select number: 2

  Split VMs across FC + iSCSI datastores? (y/n): y
  Select FC datastore: 1
  How many VMs on FC? 50
  -> Split: 50 on FC + 30 on iSCSI
```

The `InfraTemplates_Global` datastore (where templates live) is automatically excluded from the list.

**Single datastore:** Answer `n` to the split question -- all VMs go to the primary datastore.
**Split datastores:** Answer `y`, pick the FC datastore, and specify how many VMs go on FC.

## VM Distribution

VMs are distributed in **equal sequential blocks** across hosts:

```
80 VMs across 8 hosts (10 per host):

  Host 1: vm-1  .. vm-10
  Host 2: vm-11 .. vm-20
  Host 3: vm-21 .. vm-30
  Host 4: vm-31 .. vm-40
  Host 5: vm-41 .. vm-50
  Host 6: vm-51 .. vm-60
  Host 7: vm-61 .. vm-70
  Host 8: vm-71 .. vm-80
```

If the count doesn't divide evenly (e.g. 136 VMs / 8 hosts = 17 each), the remainder is distributed one extra VM per host starting from the first host.

## Split Datastore Mode

When splitting across FC + iSCSI, VMs are assigned **by VM number** (not by host):

```
80 VMs, 50 on FC + 30 on iSCSI:

  Host 1: vm-1..10   -> all FC
  Host 2: vm-11..20  -> all FC
  Host 3: vm-21..30  -> all FC
  Host 4: vm-31..40  -> all FC
  Host 5: vm-41..50  -> all FC
  Host 6: vm-51..60  -> all iSCSI
  Host 7: vm-61..70  -> all iSCSI
  Host 8: vm-71..80  -> all iSCSI
```

## Deployment Plan Preview

Before creating any VMs, the script shows a full plan:

```
  ================================================================================
    DEPLOYMENT PLAN
  ================================================================================

    vCenter       : vcenter.example.com
    Template      : Template-A-new
    VM Prefix     : rhel79-50gb-70usage-vm-
    Total VMs     : 80 (index 1 to 80)
    Hosts         : 8
    DS FC         : PerfTest_VC7_1_FC_10TB (50 VMs)
    DS iSCSI      : PerfTest_VC7_1_ISCSI_24TB (30 VMs)

  HostIndex HostName                                VMCount VMRange              Datastores
  --------- --------                                ------- -------              ----------
  1         esxi-host-01.example.com...             10      vm-1 .. vm-10        FC
  2         esxi-host-02.example.com...             10      vm-11 .. vm-20       FC
  ...

  Deploy 80 VMs now? (y/n):
```

## Validation

Before deploying, the script verifies:
- Template exists in vCenter
- All selected datastores exist (shows free space)
- All selected ESXi hosts exist and are connected

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Server` | `$env:VCENTER_HOSTNAME` | vCenter FQDN |
| `-User` | `administrator@vsphere.local` | vCenter username |
| `-DryRun` | off | Show plan without deploying |

All other values (template, prefix, VMs, hosts, datastores) are selected interactively.

## Replaces These Legacy Scripts

| Old Script | Equivalent |
|------------|------------|
| `Popultion_Template-A.ps1` | Template-A, 80 VMs, 8 hosts, split 50 FC + 30 iSCSI |
| `Popultion_Template-A-IBM.ps1` | Template-A, 80 VMs, 8 hosts, single iSCSI (IBM) |
| `Popultion_Template-B.ps1` | Template-B, 136 VMs, 8 hosts, single iSCSI |
| `Popultion_Template-C.ps1` | Template-C, 1 VM, 1 host, single FC |
| `Popultion_Template-D.ps1` | Template-D, 5 VMs, 1 host, single FC |
| `Popultion_Template-E.ps1` | Template-E, 1 VM, 1 host, single iSCSI |
| `Popultion_Template-F.ps1` | Template-F, 1 VM, 1 host, single iSCSI |
| `Popultion_Template-G.ps1` | Template-B, 50 VMs, 1 host, single iSCSI |
