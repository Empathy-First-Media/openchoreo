#!/usr/bin/env bash
# Private, single-host development bootstrap. Hand ongoing reconciliation to the
# existing GitOps owner before using it; do not run two configuration owners.
set -euo pipefail
umask 077

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"; }
port() { [[ $1 =~ ^[1-9][0-9]{3,4}$ ]] && (( 10#$1 >= 1024 && 10#$1 <= 65535 )); }

action=${1:-preflight}
[[ $# -le 1 ]] || fail 'Use exactly one action: preflight, create, install, status, forward, stop, start.'
case "$action" in
  preflight|create|install|status|forward|stop|start) ;;
  -h|--help|help)
    printf '%s\n' 'Usage: mise run local -- preflight|create|install|status|forward|stop|start' \
      'Read docs/aiagencypro/local-tailnet.md for required, private operator inputs.'
    exit 0 ;;
  *) fail "Unknown action: $action" ;;
esac

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
for tool in docker k3d kubectl helm jq openssl; do need "$tool"; done
# Native k3d gives K3D_* environment settings precedence over its config file.
# Refuse inherited overrides, including extra published ports/volumes or changes
# to kubeconfig behavior. Set the known Colima DNS adaptation below ourselves.
while IFS= read -r exported_name; do
  case "$exported_name" in K3D_*) fail "Remove inherited $exported_name from this invocation; this profile owns k3d configuration." ;; esac
done < <(compgen -e)
: "${DOCKER_CONTEXT:?Select the existing local Docker context}"
: "${OPENCHOREO_CLUSTER_NAME:?Select a unique disposable cluster name}"
: "${OPENCHOREO_LOCAL_STATE_DIR:?Select a new absolute private state directory outside this checkout}"
: "${OPENCHOREO_KUBE_PORT:?Select a free loopback Kubernetes API port}"
: "${OPENCHOREO_K3S_IMAGE:?Run through the project mise local task}"
: "${OPENCHOREO_VERSION:?Run through the project mise local task}"
: "${OPENCHOREO_CHART_REPOSITORY:?Run through the project mise local task}"
: "${OPENCHOREO_CERT_MANAGER_VERSION:?Run through the project mise local task}"

[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || fail 'This profile requires the local Apple Silicon Mac; use the general pilot guide on other hosts.'
[[ $OPENCHOREO_CLUSTER_NAME =~ ^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$ ]] || fail 'Cluster name must be 1–32 lowercase letters, digits or hyphens, with alphanumeric ends.'
port "$OPENCHOREO_KUBE_PORT" || fail 'Kubernetes API port must be an integer from 1024 to 65535.'
[[ $OPENCHOREO_LOCAL_STATE_DIR == /* && $OPENCHOREO_LOCAL_STATE_DIR != */ ]] || fail 'State directory must be an absolute path without a trailing slash.'
state_parent=$(cd "$(dirname "$OPENCHOREO_LOCAL_STATE_DIR")" && pwd -P)
[[ $OPENCHOREO_LOCAL_STATE_DIR == "$state_parent/$(basename "$OPENCHOREO_LOCAL_STATE_DIR")" ]] || fail 'State path must be canonical, without redirected parent directories.'
case "$OPENCHOREO_LOCAL_STATE_DIR" in "$ROOT"|"$ROOT"/*) fail 'Keep private state outside the Git checkout.' ;; esac
[[ ! -L $OPENCHOREO_LOCAL_STATE_DIR ]] || fail 'State directory must not be a symbolic link.'

docker_local() { docker --context "$DOCKER_CONTEXT" "$@"; }
endpoint=$(docker_local context inspect "$DOCKER_CONTEXT" --format '{{.Endpoints.docker.Host}}')
case "$endpoint" in unix:///*) ;; *) fail 'Only a local Unix-socket Docker context is supported; remote SSH/TCP engines are refused.' ;; esac
# k3d uses Docker's native client. Bind its process to the same inspected endpoint;
# do not switch the user's global context or mount a different default socket.
export DOCKER_HOST="$endpoint"
info=$(docker_local info --format '{{json .}}')
jq -e '(.Architecture == "arm64" or .Architecture == "aarch64") and .OSType == "linux"' <<<"$info" >/dev/null || fail 'The selected Docker engine must run Linux ARM64 containers.'
engine_major=$(jq -er '.ServerVersion | split(".")[0] | tonumber' <<<"$info")
(( engine_major >= 28 )) || fail 'Require Docker Engine 28+ for the documented localhost-published-port isolation fix.'
case "$action" in
  preflight|create|install|start)
    jq -e '.NCPU >= 2 and .MemTotal >= 4000000000' <<<"$info" >/dev/null || fail 'Allocate at least 2 CPUs and 4 GB RAM to the Docker VM.' ;;
esac
daemon_id=$(jq -er '.ID | select(length > 0)' <<<"$info")
if [[ $(jq -r '.Name' <<<"$info") == *colima* ]]; then export K3D_FIX_DNS=0; fi
context="k3d-$OPENCHOREO_CLUSTER_NAME"
kubeconfig="$OPENCHOREO_LOCAL_STATE_DIR/kubeconfig.yaml"
receipt="$OPENCHOREO_LOCAL_STATE_DIR/cluster.json"
node="k3d-$OPENCHOREO_CLUSTER_NAME-server-0"
kubectl_local() { kubectl --kubeconfig "$kubeconfig" --context "$context" "$@"; }
helm_local() { helm --kubeconfig "$kubeconfig" --kube-context "$context" "$@"; }

check_owned_cluster() {
  [[ -d $OPENCHOREO_LOCAL_STATE_DIR && -O $OPENCHOREO_LOCAL_STATE_DIR ]] || fail 'Owned state directory is missing.'
  [[ -f $receipt && ! -L $receipt && -f $kubeconfig && ! -L $kubeconfig ]] || fail 'Owned receipt and kubeconfig must be ordinary files, not links.'
  local node_id server
  node_id=$(docker_local inspect "$node" --format '{{.Id}}')
  jq -e --arg cluster "$OPENCHOREO_CLUSTER_NAME" --arg docker_context "$DOCKER_CONTEXT" \
    --arg endpoint "$endpoint" --arg daemon "$daemon_id" --arg node "$node_id" \
    --arg version "$OPENCHOREO_VERSION" --arg image "$OPENCHOREO_K3S_IMAGE" \
    --arg cert_manager "$OPENCHOREO_CERT_MANAGER_VERSION" \
    '.cluster == $cluster and .docker_context == $docker_context and .endpoint == $endpoint and .daemon == $daemon and .node == $node and .version == $version and .image == $image and .cert_manager == $cert_manager' \
    "$receipt" >/dev/null || fail 'Cluster ownership, Docker engine or pinned release changed; inspect manually before continuing.'
  server=$(kubectl_local config view --minify -o jsonpath='{.clusters[0].cluster.server}')
  [[ $server == "https://127.0.0.1:$OPENCHOREO_KUBE_PORT" ]] || fail 'Private kubeconfig does not point to the selected loopback endpoint.'
}

case "$action" in
  preflight)
    jq '{ServerVersion, Architecture, OSType, NCPU, MemTotal}' <<<"$info"
    printf 'Selected local Docker context: %s\nPrivate cluster: %s\nKubernetes API: https://127.0.0.1:%s\n' \
      "$DOCKER_CONTEXT" "$OPENCHOREO_CLUSTER_NAME" "$OPENCHOREO_KUBE_PORT"
    k3d cluster list
    df -h "$state_parent"
    docker_local system df
    if [[ -e $OPENCHOREO_LOCAL_STATE_DIR ]]; then
      check_owned_cluster
      printf '%s\n' 'Existing cluster ownership verified; no changes made.'
    else
      printf '%s\n' 'No state directory exists; create is a separate action. No changes made.'
    fi
    ;;
  create)
    [[ ! -e $OPENCHOREO_LOCAL_STATE_DIR ]] || fail 'State destination already exists; it will not be overwritten.'
    clusters=$(k3d cluster list --output json)
    jq -e --arg name "$OPENCHOREO_CLUSTER_NAME" 'all(.[]; .name != $name)' <<<"$clusters" >/dev/null || fail 'A cluster with this name already exists; it will not be adopted.'
    mkdir -m 700 "$OPENCHOREO_LOCAL_STATE_DIR"
    # If creation is interrupted, preserve this private directory for inspection.
    # Never delete an existing cluster or unrelated kubeconfig during recovery.
    k3d cluster create "$OPENCHOREO_CLUSTER_NAME" --config "$ROOT/deploy/aiagencypro/local/k3d.yaml" \
      --image "$OPENCHOREO_K3S_IMAGE" --api-port "127.0.0.1:$OPENCHOREO_KUBE_PORT" \
      --kubeconfig-update-default=false --kubeconfig-switch-context=false
    k3d kubeconfig get "$OPENCHOREO_CLUSTER_NAME" > "$kubeconfig"
    node_id=$(docker_local inspect "$node" --format '{{.Id}}')
    jq -n --arg cluster "$OPENCHOREO_CLUSTER_NAME" --arg docker_context "$DOCKER_CONTEXT" \
      --arg endpoint "$endpoint" --arg daemon "$daemon_id" --arg node "$node_id" \
      --arg version "$OPENCHOREO_VERSION" --arg image "$OPENCHOREO_K3S_IMAGE" \
      --arg cert_manager "$OPENCHOREO_CERT_MANAGER_VERSION" \
      '{cluster:$cluster,docker_context:$docker_context,endpoint:$endpoint,daemon:$daemon,node:$node,version:$version,image:$image,cert_manager:$cert_manager}' > "$receipt"
    check_owned_cluster
    kubectl_local wait --for=condition=Ready node --all --timeout=180s
    printf '%s\n' 'Local Kubernetes cluster created. Platform installation is a separate action.'
    ;;
  install)
    check_owned_cluster
    : "${OPENCHOREO_PRIVATE_VALUES:?Select the reviewed external OIDC and RBAC Helm values file}"
    : "${OPENCHOREO_PLANE_ID:?Use the existing private owner’s plane identity; registration must use the same value}"
    [[ $OPENCHOREO_PRIVATE_VALUES == /* && -f $OPENCHOREO_PRIVATE_VALUES && ! -L $OPENCHOREO_PRIVATE_VALUES && -O $OPENCHOREO_PRIVATE_VALUES ]] || fail 'Private values must be an absolute, current-user-owned ordinary file, not a symbolic link.'
    values_parent=$(cd "$(dirname "$OPENCHOREO_PRIVATE_VALUES")" && pwd -P)
    [[ $OPENCHOREO_PRIVATE_VALUES == "$values_parent/$(basename "$OPENCHOREO_PRIVATE_VALUES")" ]] || fail 'Private values path must be canonical, without redirected parent directories.'
    case "$OPENCHOREO_PRIVATE_VALUES" in "$ROOT"/*) fail 'Private identity configuration must remain outside the checkout.' ;; esac
    case $(stat -f '%Lp' "$OPENCHOREO_PRIVATE_VALUES") in 400|600) ;; *) fail 'Private values must already have owner-only mode 400 or 600; the helper does not change operator file permissions.' ;; esac
    [[ $OPENCHOREO_PLANE_ID =~ ^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$ ]] || fail 'Plane ID must satisfy native data-plane registration: 1–63 lowercase letters, digits or hyphens, with alphanumeric ends.'
    cp_chart="$OPENCHOREO_CHART_REPOSITORY/openchoreo-control-plane"
    dp_chart="$OPENCHOREO_CHART_REPOSITORY/openchoreo-data-plane"
    # The private final layer must be reviewed to preserve the base security and
    # scope controls. Helm schema validity is not semantic OIDC/RBAC acceptance.
    cp_values=(--values "$ROOT/deploy/aiagencypro/values-control-plane.yaml" --values "$OPENCHOREO_PRIVATE_VALUES")
    dp_values=(--values "$ROOT/deploy/aiagencypro/values-data-plane.yaml" --set-string "clusterAgent.planeID=$OPENCHOREO_PLANE_ID")
    # Native chart validation happens before cluster mutation. Output may contain
    # private values, so render only into an exclusively created private temp dir.
    validation_dir=$(mktemp -d "$OPENCHOREO_LOCAL_STATE_DIR/render.XXXXXX")
    trap 'rm -rf -- "$validation_dir"' EXIT
    helm template openchoreo-control-plane "$cp_chart" --version "$OPENCHOREO_VERSION" \
      --namespace openchoreo-control-plane "${cp_values[@]}" > "$validation_dir/control-plane.yaml"
    helm template openchoreo-data-plane "$dp_chart" --version "$OPENCHOREO_VERSION" \
      --namespace openchoreo-data-plane "${dp_values[@]}" > "$validation_dir/data-plane.yaml"
    helm_local upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
      --namespace cert-manager --create-namespace --version "$OPENCHOREO_CERT_MANAGER_VERSION" \
      --set crds.enabled=true --wait --timeout 5m
    helm_local upgrade --install openchoreo-control-plane "$cp_chart" --version "$OPENCHOREO_VERSION" \
      --namespace openchoreo-control-plane --create-namespace "${cp_values[@]}" --wait --timeout 10m
    kubectl_local wait -n openchoreo-control-plane --for=condition=Ready certificate/cluster-gateway-ca --timeout=120s
    kubectl_local create namespace openchoreo-data-plane --dry-run=client -o yaml | kubectl_local apply -f -
    # Transfer only the public CA certificate; no private key is exported.
    kubectl_local get secret cluster-gateway-ca -n openchoreo-control-plane -o jsonpath='{.data.ca\.crt}' \
      | openssl base64 -d -A > "$validation_dir/cluster-gateway-ca.crt"
    openssl x509 -in "$validation_dir/cluster-gateway-ca.crt" -noout >/dev/null
    kubectl_local create configmap cluster-gateway-ca -n openchoreo-data-plane \
      --from-file="ca.crt=$validation_dir/cluster-gateway-ca.crt" --dry-run=client -o yaml | kubectl_local apply -f -
    helm_local upgrade --install openchoreo-data-plane "$dp_chart" --version "$OPENCHOREO_VERSION" \
      --namespace openchoreo-data-plane "${dp_values[@]}" --wait --timeout 5m
    printf '%s\n' 'Platform charts installed. The data plane still needs its reviewed native registration.' \
      'Pod readiness is not registration, an application deployment, or successful OIDC/RBAC acceptance.'
    ;;
  status)
    check_owned_cluster
    kubectl_local get nodes
    helm_local list --all-namespaces
    kubectl_local get deployments,pods,services,certificates -n openchoreo-control-plane
    kubectl_local get deployments,pods,services,certificates -n openchoreo-data-plane
    kubectl_local get clusterdataplanes
    ;;
  forward)
    check_owned_cluster
    : "${OPENCHOREO_API_LOCAL_PORT:?Select the owned free loopback API-forward port}"
    port "$OPENCHOREO_API_LOCAL_PORT" || fail 'API-forward port must be an integer from 1024 to 65535.'
    service_port=$(kubectl_local get service openchoreo-api -n openchoreo-control-plane -o jsonpath='{.spec.ports[?(@.name=="http")].port}')
    [[ $service_port =~ ^[0-9]+$ ]] || fail 'Expected native API HTTP service port was not found.'
    exec kubectl --kubeconfig "$kubeconfig" --context "$context" -n openchoreo-control-plane \
      port-forward --address 127.0.0.1 service/openchoreo-api "$OPENCHOREO_API_LOCAL_PORT:$service_port"
    ;;
  stop|start)
    check_owned_cluster
    k3d cluster "$action" "$OPENCHOREO_CLUSTER_NAME"
    ;;
esac
