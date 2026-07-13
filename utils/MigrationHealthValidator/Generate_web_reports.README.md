# Generate Web Reports

Generates HTML reports for ALL MTV versions and pushes them directly to a remote web server.

## Quick Start

```bash
# Generate all reports and push to remote
./Generate_web_reports.sh

# Backup current index.html before changes
./Generate_web_reports.sh -b "pre-upgrade backup"

# Show help
./Generate_web_reports.sh -h
```

## Features

- **Batch processing** - Generates reports for all version folders in results directory
- **Remote sync** - Automatically pushes reports to web server via rsync/scp
- **Golden backup management** - Maintains a full-featured index template
- **Auto version cards** - Detects missing versions and adds cards to main index
- **Backup support** - Create timestamped backups of index.html on remote server

## Usage

### Generate Reports (Default)

```bash
./Generate_web_reports.sh
```

This will:
1. Process all version folders in `/home/$USER/MTV/results/`
2. Generate web reports using `MigrationHealthValidator.sh generate-web`
3. Fetch golden backup from remote server
4. Update `index.html` with current versions
5. Add missing version cards automatically
6. Sync everything to remote web server
7. Prompt to update golden backup

### Backup Mode

```bash
# Simple backup
./Generate_web_reports.sh -b

# Backup with description
./Generate_web_reports.sh -b "before-2.13-release"
```

Creates timestamped backup on remote server:
- `backups/index.backup.<timestamp>_<description>.html`
- `backups/index.html.full-featured-backup` (golden copy)

## Configuration

Edit variables at top of script:

| Variable | Default | Description |
|----------|---------|-------------|
| `SCRIPT_DIR` | `/home/$USER/git/mpqe-scale-scripts/MTV/utils/MigrationHealthValidator` | Script location |
| `RESULTS_DIR` | `/home/$USER/MTV/results` | Source results folder |
| `TEMP_DIR` | `/tmp/MTV-Dashboard` | Temporary working directory |
| `REMOTE_WEB_SERVER` | `$REMOTE_WEB_SERVER` (from bws) | Remote web server hostname |
| `REMOTE_WEB_USER` | `root` | SSH user for remote server |
| `REMOTE_WEB_PATH` | `/MTV-Dashboard` | Path on remote server |
| `REMOTE_WEB_ENABLED` | `true` | Enable/disable remote sync |

## Requirements

- `bash`
- `ssh` / `scp` / `rsync` - for remote server operations
- `perl` - for updating JavaScript arrays in index.html
- `MigrationHealthValidator.sh` - in same directory

### Remote Server Setup

The remote server must have:
- SSH key authentication configured
- Web server serving `REMOTE_WEB_PATH`
- Golden backup at `<REMOTE_WEB_PATH>/backups/index.html.full-featured-backup`

## Workflow

```
┌─────────────────────────────────────────────────────────────┐
│  1. Process each version folder                             │
│     └── MigrationHealthValidator.sh generate-web <version>  │
├─────────────────────────────────────────────────────────────┤
│  2. Fetch golden backup from remote                         │
├─────────────────────────────────────────────────────────────┤
│  3. Update index.html                                       │
│     ├── Update JavaScript versions array                    │
│     └── Add missing version cards to HTML                   │
├─────────────────────────────────────────────────────────────┤
│  4. Sync index.html to remote server                        │
├─────────────────────────────────────────────────────────────┤
│  5. Cleanup temp folder                                     │
├─────────────────────────────────────────────────────────────┤
│  6. Prompt to update golden backup                          │
└─────────────────────────────────────────────────────────────┘
```

## Output

View reports at: `http://$REMOTE_WEB_SERVER/`
