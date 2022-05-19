#!/bin/bash

while true
do
    for IP in `kubectl get nodes -o wide | grep spark | awk '{print $6}'` 
    do 
        JSON=$(ssh -q -t azureuser@${IP} 'curl -sS -H Metadata:true http://169.254.169.254/metadata/scheduledevents?api-version=2020-07-01')
        DOC_INC=$(echo ${JSON} | jq '.DocumentIncarnation')
        if [[ ! -z "${DOC_INC}" ]]; then
            EVENT_SIZE=$(echo ${JSON} | jq '.Events | length')
            if [[ ${EVENT_SIZE} -gt 0 ]]; then
                echo "AKS Node ${IP} at `date '+%Y-%m-%d %H:%M:%S'`"
                echo ${JSON} | jq .
            fi
        fi
        #echo ${JSON} | jq .
    done
    sleep 30
done