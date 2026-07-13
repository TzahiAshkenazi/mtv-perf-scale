#!/bin/bash
# Generate web reports and push directly to remote server
#
# Usage:
#   ./generate_web_reports.sh                    Generate ALL reports and push to remote
#   ./generate_web_reports.sh <version-folder>   Generate report for a specific folder only
#   ./generate_web_reports.sh -b [desc]          Backup index.html on remote server

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="/home/$USER/MTV/results"
TEMP_DIR="/tmp/MTV-Dashboard"
TEMP_RESULTS_DIR="$TEMP_DIR/results-data"

# Verify required environment variables are present (injected by bws run or source .env)
if [[ -z "${REMOTE_WEB_SERVER}" || -z "${REMOTE_WEB_USER}" || -z "${REMOTE_WEB_PATH}" ]]; then
    echo "ERROR: Required environment variables not set: REMOTE_WEB_SERVER, REMOTE_WEB_USER, REMOTE_WEB_PATH"
    echo "Current user: $USER"
    echo ""
    echo "Run with bws (recommended):"
    echo "  cd /home/$USER/git/mpqe-scale-scripts/MTV"
    echo "  ./run-with-secrets.sh ./utils/MigrationHealthValidator/Generate_web_reports.sh"
    echo ""
    echo "Or: bws run -- ./Generate_web_reports.sh (from this directory)"
    exit 1
fi

# Remote Web Server Configuration (sourced from environment / bws)
REMOTE_WEB_SERVER="${REMOTE_WEB_SERVER}"
REMOTE_WEB_USER="${REMOTE_WEB_USER}"
REMOTE_WEB_PATH="${REMOTE_WEB_PATH}"
REMOTE_WEB_ENABLED=true

# Function to run command on remote server
remote_cmd() {
    ssh "${REMOTE_WEB_USER}@${REMOTE_WEB_SERVER}" "$@"
}

# Function to sync to remote server
sync_to_remote() {
    local source_path="$1"
    local remote_path="$2"
    
    if [[ "$REMOTE_WEB_ENABLED" != "true" ]]; then
        echo "Remote sync disabled"
        return 0
    fi
    
    rsync -avz "$source_path" "${REMOTE_WEB_USER}@${REMOTE_WEB_SERVER}:${remote_path}"
    return $?
}

# Handle flags
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Generate Web Reports Script"
    echo ""
    echo "Usage:"
    echo "  ./generate_web_reports.sh                              Generate ALL reports and push to remote"
    echo "  ./generate_web_reports.sh <version-folder>             Generate report for specific folder + update index"
    echo "  ./generate_web_reports.sh <version-folder> --force     Regenerate ALL reports (skip nothing)"
    echo "  ./generate_web_reports.sh --force                      Regenerate ALL versions, ALL reports"
    echo "  ./generate_web_reports.sh -b [desc]                    Backup index.html on remote server"
    echo "  ./generate_web_reports.sh -h                           Show this help"
    echo ""
    echo "Examples:"
    echo "  ./generate_web_reports.sh ~/MTV/results/2-12-0-43/"
    echo "  ./generate_web_reports.sh 2-12-0-43"
    echo "  ./generate_web_reports.sh 2-12-0-43 --force"
    echo ""
    echo "Remote server: ${REMOTE_WEB_USER}@${REMOTE_WEB_SERVER}:${REMOTE_WEB_PATH}"
    echo ""
    echo "This script:"
    echo "  1. Generates reports to temp folder (/tmp/MTV-Dashboard/)"
    echo "  2. Updates main index.html with version cards"
    echo "  3. Syncs to remote web server"
    echo "  4. Cleans up temp folder"
    exit 0
fi

if [[ "$1" == "-b" || "$1" == "--backup" ]]; then
    echo "=== Backup Mode (Remote Server) ==="
    
    # Get optional description from second argument
    BACKUP_DESC=""
    if [[ -n "$2" ]]; then
        BACKUP_DESC="_$(echo "$2" | tr ' ' '_' | tr -cd '[:alnum:]_-')"
    fi
    
    BACKUP_DATE=$(date +%d-%m-%Y_%H-%M-%S)
    BACKUP_FILE="index.backup.${BACKUP_DATE}${BACKUP_DESC}.html"
    
    # Create backup on remote server
    echo "Creating backup on remote server..."
    remote_cmd "
        cd ${REMOTE_WEB_PATH} && \
        if [[ -f index.html ]]; then
            cp index.html backups/${BACKUP_FILE} && \
            cp index.html backups/index.html.full-featured-backup && \
            echo 'Created: backups/${BACKUP_FILE}' && \
            echo 'Updated: backups/index.html.full-featured-backup'
        else
            echo 'ERROR: No index.html found on remote server'
            exit 1
        fi
    "
    
    if [[ $? -eq 0 ]]; then
        echo ""
        echo "Done! Backup complete on remote server."
    else
        echo ""
        echo "ERROR: Backup failed"
        exit 1
    fi
    exit 0
fi

cd "$SCRIPT_DIR"

# Parse arguments
SINGLE_FOLDER=""
FORCE_FLAG=""
for arg in "$@"; do
    if [[ "$arg" == "--force" ]]; then
        FORCE_FLAG="--force"
    elif [[ "$arg" != -* && -z "$SINGLE_FOLDER" ]]; then
        if [[ -d "$arg" ]]; then
            SINGLE_FOLDER="$arg"
        elif [[ -d "$RESULTS_DIR/$arg" ]]; then
            SINGLE_FOLDER="$RESULTS_DIR/$arg"
        else
            echo "ERROR: Folder not found: $arg"
            echo "Tried: $arg and $RESULTS_DIR/$arg"
            exit 1
        fi
    fi
done

if [[ -n "$FORCE_FLAG" ]]; then
    echo "[FORCE MODE] Will regenerate all reports, skipping nothing"
    echo ""
fi

# Record start time
START_TIME=$(date +%s)
START_TIME_DISPLAY=$(date '+%Y-%m-%d %H:%M:%S')

if [[ -n "$SINGLE_FOLDER" ]]; then
    SINGLE_VNAME=$(basename "$SINGLE_FOLDER")
    echo "============================================"
    echo " Generating Web Report for: $SINGLE_VNAME"
    echo "============================================"
    echo "Start time: $START_TIME_DISPLAY"
    echo "Source: $SINGLE_FOLDER"
    echo "Temp: $TEMP_DIR"
    echo "Remote: ${REMOTE_WEB_USER}@${REMOTE_WEB_SERVER}:${REMOTE_WEB_PATH}"
    echo ""

    mkdir -p "$TEMP_RESULTS_DIR"

    echo "=== Processing: $SINGLE_VNAME ==="
    ./MigrationHealthValidator.sh generate-web "$SINGLE_FOLDER" $FORCE_FLAG
    echo ""
else
    echo "============================================"
    echo " Generating Web Reports for ALL versions"
    echo "============================================"
    echo "Start time: $START_TIME_DISPLAY"
    echo "Source: $RESULTS_DIR"
    echo "Temp: $TEMP_DIR"
    echo "Remote: ${REMOTE_WEB_USER}@${REMOTE_WEB_SERVER}:${REMOTE_WEB_PATH}"
    echo ""

    mkdir -p "$TEMP_RESULTS_DIR"

    for v in "$RESULTS_DIR"/*/; do
        vname=$(basename "$v")
        [[ "$vname" == "old" || "$vname" == "old2" ]] && continue
        
        echo "=== Processing: $vname ==="
        ./MigrationHealthValidator.sh generate-web "$v" $FORCE_FLAG
        echo ""
    done
fi

# Get golden backup from remote and update main index
echo "=== Generating Main Index ==="

# Fetch golden backup from remote
echo "Fetching golden backup from remote server..."
mkdir -p "$TEMP_DIR/backups"
scp "${REMOTE_WEB_USER}@${REMOTE_WEB_SERVER}:${REMOTE_WEB_PATH}/backups/index.html.full-featured-backup" "$TEMP_DIR/backups/" 2>/dev/null

if [[ -f "$TEMP_DIR/backups/index.html.full-featured-backup" ]]; then
    # Copy the full-featured backup
    cp "$TEMP_DIR/backups/index.html.full-featured-backup" "$TEMP_DIR/index.html"
    
    # Add no-cache meta tags if not already present
    if ! grep -q "Cache-Control" "$TEMP_DIR/index.html"; then
        sed -i 's|<meta charset="UTF-8">|<meta charset="UTF-8">\n    <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">\n    <meta http-equiv="Pragma" content="no-cache">\n    <meta http-equiv="Expires" content="0">|' "$TEMP_DIR/index.html"
    fi
    
    echo "Copied full-featured index template"
    
    # Build versions array from remote server folders
    echo "Getting version list from remote server..."
    versions=$(remote_cmd "ls -d ${REMOTE_WEB_PATH}/results-data/*/ 2>/dev/null | xargs -n1 basename | sort -V" | tr '\n' ',' | sed "s/,/', '/g" | sed "s/^/'/" | sed "s/, '$//" )
    
    # Update the versions array in JavaScript
    perl -i -0pe "s/const versions = \[.*?\];/const versions = [$versions];/s" "$TEMP_DIR/index.html"
    
    echo "Updated versions array"
    
    # Add missing version cards to HTML
    echo ""
    echo "=== Checking for missing version cards ==="
    added_count=0
    
    for vname in $(remote_cmd "ls ${REMOTE_WEB_PATH}/results-data/ 2>/dev/null" | sort -rV); do
        [[ "$vname" == "old" ]] && continue
        
        # Check if this version already has a card in the HTML
        if ! grep -q "href=\"results-data/${vname}/index.html" "$TEMP_DIR/index.html"; then
            echo "  Adding missing card: $vname"
            added_count=$((added_count + 1))
            
            # Convert folder name to display name (2-12-0-05 -> 2.12.0-05)
            display_name=$(echo "$vname" | sed 's/^\([0-9]\+\)-\([0-9]\+\)-/\1.\2./' | sed 's/-\([0-9]\+\)$/-\1/')
            
            # Extract major.minor for section
            if [[ "$vname" =~ ^2[.-]([0-9]+) ]]; then
                minor="${BASH_REMATCH[1]}"
            fi
            
            # Find the section and add card after version-grid div using awk
            # Pattern: look for "MTV 2.XX " (with space) in section title, then add after version-grid
            awk -v vname="$vname" -v dname="$display_name" -v pattern="MTV 2.$minor " '
            index($0, pattern) > 0 { found_section=1 }
            found_section && /version-grid/ {
                print
                print "            <a href=\"results-data/" vname "/index.html?t=" systime() "\" class=\"version-card\">"
                print "                <span class=\"arrow\">→</span>"
                print "                <h3>MTV " dname "</h3>"
                print "            </a>"
                found_section=0
                next
            }
            { print }
            ' "$TEMP_DIR/index.html" > "$TEMP_DIR/index.html.tmp" && mv "$TEMP_DIR/index.html.tmp" "$TEMP_DIR/index.html"
            
            # Verify it was added
            if grep -q "href=\"results-data/${vname}/index.html" "$TEMP_DIR/index.html"; then
                echo "    [OK] Card added"
            else
                echo "    [WARN] Failed to add card, section MTV 2.${minor} may not exist"
            fi
        fi
    done
    
    if [[ $added_count -eq 0 ]]; then
        echo "  All version cards present"
    else
        echo "  Added $added_count new version card(s)"
    fi
    
    # Sync index.html to remote
    echo ""
    echo "Syncing index.html to remote..."
    scp "$TEMP_DIR/index.html" "${REMOTE_WEB_USER}@${REMOTE_WEB_SERVER}:${REMOTE_WEB_PATH}/"
    
else
    echo "WARNING: No golden backup found on remote server"
    echo "Please create one first by copying a working index.html to:"
    echo "  ${REMOTE_WEB_PATH}/backups/index.html.full-featured-backup"
    exit 1
fi

# Clean up temp folder
echo ""
echo "============================================"
echo " Cleaning up temp folder"
echo "============================================"
rm -rf "$TEMP_DIR"
echo "Removed: $TEMP_DIR"

# Record end time and calculate duration
END_TIME=$(date +%s)
END_TIME_DISPLAY=$(date '+%Y-%m-%d %H:%M:%S')
DURATION=$((END_TIME - START_TIME))
DURATION_MIN=$((DURATION / 60))
DURATION_SEC=$((DURATION % 60))

echo ""
echo "============================================"
echo " DONE"
echo "============================================"
echo ""
echo "Start time:  $START_TIME_DISPLAY"
echo "End time:    $END_TIME_DISPLAY"
echo "Total time:  ${DURATION_MIN}m ${DURATION_SEC}s"
echo ""
echo "View at: http://${REMOTE_WEB_SERVER}/"

# Prompt to update the golden backup on remote
echo ""
echo -n "Update golden backup on remote server? (y/n): "
read update_backup
if [[ "$update_backup" == "y" || "$update_backup" == "Y" ]]; then
    echo "Updating golden backup..."
    if remote_cmd "cp ${REMOTE_WEB_PATH}/index.html ${REMOTE_WEB_PATH}/backups/index.html.full-featured-backup"; then
        echo "Golden backup updated on remote server"
    else
        echo "ERROR: Failed to update golden backup"
    fi
else
    echo "Golden backup NOT updated"
fi
