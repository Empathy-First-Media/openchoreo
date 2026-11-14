# Private OpenChoreo pilot

These are native Helm overrides for **OpenChoreo 1.3.3** on an existing,
explicitly selected Kubernetes cluster. They prepare a control plane and a data
plane agent. They do not provision cloud infrastructure or publish applications.

The files are intentionally generic. Account IDs, tenant identities, OIDC URLs,
application domains, credentials, certificate material, and authorization
bindings belong in the existing private deployment system.

## Scope and installation contract

| Item | Pilot behavior |
| --- | --- |
| Release | Published upstream charts pinned to `1.3.3` |
| Control plane | API, controllers, and internal cluster gateway |
| Data plane | Agent with TLS and its own generated client certificate |
| Identity | Existing OIDC provider; authentication and authorization enabled |
| Authorization | No example entitlement mappings; provide reviewed mappings privately |
| Portal | Bundled Backstage and its event forwarder disabled |
| Build system | External CI; no workflow-plane installation |
| Application ingress | Disabled until its gateway, domains, and certificates are reviewed |
| MCP and remote development | Disabled until scoped authorization and audit behavior are verified |
| Observability | Existing monitoring during bootstrap; supported module integration is a later stage |

Use the upstream installation namespaces `openchoreo-control-plane` and
`openchoreo-data-plane` for this profile. The upstream default internal service
URLs and certificate names refer to them. These are software installation
namespaces, not customer or tenant identifiers. Changing them requires updating
all corresponding internal URLs and certificate SANs together.

OpenChoreo installs cluster-scoped CRDs, RBAC, and webhook configuration. A new
namespace alone does not isolate a second installation. Inspect the cluster and
its current owners before installing; use a separate pilot cluster if an existing
OpenChoreo installation would conflict.

## 1. Read-only preflight

Run from the repository root using the project toolchain. Supply the exact
already-authorized context and a private values file outside this public checkout.
The private file is a real configuration input, not a template to commit here.

```bash
: "${KUBE_CONTEXT:?Set the approved existing Kubernetes context}"
: "${OPENCHOREO_PRIVATE_VALUES:?Set an absolute path to reviewed private Helm values}"
test -r "$OPENCHOREO_PRIVATE_VALUES"
kubectl --context "$KUBE_CONTEXT" cluster-info
kubectl --context "$KUBE_CONTEXT" version
kubectl --context "$KUBE_CONTEXT" get nodes
kubectl --context "$KUBE_CONTEXT" get storageclass
helm list --all-namespaces --kube-context "$KUBE_CONTEXT"
kubectl --context "$KUBE_CONTEXT" get crd
kubectl --context "$KUBE_CONTEXT" auth can-i create customresourcedefinitions.apiextensions.k8s.io
```

Require Kubernetes 1.34 or later and a working cert-manager installation. Reuse
the existing cert-manager owner and compatible version. The upstream v1.3.3
installer pins cert-manager v1.19.4; do not use that as a reason to overwrite a
separately managed cluster prerequisite. Gateway API/kgateway and the secret-store
integration must be installed and validated when the corresponding workload
features are enabled. They are not provisioned by these overrides.

Choose a provider-supported Kubernetes release rather than treating the minimum
as the preferred version. The v1.3.3 chart's authorization-bootstrap hook defaults
to `registry.k8s.io/kubectl:v1.36.0`. Check that image as well as the workstation CLI
against the actual API server: Kubernetes
[supports kubectl within one minor version](https://kubernetes.io/releases/version-skew-policy/#kubectl).
Override the native bootstrap image field privately if needed; a 1.34 API server
and the default 1.36 hook client exceed that supported skew.

Confirm cloud quota, operating budget, region, storage, backup ownership, and
network reachability separately. This profile does not select a billable provider.

## 2. Supply identity and authorization privately

The native chart rejects its default `.invalid` OIDC issuer. Keep that guard.
Populate these **existing chart fields** from the authoritative identity and
deployment records:

| Chart field | Required private input |
| --- | --- |
| `security.oidc.issuer` | Exact issuer expected in tokens |
| `security.oidc.jwksUrl` | Reachable TLS-verified JWKS endpoint |
| `security.oidc.authorizationUrl` | Provider authorization endpoint |
| `security.oidc.tokenUrl` | Provider token endpoint |
| `security.oidc.wellKnownEndpoint` | Provider discovery URL when applicable |
| `security.jwt.audience` | Intended platform API audience |
| `security.oidc.externalClients` | Approved client registrations and scopes |
| `openchoreoApi.config.server.publicUrl` | Actual API URL clients will use, including private routing during the pilot |
| `openchoreoApi.config.security.subjects` | Provider claim mapping, reviewed against actual token claims |
| `openchoreoApi.config.security.authorization.bootstrap.mappings` | Approved administrator and narrowly scoped automation entitlements |
| `openchoreoApi.config.security.authorization.bootstrap.image` | Reviewed kubectl image compatible with the selected API server |

The base replaces all upstream example mappings with an empty list. The chart
still defines its built-in role vocabulary; no principal receives those roles
from this profile alone. Provide approved bindings before expecting authenticated
API operations to succeed. Never import a sample MCP administrator or broaden a
client entitlement merely to get a pilot working.

Use the chart's native bootstrap mapping structure and the existing private
GitOps repository. Do not create a second identity registry or copy client secrets
into values committed to this fork. Kubernetes administrator access remains a
separate control path during bootstrap.

## 3. Render and review the pinned release

Use published chart packages. The chart files in the source tag retain
`appVersion: latest-dev` until release packaging rewrites them; installing directly
from the repository can therefore select development images despite a source tag.

```bash
helm show chart oci://ghcr.io/openchoreo/helm-charts/openchoreo-control-plane --version 1.3.3
helm show chart oci://ghcr.io/openchoreo/helm-charts/openchoreo-data-plane --version 1.3.3

umask 077
OPENCHOREO_RENDER_DIR="$(mktemp -d)"
helm template openchoreo-control-plane \
  oci://ghcr.io/openchoreo/helm-charts/openchoreo-control-plane \
  --version 1.3.3 --namespace openchoreo-control-plane --include-crds \
  --values deploy/aiagencypro/values-control-plane.yaml \
  --values "$OPENCHOREO_PRIVATE_VALUES" \
  > "$OPENCHOREO_RENDER_DIR/control-plane.yaml"
helm template openchoreo-data-plane \
  oci://ghcr.io/openchoreo/helm-charts/openchoreo-data-plane \
  --version 1.3.3 --namespace openchoreo-data-plane --include-crds \
  --values deploy/aiagencypro/values-data-plane.yaml \
  > "$OPENCHOREO_RENDER_DIR/data-plane.yaml"
```

Review the rendered objects, image tags/digests, hook jobs, cluster permissions,
certificate lifetimes, and resource requests. Confirm there is no bundled portal,
public `Gateway`, `HTTPRoute`, `TLSRoute`, `Ingress`, `LoadBalancer`, or `NodePort`
service. Confirm authentication, authorization, and cluster-gateway internal mTLS
are enabled. Private overrides can change these settings, so inspect the merged
output rather than assuming the base file determines the final behavior.

Keep rendered private configuration out of public CI artifacts and logs. An
offline template/schema check cannot prove cluster admission, network policy,
identity-provider interoperability, or runtime health.

## 4. Install the two chart releases

The following commands mutate only the selected existing cluster. Use them after
the reviewed prerequisites and private inputs are ready, or express the equivalent
native Helm releases in the existing GitOps system. Do not run a manual Helm owner
and a GitOps owner against the same release concurrently.

```bash
helm upgrade --install openchoreo-control-plane \
  oci://ghcr.io/openchoreo/helm-charts/openchoreo-control-plane \
  --version 1.3.3 --kube-context "$KUBE_CONTEXT" \
  --namespace openchoreo-control-plane --create-namespace \
  --values deploy/aiagencypro/values-control-plane.yaml \
  --values "$OPENCHOREO_PRIVATE_VALUES" \
  --atomic --wait --timeout 15m

kubectl --context "$KUBE_CONTEXT" wait \
  --namespace openchoreo-control-plane \
  --for=condition=Ready certificate/cluster-gateway-ca --timeout=180s

kubectl --context "$KUBE_CONTEXT" create namespace openchoreo-data-plane \
  --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f -

# Copy only the public trust anchor; never copy the CA private key.
set -o pipefail
kubectl --context "$KUBE_CONTEXT" get secret cluster-gateway-ca \
  --namespace openchoreo-control-plane -o jsonpath='{.data.ca\.crt}' | \
  base64 --decode | \
  kubectl --context "$KUBE_CONTEXT" create configmap cluster-gateway-ca \
    --namespace openchoreo-data-plane --from-file=ca.crt=/dev/stdin \
    --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f -

helm upgrade --install openchoreo-data-plane \
  oci://ghcr.io/openchoreo/helm-charts/openchoreo-data-plane \
  --version 1.3.3 --kube-context "$KUBE_CONTEXT" \
  --namespace openchoreo-data-plane \
  --values deploy/aiagencypro/values-data-plane.yaml \
  --atomic --wait --timeout 15m
```

The public-CA ConfigMap must be refreshed through the same owner if the gateway CA
rotates. Establish certificate renewal and trust-anchor rotation before production.
Ordinary leaf-certificate renewal and CA replacement are different operations.

`--atomic` handles Helm release failure; it is not a database backup, an undo for
every hook side effect, or a CRD downgrade strategy. Before upgrading an existing
installation, inspect the release's migration instructions and test restore.

## 5. Enroll the data plane and deploy one private component

Installing an agent does not register or authorize it. Use the official
[v1.3.3 data-plane registration procedure](https://github.com/openchoreo/openchoreo/blob/v1.3.3/install/k3d/single-cluster/README.md#register-data-plane)
to register the agent certificate and plane identity in the **existing private
platform configuration**. Adapt the native `DataPlane`/`ClusterDataPlane` resource
through its current API schema; omit the tutorial's demo ingress and secret-store
references when those integrations have not been installed. This public profile
does not duplicate the tutorial's platform catalog.

Reuse approved component types, project identities, environments, and release
bindings. The first deployment should consume an externally built immutable image
digest and have no public endpoint. Record its owning tenant/project using the
existing catalog contract. Run the following acceptance sequence before enabling
more services:

1. Verify expected identity claims, audience rejection, approved access, and denied
   cross-project/cross-tenant access.
2. Verify the cluster agent connects with its registered certificate and the
   controller can reconcile a workload into the intended namespace.
3. Deploy a known image digest, confirm workload readiness, and exercise a useful
   application response over a private connection.
4. Promote the same image digest through the chosen release workflow; verify the
   running image and configuration after reconciliation.
5. Revert the release binding/configuration commit and verify application recovery.
6. Verify logs, deployment events, restart behavior, resource limits, and the
   certificate renewal/backup runbooks.

Read-back commands for the installation itself:

```bash
helm status openchoreo-control-plane --kube-context "$KUBE_CONTEXT" --namespace openchoreo-control-plane
helm status openchoreo-data-plane --kube-context "$KUBE_CONTEXT" --namespace openchoreo-data-plane
kubectl --context "$KUBE_CONTEXT" get deployments,services,certificates --namespace openchoreo-control-plane
kubectl --context "$KUBE_CONTEXT" get deployments,services,certificates --namespace openchoreo-data-plane
kubectl --context "$KUBE_CONTEXT" logs --namespace openchoreo-data-plane deployment/cluster-agent-dataplane --tail=50
```

Review logs privately. A Helm success or a running pod is not proof that the plane
is registered, the application works, or authorization boundaries hold.

## 6. Adopt existing GitOps and portal integration

Use the existing reconciliation engine. If Flux is already the owner, its native
Helm tooling can represent these pinned OCI charts and supplied values. Follow the
[official Flux Helm release documentation](https://fluxcd.io/flux/components/helm/helmreleases/)
and [OpenChoreo GitOps guide](https://openchoreo.dev/docs/platform-engineer-guide/gitops/).
Keep private values, RBAC bindings, and environment resources in the existing
private desired-state repository. Do not install another controller merely to
match this document.

Integrate the maintained OpenChoreo Backstage plugins into the existing portal in
an isolated branch after checking its Backstage version and authentication model.
Only enable a separate upstream portal for a deliberate isolated comparison with
its own database and access boundary. Configure catalog event delivery only after
the receiving integration and its authentication are verified.

Enable Cloudflare ingress, observability modules, audit export, and selected MCP
toolsets in subsequent reviewed environment changes. Keep the internal mTLS
gateway private. See [hosting decisions](../../docs/aiagencypro/hosting.md).

## Source contract

These fields were inspected against the upstream
[control-plane values](https://github.com/openchoreo/openchoreo/blob/v1.3.3/install/helm/openchoreo-control-plane/values.yaml),
[data-plane values](https://github.com/openchoreo/openchoreo/blob/v1.3.3/install/helm/openchoreo-data-plane/values.yaml),
their `values.schema.json` files, and the
[v1.3.3 installer](https://github.com/openchoreo/openchoreo/blob/v1.3.3/install/k3d/k3d-install.sh).
Revalidate chart schemas, rendered resources, security advisories, and provider
capabilities with every release change. No live cluster is implied by these files.
