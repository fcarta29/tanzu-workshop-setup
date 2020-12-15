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
PROJECT_FOLDER="/ytt"
TARGET_FOLDER="${PROJECT_FOLDER}/generated/kubeconf/$WORKSHOP_NAME"
CLUSTER_ROLE_BINDING_FOLDER="${PROJECT_FOLDER}/generated/clusterRoleBinding"
KUBECFG_FILE_NAME="$TARGET_FOLDER/kubeconf"
CLUSTER_ID=""
ADMIN_CONFIG_FILE="/tmp/admin_kube_conf"
PUBLIC_SUBNET_ID="subnet-0b7fe3813dfe81999"
CLUSTER_KEY="kubernetes.io/cluster"


create_target_folder() {
    echo -n "Creating target directory to hold files in ${TARGET_FOLDER}..."
    mkdir -p "${TARGET_FOLDER}"
    printf "done"
}

get_cluster_access(){
    echo -e "\\nGetting cluster access fcarta-${WORKSHOP_NAME}"
    tmc cluster auth admin-kubeconfig get -m aws-hosted -p pa-fcarta fcarta-${WORKSHOP_NAME} > $ADMIN_CONFIG_FILE
}

create_service_account() {
    echo -e "\\nCreating a service account in ${NAMESPACE} namespace: ${SERVICE_ACCOUNT_NAME}"
    kubectl --kubeconfig=${ADMIN_CONFIG_FILE} create sa "${SERVICE_ACCOUNT_NAME}" --namespace "${NAMESPACE}"
}

get_secret_name_from_service_account() {
    echo -e "\\nGetting secret of service account ${SERVICE_ACCOUNT_NAME} on ${NAMESPACE}"
    SECRET_NAME=$(kubectl --kubeconfig=${ADMIN_CONFIG_FILE} get sa "${SERVICE_ACCOUNT_NAME}" --namespace="${NAMESPACE}" -o json | jq -r .secrets[].name)
    echo "Secret name: ${SECRET_NAME}"
}

extract_ca_crt_from_secret() {
    echo -e -n "\\nExtracting ca.crt from secret..."
    kubectl --kubeconfig=${ADMIN_CONFIG_FILE} get secret --namespace "${NAMESPACE}" "${SECRET_NAME}" -o json | jq \
    -r '.data["ca.crt"]' | base64 -d > "${TARGET_FOLDER}/ca.crt"
    printf "done"
}

get_user_token_from_secret() {
    echo -e -n "\\nGetting user token from secret..."
    USER_TOKEN=$(kubectl --kubeconfig=${ADMIN_CONFIG_FILE} get secret --namespace "${NAMESPACE}" "${SECRET_NAME}" -o json | jq -r '.data["token"]' | base64 -d)
    printf "done"
}

apply_rbac() {
    echo -e -n "\\nApplying RBAC permissions..."
    # sed -e "s|my_account|${SERVICE_ACCOUNT_NAME}|g" -e "s|my_namespace|${NAMESPACE}|g" \
    # permissions-template.yaml > permissions_${SERVICE_ACCOUNT_NAME}.yaml     
    kubectl --kubeconfig=${ADMIN_CONFIG_FILE} apply -f ${CLUSTER_ROLE_BINDING_FOLDER}/${CLUSTER_ROLE_BINDING}.yaml
    printf "done"
}

get_cluster_id() {
    CLUSTER_ID=$(tmc cluster get -m aws-hosted -p pa-fcarta fcarta-${WORKSHOP_NAME} -o json | jq '.meta.uid' | sed -e 's/^"//' -e 's/"$//' | cut -c 3- | sed -e 's/\(.*\)/\L\1/')
}

set_kube_config_values() {
    context=$(kubectl --kubeconfig=${ADMIN_CONFIG_FILE} config current-context)
    echo -e "\\nSetting current context to: ${context}"

    CLUSTER_NAME=$(kubectl --kubeconfig=${ADMIN_CONFIG_FILE} config get-contexts "${context}" | awk '{print $3}' | tail -n 1)
    echo "Cluster name: ${CLUSTER_NAME}"

    ENDPOINT=$(kubectl --kubeconfig=${ADMIN_CONFIG_FILE} config view \
    -o jsonpath="{.clusters[?(@.name == \"${CLUSTER_NAME}\")].cluster.server}")
    echo "Endpoint: ${ENDPOINT}"

    # Set up the config
    echo -e "\\nPreparing k8s-${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-conf"
    echo -n "Setting a cluster entry in kubeconfig..."
    kubectl --kubeconfig=${ADMIN_CONFIG_FILE} config set-cluster "${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --server="${ENDPOINT}" \
    --certificate-authority="${TARGET_FOLDER}/ca.crt" \
    --embed-certs=true

    echo -n "Setting token credentials entry in kubeconfig..."
    kubectl --kubeconfig=${ADMIN_CONFIG_FILE} config set-credentials \
    "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --token="${USER_TOKEN}"

    echo -n "Setting a context entry in kubeconfig..."
    kubectl --kubeconfig=${ADMIN_CONFIG_FILE} config set-context \
    "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --cluster="${CLUSTER_NAME}" \
    --user="${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --namespace="${NAMESPACE}"

    echo -n "Setting the current-context in the kubeconfig file..."
    kubectl --kubeconfig=${ADMIN_CONFIG_FILE} config use-context "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}"
}

create_cloud_tags() {
    echo -e "\\nCreate cloud tags for cluster ${CLUSTER_ID}"
    aws ec2 create-tags --resources ${PUBLIC_SUBNET_ID} --tags Key=${CLUSTER_KEY}/${CLUSTER_ID},Value=shared
}

create_target_folder
get_cluster_access
create_service_account
get_secret_name_from_service_account
extract_ca_crt_from_secret
get_user_token_from_secret
apply_rbac
set_kube_config_values
get_cluster_id
create_cloud_tags

echo "CLUSTER_ID=${CLUSTER_ID}"
echo -e "\\nAll done! Test with:"
echo "KUBECONFIG=${KUBECFG_FILE_NAME} kubectl get pods"
KUBECONFIG=${KUBECFG_FILE_NAME} kubectl get pods
