#!/bin/bash
set -e
set -o pipefail

# Add user to k8s using service account, no RBAC (must create RBAC after this script)
if [[ -z "$1" ]]; then
 echo "usage: $0 <service_account_name>"
 exit 1
fi

WORKSHOP_NAME=$1
SERVICE_ACCOUNT_NAME="sa-$WORKSHOP_NAME"
CLUSTER_ROLE_BINDING="crb-$WORKSHOP_NAME"
NAMESPACE="default"
TARGET_FOLDER="/ytt/generated/kubeconf/$WORKSHOP_NAME"
KUBECFG_FILE_NAME="$TARGET_FOLDER/kubeconf"
CLUSTER_ID=""
ADMIN_CONFIG_FILE="/tmp/admin_kube_conf"
PUBLIC_SUBNET_ID="subnet-0b7fe3813dfe81999"
CLUSTER_KEY="kubernetes.io/cluster"

get_cluster_access(){
    echo -e "\\nGetting cluster access fcarta-${WORKSHOP_NAME}"
    tmc cluster auth admin-kubeconfig get -m aws-hosted -p pa-fcarta fcarta-${WORKSHOP_NAME} > $ADMIN_CONFIG_FILE
}

delete_rbac() {
    echo -e -n "\\nDeleting RBAC permissions..."
    # sed -e "s|my_account|${SERVICE_ACCOUNT_NAME}|g" -e "s|my_namespace|${NAMESPACE}|g" \
    # permissions-template.yaml > permissions_${SERVICE_ACCOUNT_NAME}.yaml     
    kubectl --kubeconfig=${ADMIN_CONFIG_FILE} delete -f generated/clusterRoleBinding/${CLUSTER_ROLE_BINDING}.yaml
    printf "done"
}

delete_service_account() {
    echo -e "\\nDeleting a service account in ${NAMESPACE} namespace: ${SERVICE_ACCOUNT_NAME}"
    kubectl --kubeconfig=${ADMIN_CONFIG_FILE} delete sa "${SERVICE_ACCOUNT_NAME}" --namespace "${NAMESPACE}"
}


get_cluster_id() {
    echo -e "\\nGet cluster id fcarta-${WORKSHOP_NAME}"
    CLUSTER_ID=$(tmc cluster get -m aws-hosted -p pa-fcarta fcarta-${WORKSHOP_NAME} -o json | jq '.meta.uid' | sed -e 's/^"//' -e 's/"$//' | cut -c 3- | sed -e 's/\(.*\)/\L\1/')
}

delete_kube_config() {
    echo -e "\\nDeleting kube_conf files at ${TARGET_FOLDER}"
    rm -rf ${TARGET_FOLDER}
}

delete_cloud_tags() {
    echo -e "\\nDeleting cloud tags for cluster ${CLUSTER_ID}"
    aws ec2 delete-tags --resources ${PUBLIC_SUBNET_ID} --tags Key=${CLUSTER_KEY}/${CLUSTER_ID}
}

get_cluster_access
delete_rbac || true
delete_service_account || true
get_cluster_id 
delete_kube_config || true
delete_cloud_tags || true

echo "CLUSTER_ID=${CLUSTER_ID}"
echo -e "\\nAll done! Test with:"
echo "KUBECONFIG=${ADMIN_CONFIG_FILE} kubectl get sa"
KUBECONFIG=${ADMIN_CONFIG_FILE} kubectl get sa
