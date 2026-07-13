#!/bin/bash

# location of cycles_list.txt
location="/home/$USER/MTV"

mkdir -p "${location}"

# Declare arrays globally to store parsed values
scenario_names=()
cycle_labels=()
cycle_values=()


login_cluster() {
    export KUBECONFIG="${KUBECONFIG:-/home/$USER/clusterconfigs/auth/kubeconfig}"
    oc login -u kubeadmin -p $(cat "${KUBECONFIG%/*}/kubeadmin-password") -ndefault
}

load_scenario() {
  local scenario_name="$1"
  local yaml_file="$2"
  
  # Overwrite the file so old variables don't persist
  : > $location/.current_scenario_vars.txt

  # Read all top-level keys in the matching scenario.
  local top_keys
  IFS=$'\n' read -rd '' -a top_keys < <(
    yq e ".scenarios[] | select(.name == \"${scenario_name}\") | keys | .[]" "${yaml_file}"
  )

  # Iterate over each top-level key
  for key in "${top_keys[@]}"; do
    if [[ "${key}" == "provider" ]]; then
      # Handle nested 'provider' object with a prefix
      local provider_keys
      IFS=$'\n' read -rd '' -a provider_keys < <(
        yq e ".scenarios[] | select(.name == \"${scenario_name}\") | .provider | keys | .[]" "${yaml_file}"
      )

      for pkey in "${provider_keys[@]}"; do
        local pvalue
        pvalue="$(yq e ".scenarios[] | select(.name == \"${scenario_name}\") | .provider.${pkey}" "${yaml_file}")"
        pvalue="$(echo "${pvalue}" | envsubst)"
        # Write to $location/.current_scenario_vars.txt as an export statement
        printf 'export provider_%s=%q\n' "${pkey}" "${pvalue}" >> $location/.current_scenario_vars.txt
      done
    else
      # Read the scalar value
      local value
      value="$(yq e ".scenarios[] | select(.name == \"${scenario_name}\") | .\"${key}\"" "${yaml_file}")"
      value="$(echo "${value}" | envsubst)"
      # Handle 'case' specially since it's a bash reserved word
      local export_key="${key}"
      if [[ "${key}" == "case" ]]; then
        export_key="mtv_case"
      fi
      # Write to $location/.current_scenario_vars.txt as an export statement
      printf 'export %s=%q\n' "${export_key}" "${value}" >> $location/.current_scenario_vars.txt
    fi
  done
}

check_cycles_list_file() {
    if [[ ! -f ${location}/cycles_list.txt ]] ; then
        echo "File "${location}/cycles_list.txt" doesn't exist , aborting.
              (please create this file with the test case scenarios you want to run under ${location})"
        exit
    else 
        cycles_list=`cat "${location}/cycles_list.txt"` > /dev/null 2>&1                    
    fi
}

sleep_timer_countdown_cycles(){
    start_timer=`date '+%Y-%m-%d--%H:%M:%S'`
    for ((i=${sleep_duration_cycle}; i>=0; i--)); do
        echo -ne "Sleep Timer Activated At ${start_timer} for: $i seconds \r"
        sleep 1
    done
}

time_stemp() {
    date '+%Y-%m-%d-%H:%M:%S'
}



# Function to check if the script is running as root
check_root() {
    if [ "$(id -u)" -eq 0 ]; then
        echo "Error: Running as root is not supported. Please run the script as a regular user."
        exit 1
    fi
}

# Function to check if the script is being executed from a directory containing /root
check_root_directory() {
    current_directory="$(pwd)"
    root_directory="/root"

    if [[ "$current_directory" == *"$root_directory"* ]]; then
        echo "Error: Running the script from a directory containing /root is not allowed."
        exit 1
    fi
}

parse_cycle_list_file() {
    # Function to read file and process each line
    local file_path="${location}/cycles_list.txt"
    # Read file line by line and process each line
    while IFS= read -r line; do
        # Trim extra spaces and split the line into words
        read -r -a words <<< "$line"
        # Get the length of the array
        word_count="${#words[@]}"

        if [ "$word_count" -eq 1 ]; then
            scenario_names+=("${words[0]}")
            cycle_labels+=("")
            cycle_values+=("")
            echo "Scenario_name=${words[0]}"
        elif [ "$word_count" -eq 3 ]; then
            scenario_names+=("${words[0]}")
            cycle_labels+=("${words[1]}")
            cycle_values+=("${words[2]}")
            echo "Scenario_name=${words[0]}, cycle_label=${words[1]}, cycle_value=${words[2]}"
        else
            echo "Its seems like the file=${file_path} does not contain  any values. The script will exit now."
            exit 1
        fi
    done < "$file_path"
}    
