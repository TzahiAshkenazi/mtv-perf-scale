#!/bin/bash
# It will return the operator version along with release tag for pre-stage build and operator version for stage/GA build
# Pass subscription name and name space of the operator as command line arguments

#"redhat-oadp-operator" (1)
#"openshift-adp" (2)

if [ -z $1 ] || [ -z $2 ] 
then
  # echo "No Args, Using defaults for -operatorDP"
  OPERATOR_NAME="mtv-operator"
  NAMESPACE="openshift-mtv"
else
  OPERATOR_NAME=$1
  NAMESPACE=$2
fi

if [[ "$NAMESPACE" == 'openshift-mtv' ]]; then
    # Execute oc get csv and grep for versions
    operatorVersion=$(oc get sub -nopenshift-mtv mtv-operator -oyaml | yq -r '.spec.source')
 
    if [[ "$operatorVersion" == *'redhat'* ]]; then
      ver=$(oc get sub -nopenshift-mtv mtv-operator -oyaml | yq -r '.status.installedCSV')
      echo "${ver##*v}"
    else
      echo "${operatorVersion#iib-}"
    fi
else
        CATALOG=$(oc get subs $OPERATOR_NAME -n $NAMESPACE -o=custom-columns=SOURCE:.spec.source --no-headers --ignore-not-found)
        INDEX=$(oc get catsrc ${CATALOG} -n openshift-marketplace -ojsonpath='{.spec.image}' --ignore-not-found | grep -Eo "iib:[0-9]+") || true
        csv=""

        if [[ -n $INDEX ]]; then
          #adding delta so the messages as old as 6 months will get included
          csv=$(curl -k -s -S https://${DATAGREPPER_HOST}/raw\?topic\=/topic/VirtualTopic.eng.ci.redhat-container-image.index.built\&contains\=${INDEX}\&rows_per_page\=1\&delta\=15552000 | jq -r '.raw_messages[0].msg.artifact.nvr')
        fi

        if [[ -z $csv ]]; then
          csv=$(oc get subs $OPERATOR_NAME -n $NAMESPACE -o=custom-columns=SOURCE:.status.installedCSV --no-headers)
        fi
        #echo $INDEX
        echo $csv
fi
# set -ex
