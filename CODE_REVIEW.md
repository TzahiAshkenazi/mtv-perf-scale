# Code Review for MainMTV.sh

## Overview
`MainMTV.sh` is the entry point script for running MTV (Migration Toolkit for Virtualization) migration scenarios. It orchestrates reading test scenarios from a configuration file and executing migrations.

---

## Current Code

```bash
#!/bin/bash
set -x

source "$(pwd)/lib/common.sh"

main() {
    check_cycles_list_file
    check_root
    check_root_directory

    # Get Scenarios from cycles_list.txt located /home/$USER/MTV
    parse_cycle_list_file
    total_cycles=${#scenario_names[@]}
    i=0  # Initialize the loop variable , for scenario_name value 
    for i in "${!scenario_names[@]}"; do
        scenario_name="${scenario_names[$i]}"
        cycle_label="${cycle_labels[$i]}"
        cycle_value="${cycle_values[$i]}"

        # Set up logging - output to both screen and file, will write to the current directory
        export MAIN_LOG_FILE="${scenario_name}_STDOUT.log"

        {
          login_cluster  &> /dev/null
          # Load Vars from yaml related to this scenario
          load_scenario ${scenario_name} config/tests.yaml

          echo ""
          echo "using Scenario name: ${scenario_name} ,testcase: ${testcase} ,case: ${mtv_case} using ${VMsPrefix} ,total-vms: ${total_vms} against ${provider_url} started at: `time_stemp`"
          echo ""

          ./SetupProvider.sh
          ./RunMigration.sh

        } 2>&1 | tee "$MAIN_LOG_FILE"

        if [ -f /home/$USER/MTV/results/.latest-result.log ]; then
            source /home/$USER/MTV/results/.latest-result.log
            mv "$MAIN_LOG_FILE" "$LogsLocation/" 2>/dev/null
        fi
        ((i++))
    done
}

main
```

---

## Issues and Recommendations

### 1. Redundant Loop Variable Increment (Bug) - HIGH

**Location:** Lines 14 and 41

```bash
i=0  # Initialize the loop variable , for scenario_name value    # Line 14
for i in "${!scenario_names[@]}"; do                              # Line 15
    ...
    ((i++))                                                        # Line 41
done
```

- **Line 14**: `i=0` initialization is unnecessary since `for i in "${!scenario_names[@]}"` handles indexing.
- **Line 41**: `((i++))` is **incorrect** — the `for` loop already iterates through array indices. This would cause incorrect behavior if arrays have non-sequential indices.

**Fix**: Remove lines 14 and 41.

---

### 2. Unused Variable `total_cycles` - LOW

**Location:** Line 13

```bash
total_cycles=${#scenario_names[@]}
```

This variable is set but never used. Either remove it or use it for logging/progress indication.

---

### 3. Silent Login Failures - MEDIUM

**Location:** Line 24

```bash
login_cluster  &> /dev/null
```

This suppresses all output, including errors. If login fails, the script continues silently.

**Recommendation**: Check the return code:

```bash
if ! login_cluster &> /dev/null; then
    echo "Error: Failed to login to cluster"
    exit 1
fi
```

---

### 4. `load_scenario` Doesn't Source the Variables - HIGH

**Location:** Line 26

```bash
load_scenario ${scenario_name} config/tests.yaml
```

The `load_scenario` function in `common.sh` writes variables to `.current_scenario_vars.txt` but doesn't source them. Variables like `$testcase`, `$mtv_case`, `$VMsPrefix`, `$total_vms`, `$provider_url` used in the echo statement (line 29) won't be available in `MainMTV.sh`.

**Note**: The child scripts (`SetupProvider.sh` and `RunMigration.sh`) do source the file, so they work correctly. However, the echo statement on line 29 in `MainMTV.sh` will show empty/undefined values.

**Fix**: Add after line 26:

```bash
source "/home/$USER/MTV/.current_scenario_vars.txt"
```

---

### 5. Missing Error Handling for Child Scripts - MEDIUM

**Location:** Lines 32-33

```bash
./SetupProvider.sh
./RunMigration.sh
```

If `SetupProvider.sh` or `RunMigration.sh` fails, the script continues to the next iteration without reporting.

**Recommendation**:

```bash
./SetupProvider.sh || { echo "SetupProvider.sh failed for scenario: $scenario_name"; continue; }
./RunMigration.sh || { echo "RunMigration.sh failed for scenario: $scenario_name"; continue; }
```

---

### 6. Relative Script Paths Without Validation - MEDIUM

**Location:** Lines 32-33

`./SetupProvider.sh` and `./RunMigration.sh` are called without checking if they exist or are executable.

**Recommendation**: Add validation at the start of main():

```bash
for script in SetupProvider.sh RunMigration.sh; do
    if [[ ! -x "./$script" ]]; then
        echo "Error: $script not found or not executable"
        exit 1
    fi
done
```

---

### 7. Hardcoded Path in `source` Command - MEDIUM

**Location:** Line 4

```bash
source "$(pwd)/lib/common.sh"
```

This depends on the script being run from a specific directory. If invoked from elsewhere, it fails.

**Recommendation**: Use script's directory:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
```

---

### 8. `set -x` in Production Script - LOW

**Location:** Line 2

```bash
set -x
```

This enables debug tracing for all commands, which is verbose for production use.

**Recommendation**: Make it optional via an environment variable:

```bash
[[ "${DEBUG:-}" == "true" ]] && set -x
```

---

### 9. Missing `set -e` or Error Handling - MEDIUM

The script doesn't use `set -e` (exit on error) or have comprehensive error handling. A failure in any command (e.g., `parse_cycle_list_file`) could lead to undefined behavior.

---

### 10. Hardcoded Path for Log Result - LOW

**Location:** Line 37

```bash
if [ -f /home/$USER/MTV/results/.latest-result.log ]; then
```

The path `/home/$USER/MTV/results/` is hardcoded. This should use a variable for consistency with other paths like `$location` in `common.sh`.

---

## Suggested Refactored Version

```bash
#!/bin/bash
[[ "${DEBUG:-}" == "true" ]] && set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

main() {
    # Validate required scripts exist
    for script in SetupProvider.sh RunMigration.sh; do
        if [[ ! -x "${SCRIPT_DIR}/$script" ]]; then
            echo "Error: $script not found or not executable"
            exit 1
        fi
    done

    check_cycles_list_file
    check_root
    check_root_directory

    # Get Scenarios from cycles_list.txt located /home/$USER/MTV
    parse_cycle_list_file
    
    local total_cycles=${#scenario_names[@]}
    echo "Total scenarios to process: $total_cycles"
    
    for i in "${!scenario_names[@]}"; do
        scenario_name="${scenario_names[$i]}"
        cycle_label="${cycle_labels[$i]}"
        cycle_value="${cycle_values[$i]}"

        # Set up logging - output to both screen and file
        export MAIN_LOG_FILE="${scenario_name}_STDOUT.log"

        {
            if ! login_cluster &> /dev/null; then
                echo "Error: Failed to login to cluster"
                exit 1
            fi

            # Load Vars from yaml related to this scenario
            load_scenario "${scenario_name}" config/tests.yaml
            source "/home/$USER/MTV/.current_scenario_vars.txt"

            echo ""
            echo "Using Scenario name: ${scenario_name}, testcase: ${testcase}, case: ${mtv_case} using ${VMsPrefix}, total-vms: ${total_vms} against ${provider_url} started at: $(time_stemp)"
            echo ""

            "${SCRIPT_DIR}/SetupProvider.sh" || { echo "SetupProvider.sh failed for scenario: $scenario_name"; exit 1; }
            "${SCRIPT_DIR}/RunMigration.sh" || { echo "RunMigration.sh failed for scenario: $scenario_name"; exit 1; }

        } 2>&1 | tee "$MAIN_LOG_FILE"

        if [ -f "${location}/results/.latest-result.log" ]; then
            source "${location}/results/.latest-result.log"
            mv "$MAIN_LOG_FILE" "$LogsLocation/" 2>/dev/null
        fi
    done
}

main
```

---

## Additional Observations in Related Files

### In `common.sh`:
- **Line 15**: Hardcoded `/home/$USER/clusterconfigs/auth/kubeconfig` path — should be configurable.
- **Line 62**: `cycles_list` variable is set but never used.

### In `SetupProvider.sh`:
- **Lines 75-78**: Hardcoded base64-encoded credentials (`password`, `user`) are security concerns and should be externalized.

### In `RunMigration.sh`:
- **Lines 239-242**: Hardcoded credentials in `CreateMTVSecretForStorageOffload()`.
- **Lines 317, 340**: Hardcoded vSphere credentials in base64.

---

## Summary Table

| Severity | Issue | Location |
|----------|-------|----------|
| **High** | Redundant `((i++))` causes incorrect iteration | Lines 14, 41 |
| **High** | Variables not sourced after `load_scenario` | Line 26 |
| **Medium** | Silent login failure | Line 24 |
| **Medium** | No error handling for child scripts | Lines 32-33 |
| **Medium** | Relative script paths without validation | Lines 32-33 |
| **Medium** | Hardcoded script path in source | Line 4 |
| **Medium** | Missing `set -e` or error handling | Throughout |
| **Low** | Unused variable `total_cycles` | Line 13 |
| **Low** | `set -x` always enabled | Line 2 |
| **Low** | Hardcoded path for log result | Line 37 |

---

*Review generated on: 2026-01-25*
*Updated on: 2026-06-06*
