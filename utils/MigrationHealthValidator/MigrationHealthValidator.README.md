# Migration Health Validator

A tool for generating health reports for MTV (Migration Toolkit for Virtualization) migrations.

## Quick Start

```bash
# From saved logs (interactive cycle selection with PASS/FAIL status)
./MigrationHealthValidator.sh --from-logs=/home/$USER/MTV/results/2.10.0/my-plan/logs

# From mtv-debug folder
./MigrationHealthValidator.sh --from-logs=mtv-debug-my-plan-20260213-090623

# From live cluster
./MigrationHealthValidator.sh my-plan-name
```

## Features

- **Interactive cycle selection** - Shows all cycles with PASS/FAIL status and duration
- **Auto-detection** - Automatically detects plan name, migration type (Warm/Cold), and folder format
- **Detailed analysis** - VM timing, warm migration precopies, transfer rates, error extraction
- **Log analysis** - Scans controller and VirtV2V logs for errors
- **Multiple input formats** - Supports automation logs and mtv-debug folders

## Usage

### Offline Mode (Recommended)

```bash
# With interactive cycle selection (shows PASS/FAIL status for each cycle)
./MigrationHealthValidator.sh --from-logs=/home/$USER/MTV/results/2-11-0-33/10vm-cold-tc6-1/logs

# Select specific cycle
./MigrationHealthValidator.sh --from-logs=2-11-0-33/10vm-cold-tc6-1/logs --cycle=20260130-100747

# From mtv-debug folder (full path or folder name)
./MigrationHealthValidator.sh --from-logs=/home/$USER/Tzahi_MTV/mtv-debug-1vm-warm-tc2-5-20260213-090623
./MigrationHealthValidator.sh --from-logs=mtv-debug-1vm-warm-tc2-5-20260213-090623
```

**Interactive cycle selection example:**
```
Available cycles (oldest to newest):
--------------------------------------------------------------------------------------------------------
  [1] my-plan_20260218-121936  (2026-02-18 12:19:36)  [PASS]  Duration: 12:06:05  
  [2] my-plan_20260219-102045  (2026-02-19 10:20:45)  [FAIL]  Duration: 00:01:31  
  [3] my-plan_20260219-120016  (2026-02-19 12:00:16)  [FAIL]  Duration: 00:01:21  
  [4] my-plan_20260220-092411  (2026-02-20 09:24:11)  [N/A]   (no migration data)  [LATEST]
--------------------------------------------------------------------------------------------------------

Enter cycle number [1-4] or press Enter for latest [4]: 
```

### Online Mode (Live Cluster)

```bash
# Generate report from live cluster
./MigrationHealthValidator.sh my-plan-name

# Monitor running migration
./MigrationHealthValidator.sh monitor my-plan-name --timeout=7200
```

### Web Report Generation

```bash
# Generate HTML reports for all cycles in a version folder
./MigrationHealthValidator.sh generate-web 2-11-0-33

# With custom output path
./MigrationHealthValidator.sh generate-web 2-11-0-33 --output=/custom/path

# Include importer logs (online mode)
./MigrationHealthValidator.sh generate-web 2.10.4 --online
```

## Options

| Option | Description |
|--------|-------------|
| `--from-logs=PATH` | Path to logs folder or mtv-debug folder |
| `--cycle=NAME` | Select specific cycle (full name or timestamp) |
| `--list-cycles` | List all available cycles |
| `--timeout=SECONDS` | Monitor timeout (default: 3600) |
| `--output=PATH` | Web report output path |
| `--online` | Try online mode first for generate-web |

## Supported Folder Formats

**Automation logs** (`/home/$USER/MTV/results/`):
```
<version>/<plan-name>/logs/<plan-name>_<timestamp>/
├── Migration_<plan-name>.json   # Required
├── Plan_<plan-name>.json        # Optional
├── MTV_forklift-controller-*.log
└── VirtV2V_*.log
```

**mtv-debug folders** (`/home/$USER/Tzahi_MTV/`):
```
mtv-debug-<plan-name>-<timestamp>/
├── Migration_<plan-name>.json   # or *-migrations.yaml
├── Importer_*.log
└── ...
```

## Report Sections

- **Migration Status** - Success/Failed, duration, timestamps
- **VM Consistency** - Success rate, failed VM details with error messages
- **VM Timing** - Average, min, max durations, outlier detection
- **Warm Migration** - Precopy snapshots, cutover timing, transfer rates
- **Log Analysis** - Controller and VirtV2V errors during migration timeframe

## Requirements

- `bash`
- `jq` (JSON processor)
- `oc` (OpenShift CLI) - for online mode only
- `yq` (YAML processor) - for mtv-debug YAML files only
