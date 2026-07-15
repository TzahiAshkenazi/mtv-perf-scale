#!/bin/bash
# This script runs 4 ansible playbooks concurrently, checks that none fail,
# and then polls for the presence of 4 JSON files in a specified directory for up to 5 minutes.

###########################
# Configurable Variables  #
###########################
# Paths to the ansible playbook files
ANSIBLE_SCRIPT1="utils/get_env_version_details.yaml"
ANSIBLE_SCRIPT2="utils/get_vsphere_sessions.yaml"
ANSIBLE_SCRIPT3="utils/get_vm_disk_utilization.yaml"
ANSIBLE_SCRIPT4="utils/vsphere_details.yaml"

# Directory where the JSON files are expected
result_dir=$0
#"/tmp/MTV/results/mtv280-5vms-dsl-cold_20250305-122651/.report-artifacts"
# Expected number of JSON files
EXPECTED_JSON_COUNT=4

# Polling parameters
TIMEOUT=300           # total polling time in seconds (5 minutes)
SLEEP_INTERVAL=5      # seconds to sleep between polls

###########################
# Functions               #
###########################

# Validate that result_dir was supplied and is a valid (and  not empty) directory.
validate_result_dir() {
    if [ -z "$result_dir" ]; then
        echo "Usage: $0 /path/to/json/directory"
        echo "Error: result_dir must be supplied as a CLI argument."
        exit 1
    fi

    if [ ! -d "$result_dir" ]; then
        echo "Error: $result_dir is not a valid directory."
        exit 1
    fi

    # Ensure the directory is not empty
    if [ "$(ls -A "$result_dir")" == "0" ]; then
        echo "Error: result_dir ($result_dir) is not empty. Please provide an empty directory."
        exit 1
    fi
}

# Function to get the VM name from a migration plan file.
get_vm_name_from_mig_plan() {
    local migfile
    migfile=$(find "$result_dir" -type f -iname "Migration*.json" | head -n 1)      #migfile=$(find "$result_dir" -type f -iname "*Plan*" | head -n 1)
    if [ -z "$migfile" ]; then
        # No migration plan file found, return 0.
        echo 0
    else
        # Extract the first VM's name from the file.
        local vm_name
        vm_name=$(jq -r '.status.vms[0].name' "$migfile")
        echo "$vm_name"
    fi
}

# Function to get the count of VMs from a migration plan file.
get_vm_count_from_mig_plan() {
    local migfile
    migfile=$(find "$result_dir" -type f -iname "Migration*.json" | head -n 1)        #migfile=$(find "$result_dir" -type f -iname "*Plan*" | head -n 1)
    if [ -z "$migfile" ]; then
        # No migration plan file found, return 0.
        echo 0
    else
        # Count the number of VMs in the file.
        local num_of_vms
        num_of_vms=$(jq '.status.vms | length' "$migfile")
        echo "$num_of_vms"
    fi
}
# Search inside result_dir for a file whose name contains "Breakdown"
# and return its full path.
find_breakdown_file() {
    local file
    file=$(find "$result_dir" -type f -iname "*Breakdown*" | head -n 1)
    if [ -z "$file" ]; then
        return 1
    else
        # Returning the file path by printing it.
        return 0
    fi
}

#Install UV if not present
install_uv() {
  if ! command -v uv &> /dev/null; then
    echo "uv is not installed. Installing..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
  else
    echo "uv is already installed."
  fi
}

# Install uv, run the report parser via uv, and verify its output.
run_uv_report_parser() {
    
    echo "Running report_parser.py using uv..."
    # If we don’t have a project yet, create one
    if [ ! -f pyproject.toml ]; then
    uv init
    fi

    # Run the report parser with the JSON directory as the test result path.
    uv add requests boto3 uuid datetime path
    output=$(uv run utils/report_parser.py --test-result-path "$breakdown_file_result")
    echo "Output from uv command:"
    echo "$output"

    # Count the occurrences of "Successfully uploaded" in the output.
    count=$(echo "$output" | grep -o "Successfully uploaded" | wc -l)
    if [ "$count" -ge 2 ]; then
        echo "Report parser verification succeeded: Uploads to ELK and S3 were successful."
    else
        echo "Error: Expected at least 2 occurrences of 'Successfully uploaded' but found $count."
        exit 1
    fi
}

# Run ansible playbooks concurrently and check exit statuses.
run_ansible_scripts() {
    
    total_vms=$(get_vm_count_from_mig_plan)
    #vm_name=$(get_vm_name_from_mig_plan)
    echo "Starting ansible playbooks concurrently..."
    # Get the VM name from the migration plan.
    vm_name=$(get_vm_name_from_mig_plan)
    echo "Migration Plan contains vm called: $vm_name"

    # Get the VM count from the migration plan.
    vm_count=$(get_vm_count_from_mig_plan)
    echo "Total VMs in plan are: $vm_count"

    # Get the vSphere URL from the provider URL and remove https:// and /sdk
    vSphere_url="${provider_url#*://}"
    vSphere_url="${vSphere_url%%/*}"

    # Launch each playbook in the background and store its PID.
    ansible-playbook "$ANSIBLE_SCRIPT1" -e result_directory="$result_dir" -vvv &
    pid1=$!
    ansible-playbook "$ANSIBLE_SCRIPT2" -e result_directory="$result_dir" -e vSphere_url="$vSphere_url" -vvv &
    pid2=$!
    ansible-playbook "$ANSIBLE_SCRIPT3" -e result_directory="$result_dir" -e vm_name="$vm_name" -e total_vms="$vm_count" -e vSphere_url="$vSphere_url" -vvv &
    pid3=$!
    ansible-playbook "$ANSIBLE_SCRIPT4" -e result_directory="$result_dir" -e vSphere_url="$vSphere_url" -vvv &
    pid4=$!

    # Wait for each process to complete and capture its exit code.
    wait $pid1; rc1=$?
    wait $pid2; rc2=$?
    wait $pid3; rc3=$?
    wait $pid4; rc4=$?

    # If any playbook returns a non-zero exit code, then an error occurred.
    if [[ $rc1 -ne 0 || $rc2 -ne 0 || $rc3 -ne 0 || $rc4 -ne 0 ]]; then
        echo "Error: One or more ansible playbooks failed."
        exit 1
    else
        echo "All ansible playbooks completed successfully."
    fi
}

# Poll for the presence of the expected JSON files.
poll_json_files() {
    echo "Polling for JSON files in directory: $json_dir"
    SECONDS=0  # built-in timer variable

    while [ $SECONDS -le $TIMEOUT ]; do
        # Count how many JSON files exist in the directory (non-recursively).
        json_count=$(find "$json_dir" -maxdepth 1 -type f -name '*.json' | wc -l)

        if [ "$json_count" -eq "$EXPECTED_JSON_COUNT" ]; then
            echo "Success: Found $EXPECTED_JSON_COUNT JSON files."
            return 0
        fi

        sleep $SLEEP_INTERVAL
    done

    echo "Error: Timeout reached. Expected JSON files not found in $result_dir."
    return 1
}

###########################
# Main Script Execution   #
###########################
main() {
    # Get the JSON directory from the first command-line argument.
    result_dir="$1"
    json_dir=$result_dir/.report-artifacts
    validate_result_dir

    run_ansible_scripts

    if ! poll_json_files; then
        echo "Exiting due to missing JSON files."
        exit 1
    fi

   # find and display the breakdown file.
    breakdown_file_result=`find "$result_dir" -type f -iname "*Breakdown*" | head -n 1`
    if [ $? -ne 0 ]; then
        echo "Exiting due to missing migration breakdown file in $result_dir"
        exit 1
    fi

    install_uv
    run_uv_report_parser

    echo "All tasks completed successfully."
}

main "$@"

