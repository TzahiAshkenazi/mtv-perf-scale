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
    
    # Add Pipeline Comparison Feature if not present
    echo ""
    echo "=== Adding Pipeline Comparison Feature ==="
    
    # 1. Add checkbox header to compare table
    if ! grep -q 'select-all-versions' "$TEMP_DIR/index.html"; then
        echo "  Adding checkbox header..."
        sed -i 's|<th>MTV Version</th>|<th style="width:30px;"><input type="checkbox" id="select-all-versions" onclick="toggleAllVersions()" title="Select All"></th><th>MTV Version</th>|' "$TEMP_DIR/index.html"
    fi
    
    # 2. Add checkbox to row template in JavaScript (check specifically for row checkbox, not popup checkboxes)
    if ! grep -q 'class="version-checkbox" data-version' "$TEMP_DIR/index.html"; then
        echo "  Adding checkbox to row template..."
        sed -i 's|<td><strong>\${d.version.replace(/-/g|<td><input type="checkbox" class="version-checkbox" data-version="\${d.version}" data-tcname="\${currentTCName}"></td><td><strong>\${d.version.replace(/-/g|' "$TEMP_DIR/index.html"
    fi
    
    # 3. Add Compare Pipeline button before compare table
    if ! grep -q 'compare-pipeline-btn' "$TEMP_DIR/index.html"; then
        echo "  Adding Compare Pipeline button..."
        sed -i 's|<table class="compare-table" id="compare-table">|<div style="margin-bottom:15px;"><button onclick="comparePipelineBreakdown()" id="compare-pipeline-btn" style="background:#fd7e14; color:white; padding:12px 24px; font-size:16px; font-weight:bold; border-radius:20px; border:none; cursor:pointer;">📊 Compare Pipeline (0)</button></div><table class="compare-table" id="compare-table">|' "$TEMP_DIR/index.html"
    fi
    
    # 4. Add event delegation for checkbox count update
    if ! grep -q 'compare-tbody.*onchange' "$TEMP_DIR/index.html"; then
        echo "  Adding event delegation..."
        sed -i '/tbody.appendChild(row);/a\            document.getElementById("compare-tbody").onchange = function(e) { if(e.target.classList.contains("version-checkbox")) { var c = document.querySelectorAll(".version-checkbox:checked").length; var btn = document.getElementById("compare-pipeline-btn"); if(btn) { btn.textContent = "📊 Compare Pipeline (" + c + ")"; } } };' "$TEMP_DIR/index.html"
    fi
    
    # 5. Add Pipeline Comparison JavaScript functions
    if ! grep -q 'comparePipelineBreakdown' "$TEMP_DIR/index.html"; then
        echo "  Adding Pipeline Comparison JavaScript..."
        # Create temp JS file
        cat > "$TEMP_DIR/pipeline-compare.js" << 'PIPELINEJS'
// ===== Pipeline Comparison Feature =====

function toggleAllVersions() {
    var selectAll = document.getElementById("select-all-versions");
    var checkboxes = document.querySelectorAll(".version-checkbox");
    checkboxes.forEach(function(cb) { cb.checked = selectAll.checked; });
    var c = document.querySelectorAll(".version-checkbox:checked").length;
    var btn = document.getElementById("compare-pipeline-btn");
    if(btn) { btn.textContent = "📊 Compare Pipeline (" + c + ")"; }
}

async function comparePipelineBreakdown() {
    var checkboxes = document.querySelectorAll(".version-checkbox:checked");
    if (checkboxes.length < 2) {
        alert("Select at least 2 versions to compare");
        return;
    }
    
    var results = [];
    for (var i = 0; i < checkboxes.length; i++) {
        var cb = checkboxes[i];
        var version = cb.dataset.version;
        var tcname = cb.dataset.tcname;
        try {
            var resp = await fetch("results-data/" + version + "/" + tcname + "/index.html?t=" + Date.now());
            if (resp.ok) {
                var html = await resp.text();
                var breakdown = extractBreakdownFromHTML(html, version);
                results.push(breakdown);
            } else {
                results.push({version: version, error: "Failed to fetch"});
            }
        } catch (err) {
            results.push({version: version, error: err.message});
        }
    }
    
    showPipelineCompareModal(results);
}

function extractBreakdownFromHTML(html, version) {
    var parser = new DOMParser();
    var doc = parser.parseFromString(html, "text/html");
    
    var headers = doc.querySelectorAll("th.breakdown-header");
    var headerNames = [];
    headers.forEach(function(h) { headerNames.push(h.textContent.trim().replace(" (Avg)", "")); });
    
    var rows = doc.querySelectorAll("tbody tr"); if (rows.length === 0) rows = doc.querySelectorAll("table tr");
    var cycles = [];
    
    rows.forEach(function(row) {
        var cells = row.querySelectorAll("td");
        var breakdownCells = row.querySelectorAll("td.breakdown-col");
        var statusCell = cells[3] ? cells[3].textContent.trim().toLowerCase() : ""; var durationCell = cells[4] ? cells[4].textContent.trim() : ""; if (breakdownCells.length > 0 && statusCell !== "unknown" && durationCell !== "N/A") {
            var cycleData = {
                cycle: cells[0] ? cells[0].textContent.trim() : "",
                date: cells[1] ? cells[1].textContent.trim() : "",
                vms: breakdownCells[0] ? breakdownCells[0].textContent.trim() : "1"
            };
            for (var i = 1; i < breakdownCells.length && i < headerNames.length; i++) {
                var hdr = headerNames[i] || ("col" + i);
                cycleData[hdr] = breakdownCells[i] ? breakdownCells[i].textContent.trim().replace(/[↑↓▲▼]/g, "").trim() : "N/A";
            }
            cycles.push(cycleData);
        }
    });
    
    var stepAvgs = {};
    headerNames.forEach(function(h) {
        if (h && h !== "VMs") {
            var vals = cycles.map(function(c) { return parseTimeToSeconds(c[h] || "0:00"); }).filter(function(v) { return v > 0; });
            stepAvgs[h] = vals.length > 0 ? vals.reduce(function(a,b){return a+b;},0) / vals.length : 0;
        }
    });
    
    return {
        version: version.replace(/-/g, "."),
        cycles: cycles,
        stepAvgs: stepAvgs,
        headers: headerNames.filter(function(h) { return h && h !== "VMs"; })
    };
}

function parseTimeToSeconds(timeStr) {
    if (!timeStr || timeStr === "N/A") return 0;
    var parts = timeStr.split(":").map(Number);
    if (parts.length === 3) return parts[0]*3600 + parts[1]*60 + parts[2];
    if (parts.length === 2) return parts[0]*60 + parts[1];
    return parts[0] || 0;
}

function formatSecToTime(sec) {
    if (!sec || sec <= 0) return "N/A";
    var h = Math.floor(sec / 3600);
    var m = Math.floor((sec % 3600) / 60);
    var s = Math.floor(sec % 60);
    if (h > 0) return h + ":" + String(m).padStart(2,"0") + ":" + String(s).padStart(2,"0");
    return m + ":" + String(s).padStart(2,"0");
}

function showPipelineCompareModal(results) {
    var existing = document.getElementById("pipeline-compare-modal");
    if (existing) existing.remove();
    
    var allHeaders = new Set();
    results.forEach(function(r) { (r.headers || []).forEach(function(h) { allHeaders.add(h); }); });
    var headerList = Array.from(allHeaders);
    
    var tcName = document.querySelector(".version-checkbox:checked") ? document.querySelector(".version-checkbox:checked").dataset.tcname : "";
    
    var tableHTML = '<table style="width:100%; border-collapse:collapse; font-size:16px;">';
    tableHTML += '<thead><tr style="background:#1a5f7a;"><th style="padding:12px 20px; text-align:center; color:#fff; min-width:100px;">Version</th>';
    headerList.forEach(function(h) {
        tableHTML += '<th style="padding:12px 20px; text-align:center; color:#fff; min-width:90px;">' + h + '</th>';
    });
    tableHTML += '</tr></thead><tbody>';
    
    var prevVals = {};
    results.forEach(function(r, idx) {
        if (r.error) {
            tableHTML += '<tr style="border-bottom:1px solid #eee;"><td style="padding:12px 20px; color:#333; text-align:center;">' + r.version + '</td><td colspan="' + headerList.length + '" style="color:#e94560; padding:12px 20px;">' + r.error + '</td></tr>';
        } else {
            tableHTML += '<tr style="border-bottom:1px solid #eee;"><td style="padding:12px 20px; font-weight:bold; color:#333; text-align:center; min-width:100px;">' + r.version + '</td>';
            headerList.forEach(function(h) {
                var val = r.stepAvgs ? r.stepAvgs[h] : 0;
                var arrow = "";
                var arrowStyle = "";
                if (idx > 0 && prevVals[h] && val > 0) {
                    if (val < prevVals[h]) {
                        arrow = " ▼";
                        arrowStyle = "color:#4caf50; font-size:14px; font-weight:bold;";
                    } else if (val > prevVals[h]) {
                        arrow = " ▲";
                        arrowStyle = "color:#e94560; font-size:14px; font-weight:bold;";
                    }
                }
                tableHTML += '<td style="padding:12px 20px; text-align:center; color:#333; min-width:90px;">' + formatSecToTime(val) + '<span style="' + arrowStyle + '">' + arrow + '</span></td>';
                prevVals[h] = val;
            });
            tableHTML += '</tr>';
        }
    });
    tableHTML += '</tbody></table>';
    
    var modal = document.createElement("div");
    modal.id = "pipeline-compare-modal";
    modal.style.cssText = "position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.8); z-index:9999; display:flex; align-items:center; justify-content:center;";
    
    var content = document.createElement("div");
    content.style.cssText = "background:#ffffff; border-radius:12px; padding:30px; min-width:1000px; max-width:95%; max-height:95%; overflow:auto; box-shadow: 0 10px 40px rgba(0,0,0,0.3);";
    
    var header = document.createElement("div");
    header.style.cssText = "display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;";
    header.innerHTML = '<h3 style="margin:0; color:#333;">📊 ' + tcName + '</h3>';
    
    var closeBtn = document.createElement("button");
    closeBtn.innerHTML = "&times;";
    closeBtn.style.cssText = "background:none; border:none; color:#333; font-size:28px; cursor:pointer; font-weight:bold;";
    closeBtn.onclick = function() { modal.remove(); };
    header.appendChild(closeBtn);
    
    content.appendChild(header);
    
    var tableDiv = document.createElement("div");
    tableDiv.innerHTML = tableHTML;
    content.appendChild(tableDiv);
    
    var legend = document.createElement("p");
    legend.style.cssText = "color:#666; font-size:14px; margin-top:15px;";
    legend.innerHTML = '<span style="color:#4caf50; font-weight:bold;">▼ Faster</span> | <span style="color:#e94560; font-weight:bold;">▲ Slower</span> (compared to previous row). Values are averages across cycles.';
    content.appendChild(legend);
    
    modal.appendChild(content);
    modal.onclick = function(e) { if (e.target === modal) modal.remove(); };
    document.body.appendChild(modal);
}
// ===== End Pipeline Comparison =====
PIPELINEJS
        # Inject JS after the opening <script> tag
        sed -i '/<script>$/r '"$TEMP_DIR/pipeline-compare.js" "$TEMP_DIR/index.html"
        rm -f "$TEMP_DIR/pipeline-compare.js"
    fi
    
    echo "  Pipeline comparison feature added"
    
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
            
            # Extract major.minor for section (supports MTV 2.x, 5.x, etc.)
            major=""
            minor=""
            if [[ "$vname" =~ ^([0-9]+)[.-]([0-9]+) ]]; then
                major="${BASH_REMATCH[1]}"
                minor="${BASH_REMATCH[2]}"
            else
                echo "    [WARN] Cannot parse major.minor from '$vname'; skipping card"
                continue
            fi
            
            section_name="MTV ${major}.${minor}"
            
            # Check if section exists, if not create it
            if ! grep -qF "$section_name " "$TEMP_DIR/index.html"; then
                echo "    Creating new section: $section_name"
                # Insert new section before the first existing MTV section
                awk -v section="$section_name" '
                /class="section-title".*MTV [0-9]/ && !inserted {
                    print "        <h2 class=\"section-title\" onclick=\"toggleSection(this)\" style=\"cursor: pointer;\">📦 " section " <span class=\"toggle-icon\">▼</span></h2>"
                    print "        <div class=\"version-grid\">"
                    print "        </div>"
                    print ""
                    inserted=1
                }
                { print }
                ' "$TEMP_DIR/index.html" > "$TEMP_DIR/index.html.tmp" && mv "$TEMP_DIR/index.html.tmp" "$TEMP_DIR/index.html"
            fi
            
            # Find the section and add card after version-grid div using awk
            # Pattern: look for "MTV X.YY " (with space) in section title, then add after version-grid
            awk -v vname="$vname" -v dname="$display_name" -v pattern="$section_name " '
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
                echo "    [WARN] Failed to add card for $vname"
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
