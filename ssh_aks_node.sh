#!/bin/bash

#
# See https://docs.microsoft.com/en-us/azure/aks/ssh#create-the-ssh-connection for details
#
SUBSCRIPTION=$1
RESOURCE_GROUP=$2
CLUSTER_NAME=$3
if [ -z "${SUBSCRIPTION}" ]; then
	echo "Missing SUBSCRIPTION parameter.  Something like Chimera-U, Chimera-U-DEV, Chimera-PB, Chimera-PB-DEV"
	exit
fi
if [ -z "${RESOURCE_GROUP}" ]; then
        echo "Missing RESOURCE_GROUP parameter.  Something like AnalyticalPlatform"
        exit
fi
if [ -z "${CLUSTER_NAME}" ]; then
        echo "Missing CLUSTER_NAME parameter.  Something like scylladev, scyllaprod, hogwarts-aks-pb"
        exit
fi


CLUSTER_RESOURCE_GROUP=$(az aks show --subscription ${SUBSCRIPTION} --resource-group ${RESOURCE_GROUP} --name ${CLUSTER_NAME} --query nodeResourceGroup -o tsv)
echo "Auto-discovered AKS RG for ${CLUSTER_NAME} is \"${CLUSTER_RESOURCE_GROUP}\""

echo
az vmss list \
    --subscription ${SUBSCRIPTION} \
    --resource-group ${CLUSTER_RESOURCE_GROUP} \
    -o table
echo
read -p "Enter the name of the set you want to access: " SCALE_SET_NAME
echo "${SCALE_SET_NAME}"

az vmss extension set  \
    --subscription ${SUBSCRIPTION} \
    --resource-group $CLUSTER_RESOURCE_GROUP \
    --vmss-name $SCALE_SET_NAME \
    --name VMAccessForLinux \
    --publisher Microsoft.OSTCExtensions \
    --version 1.4 \
    --protected-settings "{\"username\":\"azureuser\", \"ssh_key\":\"$(cat ~/.ssh/id_rsa.pub)\"}" > az_vmss_ext.log
if [ $? != 0 ]; then
	echo "Failed at:"
	echo "az vmss extension set --subscription ${SUBSCRIPTION} --resource-group $CLUSTER_RESOURCE_GROUP --vmss-name $SCALE_SET_NAME --name VMAccessForLinux --publisher Microsoft.OSTCExtensions --version 1.4 --protected-settings..."
	exit
fi

az vmss update-instances --instance-ids '*' \
    --subscription ${SUBSCRIPTION} \
    --resource-group $CLUSTER_RESOURCE_GROUP \
    --name $SCALE_SET_NAME > az_vmss_update.log
if [ $? != 0 ]; then
	echo "Failed at:"
	echo "az vmss update-instances --instance-ids '*' --resource-group $CLUSTER_RESOURCE_GROUP --name $SCALE_SET_NAME"
        exit
fi

kubectl get nodes -o wide

echo "To SSH to a node, use it's IP address and the command"
echo " ssh azureuser@[Node IP]"

#echo "Once inside the debian container, install ssh by running:"
#echo "apt-get update && apt-get install openssh-client -y"
#kubectl run -it --rm aks-ssh --image=debian