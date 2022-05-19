#!/bin/bash

HOST_FILE=./host.list

for IP in $(cat ${HOST_FILE} | awk '{print $6}')
do
    echo "On host ${IP}"
    ssh -oStrictHostKeyChecking=no azureuser@${IP} sudo netplan apply
    ssh -oStrictHostKeyChecking=no azureuser@${IP} cat /etc/resolv.conf
done
