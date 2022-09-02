#!/bin/bash

#
# See https://docs.microsoft.com/en-us/azure/aks/ssh#create-the-ssh-connection for details
#

SUBSCRIPTION=""
RESOURCE_GROUP="AnalyticalPlatform"
CLUSTER_NAME=""
USE_YUBI_KEY=0

function usage() {
    echo "Usage:"
    echo "  Helper script to allow for ssh'ing into a kubernetes node running"
    echo "  in AKS.  The ssh public will be copied to the nodeset"
    echo ""
    echo "    ./ssh_aks_node.sh \\"
    echo "         -s|--subscription <subscription> (Something like Chimera-U,"
    echo "                           Chimera-U-DEV, Chimera-PB, Chimera-PB-DEV)"
    echo "         -r|--resource-group <resource group> (The default resource"
    echo "                                         group is AnalyticalPlatform)"
    echo "         -c|--cluster-name <cluster name> (Something like scylladev,"
    echo "                                         scyllaprod, hogwarts-aks-pb)"
    echo "         -y|--use-yubi-key (optional empty parameter, tell the script"
    echo "                               to get the ssh key from your yubi key)"
    echo ""
    echo "  If --use-yubi-key is not used then the script will look for your"
    echo "  ssh key in ${HOME}/.ssh/id_rsa.pub"
    echo ""
    echo "  If --use-yubi-key is set then the script will try finding the ssh"
    echo "  key using gpg --export-ssh-key ${USER}, if that fails it will"
    echo "  prompt for a unique identifier for your key after listing all"
    echo "  available keys"

    exit 1
}

if [[ $# -eq 0 ]]; then
    usage
fi

while [[ $# -gt 0 ]]; do
    ARG="$1"

    case $ARG in
        -s|--subscription)
            SUBSCRIPTION="$2"
            shift
            shift
            ;;
        -r|--resource-group)
            RESOURCE_GROUP="$2"
            shift
            shift
            ;;
        -c|--cluster-name)
            CLUSTER_NAME="$2"
            shift
            shift
            ;;
        -y|--use-yubi-key)
            USE_YUBI_KEY=1
            shift
            ;;
        *)
            usage
            ;;
    esac
done

if [[ -z "${SUBSCRIPTION}" ]]; then
    printf "Missing a subscription\n\n"
    usage
fi

if [[ -z "${RESOURCE_GROUP}" ]]; then
    printf "Missing a resource group\n\n"
    usage
fi

if [[ -z "${CLUSTER_NAME}" ]]; then
    printf "Missing a cluster name\n\n"
    usage
fi

CLUSTER_RESOURCE_GROUP="$(az aks show --subscription ${SUBSCRIPTION} --resource-group ${RESOURCE_GROUP} --name ${CLUSTER_NAME} --query nodeResourceGroup -o tsv)"
# running in wsl with windows az cli returns CRLF instead of just LF, removing CR from string if it exists
CLUSTER_RESOURCE_GROUP=${CLUSTER_RESOURCE_GROUP%$'\r'}
echo "Auto-discovered AKS RG for ${CLUSTER_NAME} is \"${CLUSTER_RESOURCE_GROUP}\""

echo
az vmss list \
    --subscription ${SUBSCRIPTION} \
    --resource-group ${CLUSTER_RESOURCE_GROUP} \
    -o table
echo
read -p "Enter the name of the set you want to access: " SCALE_SET_NAME
echo "${SCALE_SET_NAME}"

if [[ ${USE_YUBI_KEY} != "0" ]]; then
    if gpg --export-ssh-key ${USER} >/dev/null 2>&1; then
        SSH_KEY=$(gpg --export-ssh-key ${USER})
    else
        gpg --list-keys
        read -p "Enter unique identifier for gpg, list is above: " SSH_USER
        SSH_KEY=$(gpg --export-ssh-key ${SSH_USER})
    fi
elif [[ -f ${HOME}/.ssh/id_rsa.pub ]]; then
    SSH_KEY=$(cat ${HOME}/.ssh/id_rsa.pub)

elif [[ -f ${HOME}/.ssh/id_ed25519.pub ]]; then
    SSH_KEY=$(cat ${HOME}/.ssh/id_ed25519.pub)

fi

if [[ -z ${SSH_KEY} ]]; then
    echo "Unable to find an ssh key to use, exiting..."
    exit 1
fi

az vmss extension set  \
    --subscription ${SUBSCRIPTION} \
    --resource-group $CLUSTER_RESOURCE_GROUP \
    --vmss-name $SCALE_SET_NAME \
    --name VMAccessForLinux \
    --publisher Microsoft.OSTCExtensions \
    --version 1.4 \
    --protected-settings "{\"username\":\"azureuser\", \"ssh_key\":\"${SSH_KEY}\"}" > az_vmss_ext.log
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

kubectl get nodes -o wide | grep ${SCALE_SET_NAME}

echo "To SSH to a node, use it's IP address and the command"
echo " ssh azureuser@[Node IP]"

#echo "Once inside the debian container, install ssh by running:"
#echo "apt-get update && apt-get install openssh-client -y"
#kubectl run -it --rm aks-ssh --image=debian