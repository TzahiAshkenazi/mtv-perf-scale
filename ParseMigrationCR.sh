#!/bin/bash

#set -x

findtimediff()
{
  t1=`date -d "$1" +%s`
  t2=`date -d "$2" +%s`

  timediff=`expr ${t2} - ${t1}`

  echo `date +%H:%M:%S -ud @${timediff}`
}


ClusterLogin()
{
  export KUBECONFIG="${KUBECONFIG:-/home/$USER/clusterconfigs/auth/kubeconfig}"
  oc login -u kubeadmin -p $(cat "${KUBECONFIG%/*}/kubeadmin-password") -n $SourceMTVns
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
  binPATH=$(echo $PATH | sed 's/:/ /g' | awk '{print $2}')

  if [ ! -f $binPATH/virtctl ]
  then
    echo "Install VirtCTL"
    virtctlUrl=$(oc get ConsoleCLIDownload virtctl-clidownloads-kubevirt-hyperconverged -o yaml | grep linux | grep amd64 | awk '{print $NF}')
    cd $binPATH
    wget $virtctlUrl 
    tar -xvf virtctl.tar.gz
    chmod +x virtctl
  fi
}

GetMigrationTime()
{
  echo $(oc get migration $PlanMigrationName -n$SourceMTVns -o jsonpath="{.status.$1}")
}

MigrationSummary()
{
  echo "MigrationName:" $PlanMigrationName ", Total VMs:" $(oc get virtualmachine -n$TargetMigrationNS | grep -v NAME | wc -l ) ", Total Duration:" $(findtimediff $(GetMigrationTime started) $(GetMigrationTime completed)) "\n"
}

ParseMigrationCR()
{
  echo $(oc get migration $PlanMigrationName -n$SourceMTVns -o jsonpath="{.status.vms[$vm].$1}")
}

ParseMigrationSteps()
{
  echo $(oc get migration $PlanMigrationName -n$SourceMTVns -o jsonpath="{.status.vms[$vm].pipeline[$planstep].$1}")
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

if [ -z $1 ] || [ -z $2 ] 
then
  echo ""
  echo "Usage: $0 [MigrationCRname] [TargetMigrationNS] [SourceMTVns]"
  echo "SourceMTVns is not mandatory. Default: openshift-mtv"
  echo "Example $0 10vms-1esx-default-network mtv26_10vms-1esx"
  echo "Example $0 10vms-1esx-default-network mtv26_10vms-1esx openshift-mtv"
  echo "Abort script!!!"
  exit 1
fi

PlanMigrationName=$1
TargetMigrationNS=$2
if [ -z $3 ]
then
  SourceMTVns="openshift-mtv"
else
  SourceMTVns=$3
fi

BreakdownOutputFile="MigrationBreakdown_$(date +"%Y%m%d-%H%M%S").txt"

ClusterLogin
CheckJQ
CheckVirtctl

TotalVMs=$(oc get migration $PlanMigrationName -n$SourceMTVns -o json | jq '.status.vms | length')
TotalSteps=$(oc get migration $PlanMigrationName -n$SourceMTVns -o json | jq '.status.vms[0].pipeline | length')

# Parse migration CR
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

MigrationSummary

# Print the headers
printf "%-40s %-15s %-12s %-16s %-17s %-17s %-25s\n" "VM" "MigrationTime" "Initialize" "DiskAllocation" "ImageConversion" "DiskTransferV2v" "VirtualMachineCreation" >> $BreakdownOutputFile
printf "%-40s %-15s %-12s %-16s %-17s %-17s %-25s\n" "--" "-------------" "----------" "--------------" "---------------" "----------------" "----------------------" >> $BreakdownOutputFile

# Print migration data
while IFS= read -r line; do
  IFS=' ' read -r vm migration_time initialize disk_allocation image_conversion disk_transfer_v2v vm_creation <<< "$line"

  printf "%-40s %-15s %-12s %-16s %-17s %-17s %-25s\n" "$vm" "$migration_time" "$initialize" "$disk_allocation" "$image_conversion" "$disk_transfer_v2v" "$vm_creation" >> $BreakdownOutputFile
done <<< "$data"

# Print summary in the 1st line 
sed -i "1i $(MigrationSummary)" $BreakdownOutputFile
