#!/bin/bash

#set -x

findtimediff()
{
  t1=`date -d "$1" +%s`
  t2=`date -d "$2" +%s`

  timediff=`expr ${t2} - ${t1}`

#  days=$((timediff / 86400))
#  hours=$(( (timediff % 86400) / 3600 ))
#  minutes=$(( (timediff % 3600) / 60 ))
#  seconds=$(( timediff % 60 ))


#  if [ $days -eq "0" ]
#  then
#    echo ${hours}":"${minutes}":"${seconds}
#  elif [ $days -eq "1" ]
#    then
#      echo ${days}"day" ${hours}":"${minutes}":"${seconds}
#    else
#      echo ${days}"days" ${hours}":"${minutes}":"${seconds}
#    fi

#  t1=$1
#  t2=S2
#  echo $(datediff $t1 $t2 -f '%dd %0H:%0M:%0S')
  echo `date +%H:%M:%S -ud @${timediff}`
}


# Function to convert time from hh:mm:ss to seconds
time_to_seconds() {
    local time=$1

    if [[ ! $time =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        echo "Invalid time format. Expected HH:MM:SS" $time
    fi

    local hours=$(echo $time | cut -d':' -f1)
    local minutes=$(echo $time | cut -d':' -f2)
    local seconds=$(echo $time | cut -d':' -f3)
    echo $((10#$hours * 3600 + 10#$minutes * 60 + 10#$seconds))
}


# Function to convert seconds back to hh:mm:ss
seconds_to_time() {
    local total_seconds=$1
    local hours=$((total_seconds / 3600))
    local minutes=$(( (total_seconds % 3600) / 60 ))
    local seconds=$((total_seconds % 60))
    printf "%02d:%02d:%02d\n" $hours $minutes $seconds
}


ClusterLogin()
{
  export KUBECONFIG="${KUBECONFIG:-/home/$USER/clusterconfigs/auth/kubeconfig}"
  oc login -u kubeadmin -p $(cat "${KUBECONFIG%/*}/kubeadmin-password") -n $SourceMTVns
}


CheckDateUtils()
{
  if [ ! -f /usr/bin/datediff ]
  then
    echo "Install dateutils"
    dnf install dateutils -y
  fi
}



CheckJQ()
{
  if [ ! -f /usr/bin/jq ]
  then
    echo "Install jq"
    python3.9 -m pip install --upgrade pip
    pip3 install jq
  fi
}

CheckVirtctl()
{
  # /binPATH=$(echo $PATH | sed 's/:/ /g' | awk '{print $2}')
  binPATH=/usr/local/bin
  if [ ! -f $binPATH/virtctl ]
  then
    echo "Install VirtCTL"
    
     # install wget tar
    sudo dnf install wget tar -y

    # Get the download URL for VirtCTL
    virtctlUrl=$(oc get ConsoleCLIDownload virtctl-clidownloads-kubevirt-hyperconverged -o yaml | grep linux | grep amd64 | awk '{print $NF}')

    # Download the file to /tmp
    wget --no-check-certificate -O /tmp/virtctl.tar.gz "$virtctlUrl"

    # Extract the contents to /usr/local/bin using sudo
    sudo tar -xvf /tmp/virtctl.tar.gz -C /usr/local/bin

    # Ensure the binary is executable
    sudo chmod +x /usr/local/bin/virtctl

    # Set correct permissions so non-root users can execute
    sudo chown root:root /usr/local/bin/virtctl
    sudo chmod 755 /usr/local/bin/virtctl
  fi
}

GetMigrationTime()
{
  echo $(oc get migration $PlanMigrationName -n$SourceMTVns -o jsonpath="{.status.$1}")
}

MigrationSummary()
{
  TotalVMs=$1
  echo "MigrationName:" $PlanMigrationName ", Total VMs:" $TotalVMs ", Total Duration:" $(findtimediff $(GetMigrationTime started) $(GetMigrationTime completed))
}

MigrationTime()
{
  StartDate=$(date -d $(GetMigrationTime started) +%s)
  EndDate=$(date -d $(GetMigrationTime completed) +%s)
  echo "MigrationStartTime:" $(date +"%Y-%m-%d %H:%M:%S" -ud @$StartDate) " ,  MigrationEndTime:" $(date +"%Y-%m-%d %H:%M:%S" -ud @$EndDate)
}


TargetNamespaceSummary()
{
  MigrationPlanName=$(oc get migration $PlanMigrationName -n$SourceMTVns -o jsonpath="{.spec.plan.name}")
  TargetMigrationNS=$(oc get plan $MigrationPlanName -n$SourceMTVns -o jsonpath="{.spec.targetNamespace}")

  echo "TargetNamespace:" $TargetMigrationNS ", Total VMs:" $(oc get virtualmachine -n$TargetMigrationNS | grep -v NAME | wc -l )
}

MigrationStatus()
{
  echo "MigrationStatus:" $(oc get migration $PlanMigrationName -n$SourceMTVns -o jsonpath="{.status.conditions[$1].type}")
}

CollectLogs()
{
  MigrationPlanName=$(oc get migration $PlanMigrationName -n$SourceMTVns -o jsonpath="{.spec.plan.name}")
  TargetNamespace=$(oc get plan $MigrationPlanName -n$SourceMTVns -o jsonpath="{.spec.targetNamespace}")

  # Get Forklift-controller configuration
  oc get forkliftcontroller forklift-controller -n$SourceMTVns -o json > ${LogsLocation}/ForkliftController_forklift-controller.json

  # Get Provider configuration
  oc get provider ${provider_name} -n$SourceMTVns -o json > ${LogsLocation}/Provider_configuration.json

  # Get Json output of Plan
  oc get plan $PlanMigrationName -n$SourceMTVns -o json > ${LogsLocation}/Plan_${MigrationPlanName}.json
  oc get migration $PlanMigrationName -n$SourceMTVns -o json > ${LogsLocation}/Migration_${MigrationPlanName}.json
  
  ### Collect MTV pods logs
  for getpod in $(oc get pods -n$SourceMTVns | grep forklift | cut -d " " -f1)
  do
    oc logs $getpod -n$SourceMTVns > ${LogsLocation}/MTV_${getpod}.log
    oc describe pod $getpod -n$SourceMTVns > ${LogsLocation}/MTV_${getpod}.txt

    ### MTV-2775 , Collect forklift-controller Reconcile duration
    if [[ "$getpod" == *'forklift-controller'* ]]; then
      oc logs $getpod -n$SourceMTVns -c main | egrep "plan.*Reconcile started|plan.*Reconcile ended" > ${LogsLocation}/ForkliftController_Reconcile.log
    fi
    sleep 1
  done  

  ### Collect VirtV2V pods logs
  for getpod in $(oc get pods -n$TargetNamespace | grep ${MigrationPlanName} | grep -v vddk | cut -d " " -f1)
  do
    oc logs $getpod -n$TargetNamespace > ${LogsLocation}/VirtV2V_${getpod}.log
    oc describe pod $getpod -n$TargetNamespace > ${LogsLocation}/VirtV2V_${getpod}.txt
    sleep 1
  done

  ### Collect populate pods logs (only for StorageOffload migrations)
  if [ "$StorageOffload" == "true" ]; then
    for getpod in $(oc get pods -n$TargetNamespace --no-headers 2>/dev/null | grep populate | awk '{print $1}')
    do
      oc logs $getpod -n$TargetNamespace > ${LogsLocation}/Populate_${getpod}.log 2>&1
      oc describe pod $getpod -n$TargetNamespace > ${LogsLocation}/Populate_${getpod}.txt 2>&1
      sleep 1
    done
  fi

  ### Copy importer logs collected during migration (from temp folder)
  if [ -n "$IMPORTER_LOGS_TMP" ] && [ -d "$IMPORTER_LOGS_TMP" ]; then
    cp "$IMPORTER_LOGS_TMP"/Importer_*.log "${LogsLocation}/" 2>/dev/null
    echo "Copied importer logs from $IMPORTER_LOGS_TMP to ${LogsLocation}/"
    rm -rf "$IMPORTER_LOGS_TMP"
    echo "Cleaned up temp folder: $IMPORTER_LOGS_TMP"
  fi

  ### Copy populate pod logs collected during migration (from temp folder)
  if [ -n "$POPULATE_LOGS_TMP" ] && [ -d "$POPULATE_LOGS_TMP" ]; then
    cp "$POPULATE_LOGS_TMP"/Populate_*.log "${LogsLocation}/" 2>/dev/null
    echo "Copied populate logs from $POPULATE_LOGS_TMP to ${LogsLocation}/"
    rm -rf "$POPULATE_LOGS_TMP"
    echo "Cleaned up temp folder: $POPULATE_LOGS_TMP"
  fi
}

MigrationType()
{
  MigrationPlanName=$(oc get migration $PlanMigrationName -n$SourceMTVns -o jsonpath="{.spec.plan.name}")
  GetMigrationType=$(oc get plan $MigrationPlanName -n$SourceMTVns -o jsonpath="{.spec.warm}")
  
  if [ -z "${GetMigrationType}" ]
  then
    GetMigrationType="COLD"
  else
    GetMigrationType="WARM"
  fi

  echo "MigrationType:" $GetMigrationType
}

ParseMigrationCR()
{
  echo $(oc get migration $PlanMigrationName -n$SourceMTVns -o jsonpath="{.status.vms[$vm].$1}")
}

ParseMigrationSteps()
{
echo $(oc get migration $PlanMigrationName -n$SourceMTVns -o jsonpath="{.status.vms[$vm].pipeline[$planstep].$1}")
}

MTVversion()
{
  OPERATOR_NAME="mtv-operator"
  NAMESPACE="openshift-mtv"

  CATALOG=$(oc get subs $OPERATOR_NAME -n $NAMESPACE -o=custom-columns=SOURCE:.spec.source --no-headers --ignore-not-found)
  INDEX=$(oc get catsrc ${CATALOG} -n openshift-marketplace -ojsonpath='{.spec.image}' --ignore-not-found | grep -Eo "iib:[0-9]+") || true
  csv=""

  if [[ -n $INDEX ]]; then
    csv=$(curl -s -k https://${DATAGREPPER_HOST}/raw\?topic\=/topic/VirtualTopic.eng.ci.redhat-container-image.index.built\&contains\=${INDEX}\&rows_per_page\=1\&delta\=15552000 2>/dev/null | jq -r '.raw_messages[0].msg.artifact.nvr')
  fi

  if [[ -z $csv ]]; then
    csv=$(oc get subs $OPERATOR_NAME -n $NAMESPACE -o=custom-columns=SOURCE:.status.installedCSV --no-headers)
  fi

  echo "MTV Version:" $(echo "$csv" | awk -F - '{print $(NF-1)"-"$NF}')  " ,  IIB:" $INDEX
}

MigrationVMduraion()
{
  echo -n $(ParseMigrationCR name) $(findtimediff $(ParseMigrationCR started) $(ParseMigrationCR completed)) >> $BreakdownOutputFile
}

MigrationStepsBreakdown()
{
  echo -n "" $(findtimediff $(ParseMigrationSteps started) $(ParseMigrationSteps completed)) >> $BreakdownOutputFile
}


######################
#####    MAIN    #####
######################

if [ -z $1 ]  
then
  echo ""
  echo "Usage: $0 [MigrationCRname] [SourceMTVns]"
  echo "SourceMTVns is not mandatory. Default: openshift-mtv"
  echo "Example $0 10vms-1esx-default-network "
  echo "Example $0 10vms-1esx-default-network openshift-mtv"
  echo "Abort script!!!"
  exit 1
fi

PlanMigrationName=$1
if [ -z $2 ]
then
  SourceMTVns="openshift-mtv"
else
  SourceMTVns=$2
fi

ClusterLogin
CheckJQ
CheckVirtctl
MTV_BUILD=`$(dirname "$0")/utils/find-version-build.sh`
LogsLocation="/home/$USER/MTV/results/${MTV_BUILD}/${PlanMigrationName}/logs/${PlanMigrationName}_${ReportDate}"
BreakdownOutputFile="$LogsLocation/MigrationBreakdown_${PlanMigrationName}_${ReportDate}.txt"
mkdir -p $LogsLocation

# Store LogsLocation and BreakdownOutputFile as vars to be sourced in other scripts
cat <<EOF > /home/$USER/MTV/results/.latest-result.log
export LogsLocation="$LogsLocation"
export BreakdownOutputFile="$BreakdownOutputFile"
EOF

# Collect MTV pods log, Plan & Migration CR
CollectLogs

#########################################
### Get Total Migration VMs and Steps ###
#########################################
TotalVMs=$(oc get migration $PlanMigrationName -n$SourceMTVns -o json | jq '.status.vms | length')
TotalSteps=$(oc get migration $PlanMigrationName -n$SourceMTVns -o json | jq '.status.vms[0].pipeline | length')

################################################
### Create Array of MigrationStep for Header ###
################################################
StepNameArray[0]="VM"
StepNameArray[1]="MigrationTime"

for planstep in `seq 0 $(( TotalSteps - 1 ))`
do
  vm=0
  StepNameArray[$planstep+2]="$(ParseMigrationSteps name)"
done


######################################
### Define Vars for Dynamic Values ###
######################################
declare -a HeaderLength
for stepname in ${StepNameArray[@]}
do
  HeaderLength+=($((${#stepname}))) 
done


##################################################
### Create Format for Print Header and Results ###
##################################################
OutputFormat=""
for length in "${HeaderLength[@]}"; do
    OutputFormat+="%-${length}s "
done
OutputFormat+="\n"
#OutputFormat="${OutputFormat/2/40}"
OutputFormat="${OutputFormat/${#StepNameArray[0]}/40}"
OutputFormat="${OutputFormat/${#StepNameArray[4]}/14}"
##################################printf "$OutputFormat" "${StepNameArray[@]}"

###############################
### Print '-' under headers ###
###############################
HeaderLine=()
for length in "${HeaderLength[@]}"; do
    HeaderLine+=($(printf '%0.s-' $(seq 1 $length)))
done

 
##########################
### Parse migration CR ###
##########################
for vm in `seq 0 $(( TotalVMs - 1 ))`
do
  MigrationVMduraion
  for planstep in `seq 0 $(( TotalSteps - 1 ))`
  do
    MigrationStepsBreakdown
  done
  echo >> $BreakdownOutputFile
done

data=$(cat $BreakdownOutputFile)
> $BreakdownOutputFile


#####################################
###### Print Migration Summary ######
#####################################
echo "Report Date:" $(date +"%Y-%m-%d  ,  %H:%M:%S") >> $BreakdownOutputFile
MTVversion >> $BreakdownOutputFile
MigrationTime >> $BreakdownOutputFile
MigrationSummary $TotalVMs >> $BreakdownOutputFile
TargetNamespaceSummary >> $BreakdownOutputFile
MigrationType >> $BreakdownOutputFile
MigrationStatus 1 >> $BreakdownOutputFile
echo "" >> $BreakdownOutputFile


###############################
###### Print the headers ######
###############################
printf "$OutputFormat" "${StepNameArray[@]}" >> $BreakdownOutputFile
printf "$OutputFormat" "${HeaderLine[@]}" >> $BreakdownOutputFile


############################
### Print migration data ###
############################
while IFS= read -r line; do
  IFS=' ' read -r  "${StepNameArray[@]}"<<< "$line"

  values=()
  for stepname in ${StepNameArray[@]}
  do
    values+=("${!stepname}")
  done

  printf "$OutputFormat" "${values[@]}" >> $BreakdownOutputFile
done <<< "$data"

#########################################
###   ADD SUMMARY - MIN , MAX , AVG   ###
#########################################

datafile=$BreakdownOutputFile
DataStartLine=$(grep -n "\-\-"  $datafile | cut -d: -f1)

# Read the header line to get column count
header=$(tail -1 "$datafile")
total_columns=$(awk '{print NF}' <<< "$header")

# Initialize arrays to store min, max, and avg for each column
declare -a min_array
declare -a max_array
declare -a avg_array

# Loop through each column (starting from 2nd to ignore VM column)
for col in $(seq 2 $total_columns)
do
  #times=($(awk "NR>10 {print \$$((col))}" "$datafile"))
  times=($(awk -v start="$DataStartLine" "NR>start {print \$$((col))}" "$datafile"))

  # Initialize min, max, sum
  min=999999
  max=0
  sum=0

  # Convert times to seconds and find min, max, and sum
  for time in "${times[@]}"
  do
    seconds=$(time_to_seconds "$time")
    if (( seconds < min )); then min=$seconds; fi
    if (( seconds > max )); then max=$seconds; fi
    sum=$((sum + seconds))
   done

   # Calculate average
   avg=$((sum / ${#times[@]}))

   # Store results in arrays
   min_array[$col]=$(seconds_to_time $min)
   max_array[$col]=$(seconds_to_time $max)
   avg_array[$col]=$(seconds_to_time $avg)
done

echo "" >> $BreakdownOutputFile
printf "$OutputFormat" "avg" "${avg_array[@]}" >> $BreakdownOutputFile
printf "$OutputFormat" "min" "${min_array[@]}" >> $BreakdownOutputFile
printf "$OutputFormat" "max" "${max_array[@]}" >> $BreakdownOutputFile

