# Private local pilot on Apple Silicon

Use native k3d and the published OpenChoreo charts on an explicitly selected
local Docker engine. The initial profile installs the control plane and data-plane
agent, keeps application ingress off, and reuses an external identity provider.
An existing portal can integrate with the API after identity and authorization
are proven. This is a disposable development environment, not a highly available
service or an unattended deployment target.

The operator is `mise run local -- ACTION`. With no action it performs a read-only
preflight. Creation and installation are separate actions. It never switches the
default Docker context, writes the default kubeconfig, configures Tailscale, or
adopts a cluster that already has the chosen name. Its local receipt binds later
actions to the created node, Docker daemon, context, image and platform version.
Use it for initial bootstrap and deliberate development changes. Once an existing
GitOps owner manages the cluster, stop using imperative installation as a second
reconciler.

## 1. Check the Mac and choose the smallest useful scope

The official quickstart minimum is **2 CPUs and 4 GB RAM allocated to Docker**;
the guide recommends **4 CPUs and 8 GB RAM** when adding the workflow plane. The
guided all-plane installation also uses 4 CPUs and 8 GB. These are Docker VM
allocations, not total Mac memory. The private profile has fewer services, but no
lower minimum has been established by runtime measurement. Start with 4 CPUs and
8 GB if the host has sufficient spare memory; an 8 GB Mac should begin with the
minimal profile and carefully observe memory pressure. Disk requirements vary
with images, build caches and retained telemetry. Reserving **20–30 GB of free
Docker storage** for this small pilot is planning headroom, not an upstream
minimum or a guarantee. Check both the VM disk limit and its host volume.

Use the already installed Docker provider. Do not launch a second VM just to run
this profile. Upstream recommends Colima with VZ/Rosetta for Apple Silicon
buildpack compatibility; the initial profile does not run buildpacks. Native
k3d does not need Docker Desktop's optional host-network feature or a helper
container that mounts `/var/run/docker.sock`. Docker Engine **28 or later** is
required here because Docker documents a same-L2-network exposure issue for
localhost-published ports in earlier releases. Reusing a Docker context does not
prove its daemon is local: preflight rejects SSH/TCP endpoints and requires a
Linux ARM64 engine reached through a local Unix socket.

| Component | Initial profile | When to add more |
| --- | --- | --- |
| K3s, cert-manager, CP API/controllers/cluster gateway | Required | Native prerequisite and internal TLS owners |
| Data-plane agent and its certificates | Required | Must still register the plane before it can receive work |
| Gateway API, kgateway | Omitted | Add a reviewed implementation before using endpoint-bearing component types or Gateway routes |
| External Secrets Operator and a secret backend | Omitted | Add the existing provider integration before using `SecretReference`/`ExternalSecret` consumers |
| Bundled Backstage and demo ThunderID | Disabled/omitted | Integrate the existing portal and identity provider; no demo users are exposed |
| Workflow plane, Argo, build registry | Omitted | Needed only for OpenChoreo's in-cluster source builds; existing CI can publish immutable images |
| Observability plane and modules | Omitted | Add the selected logs/metrics/traces modules after measuring capacity; basic `kubectl logs` remains available |
| MCP, remote-development router, public ingress | Disabled | Require their own reviewed authentication, routing and acceptance |

The rendered base charts contain core Kubernetes/OpenChoreo resources and
cert-manager `Certificate`/`Issuer` resources. The control-plane chart installs
its own OpenChoreo CRDs. Its registered controllers initially watch core and
OpenChoreo types; registering an external type in the Go scheme alone does not
install a controller or require that CRD. Gateway and external-secret resources
are not emitted by this profile. This establishes the bootstrap dependency
boundary; it does not prove that arbitrary component templates will work without
their own Gateway, secret, policy or storage prerequisites.

Sources: [OpenChoreo quickstart](https://openchoreo.dev/docs/getting-started/quick-start-guide/),
[native k3d guide](https://openchoreo.dev/docs/getting-started/try-it-out/on-k3d-locally/),
[Docker port publishing](https://docs.docker.com/engine/network/port-publishing/),
[stable controller registration](https://github.com/openchoreo/openchoreo/blob/v1.3.3/cmd/main.go).

## 2. Install the pinned project tools and run preflight

Use a reviewed checkout of this fork and its existing mise owner. Versions are
declared once in `mise.toml`; the generated `mise.lock` includes macOS ARM64.
Do not run the upstream main-branch installer from this checkout for a stable
release: it can combine current source values with a released chart.

```bash
cd /absolute/path/to/openchoreo
mise trust
mise tasks validate
mise run local -- help

docker context ls
# Select actual owner-approved values; do not copy the angle-bracket placeholders.
export DOCKER_CONTEXT='<existing-local-Docker-context>'
export OPENCHOREO_CLUSTER_NAME='<unique-disposable-cluster-name>'
export OPENCHOREO_LOCAL_STATE_DIR='/absolute/private/parent/new-pilot-directory'
export OPENCHOREO_KUBE_PORT='<free-loopback-Kubernetes-port>'

mise run local -- preflight
```

The state directory's parent must already exist, and its canonical path must not
contain symlinked parents. The new state directory must be outside the checkout.
Creation makes it mode 700 and writes its kubeconfig and receipt under a private
umask. Inherited `K3D_*` overrides are refused because native k3d gives them
precedence over the configuration file; the helper sets its own documented
Colima DNS adaptation when needed. Preflight prints selected runtime capacity
and disk usage, and reads the
existing k3d inventory. It does not create the directory, pull application images,
create containers, install charts, or modify any system setting. A successful
preflight is not a successful installation. Port availability can change after
preflight; native cluster creation will fail if the chosen port is occupied.

The initial Kubernetes API binds to `127.0.0.1`. No application, registry,
observability, remote-development, or public-facing ports are published. The
configuration disables K3s's unused Traefik and service load balancer. It does
not lower kubelet eviction thresholds to conceal disk pressure.

### Release and architecture evidence

As checked on 2026-11-14, the latest stable release is **v1.3.3**, published
2026-10-29. The exact tagged installer selects K3s `v1.36.1-k3s1`; the tagged
quickstart Dockerfile selects k3d `v5.8.3` and kubectl `v1.36.1`. This profile
deliberately updates cert-manager to **v1.21.3**: the original installer pin
`v1.19.4` is in an end-of-life minor whose documented Kubernetes compatibility
stops at 1.35, while cert-manager 1.21 supports/tests Kubernetes 1.33–1.36.
This is a fresh installation, not an in-place cert-manager minor upgrade.
The source branch may already identify itself as a later milestone.
Published OCI charts are the release artifacts; source chart metadata at a tag
can still contain a development app version before packaging.

The following public registry manifest indexes were inspected directly, without
pulling image layers. Each listed image contained a **linux/arm64** platform:

| Image(s) | Tag |
| --- | --- |
| `ghcr.io/openchoreo/controller`, `openchoreo-api`, `cluster-gateway`, `cluster-agent` | `v1.3.3` |
| `ghcr.io/openchoreo/quick-start` (optional demo helper, unused here) | `v1.3.3` |
| `registry.k8s.io/kubectl` (chart authorization bootstrap) | `v1.36.0` |
| `quay.io/jetstack/cert-manager-controller`, `cert-manager-webhook`, `cert-manager-cainjector`, `cert-manager-startupapicheck` | `v1.21.3` |
| `docker.io/rancher/k3s` | `v1.36.1-k3s1` |
| `ghcr.io/k3d-io/k3d-proxy`, `ghcr.io/k3d-io/k3d-tools` | `5.8.3` |
| `docker.io/rancher/local-path-provisioner` | `v0.0.36` |
| `docker.io/rancher/mirrored-coredns-coredns` | `1.14.3` |
| `docker.io/rancher/mirrored-library-busybox` | `1.37.0` |
| `docker.io/rancher/mirrored-metrics-server` | `v0.8.1` |
| `docker.io/rancher/mirrored-pause` | `3.6` |

This is image compatibility evidence, not an execution test on the target Mac.
Recheck registry manifests when changing versions, including the k3d helper
images and the images selected by any optional plane or application. Docker's
native read-only command is `docker buildx imagetools inspect IMAGE:TAG`; an ARM64
`occ` binary or a source build matrix alone is insufficient evidence about images.
Do not force the whole installation to `linux/amd64` when the selected components
already provide native ARM64 images.

Sources: [stable release](https://github.com/openchoreo/openchoreo/releases/tag/v1.3.3),
[tagged installer](https://github.com/openchoreo/openchoreo/blob/v1.3.3/install/k3d/k3d-install.sh),
[tagged cluster config](https://github.com/openchoreo/openchoreo/blob/v1.3.3/install/k3d/single-cluster/config.yaml),
[tagged quickstart tool versions](https://github.com/openchoreo/openchoreo/blob/v1.3.3/install/quick-start/Dockerfile),
[cert-manager supported versions](https://cert-manager.io/docs/releases/),
[cert-manager Helm installation](https://cert-manager.io/docs/installation/helm/),
[K3s release and bundled image list](https://github.com/k3s-io/k3s/releases/tag/v1.36.1%2Bk3s1),
[k3d native configuration](https://k3d.io/v5.8.3/usage/configfile/),
[Docker manifest inspection](https://docs.docker.com/reference/cli/docker/buildx/imagetools/inspect/).

## 3. Create the private cluster and configure identity

```bash
mise run local -- create
```

This refuses an existing state destination or k3d cluster of the same name. All
later operations require the original receipt, node ID and private kubeconfig.
If creation fails or is interrupted, inspect the retained directory and native
k3d state before retrying; the script does not delete a partial cluster or adopt
one by name. Do not fabricate a receipt to bypass that check.

Prepare the reviewed external values described in the
[private pilot guide](../../deploy/aiagencypro/README.md#2-supply-identity-and-authorization-privately).
Use the existing secret/configuration owner and save no credentials in this
public repository. The external file must be owned by the current user, have
mode 400 or 600, and use a canonical absolute path without symbolic links. The
helper rejects unsafe inputs without changing their permissions. Verify the
real issuer, discovery/JWKS, authorization and
token endpoints, audience, CLI client, subject claim mapping and explicitly
scoped role bindings. Preserve authentication, authorization and TLS verification.
The base profile grants no sample identities a role; merely changing the issuer
does not make a user authorized.

The external file is Helm's final values layer and can override the base. It
must be reviewed to retain enabled authentication/authorization, verified TLS,
internal mTLS and the disabled optional/public services. The helper checks native
chart validity; it does not certify arbitrary private overrides or correct IdP
claim semantics. Review that merged configuration before installation and before
sharing the API, then prove the real allow/deny behavior in the acceptance table.

For tailnet API use, `openchoreoApi.config.server.publicUrl` must be the eventual
HTTPS tailnet FQDN and selected HTTPS port. Obtain that name from the actual
connected node, not a guessed hostname. The API can use an external HTTPS IdP;
its browser callback/client settings must match the selected native CLI or
existing portal flow. Verify issuer/JWKS/token reachability from the cluster as
well as from the Mac: host MagicDNS resolution does not prove pod resolution.
Do not disable certificate verification to make those checks pass.

```bash
export OPENCHOREO_PRIVATE_VALUES='/absolute/private/path/reviewed-control-plane-values.yaml'
export OPENCHOREO_PLANE_ID='<plane-identity-from-the-existing-private-owner>'
mise run local -- install
mise run local -- status
```

Installation first performs native chart rendering into a new private temporary
directory, then installs cert-manager and the published CP/DP charts. The render
is removed on exit and is never printed or uploaded. The script copies only the
public cluster-gateway CA certificate into the data-plane ConfigMap. The gateway
and agent keep their native certificate management and mTLS. No additional
identity service, secret backend, edge certificate controller or demo catalog
is introduced.

Native Helm readiness confirms platform resources reached the chart's wait
conditions. The data-plane agent has no readiness probe proving enrollment, so
that result must not be described as a connected plane.

## 4. Register and exercise the data plane

Use the [stable registration procedure](https://github.com/openchoreo/openchoreo/blob/v1.3.3/install/k3d/single-cluster/README.md#register-data-plane)
and [actual ClusterDataPlane schema](https://github.com/openchoreo/openchoreo/blob/v1.3.3/api/v1alpha1/clusterdataplane_types.go)
to prepare a reviewed native resource with the existing owner's name/identity.
Its `spec.planeID` must match `OPENCHOREO_PLANE_ID`, and
`spec.clusterAgent.clientCA.value` must contain the public `ca.crt` from this
agent's `cluster-agent-tls` Secret. Do not copy `tls.key`. The sample's gateway
and `secretStoreRef` describe optional services that this profile has not
installed; do not reference nonexistent services merely to copy the sample.
Choose namespace-scoped `DataPlane` when the tenant model requires it, using its
native schema and the same explicit identity alignment. The registration schema
requires a lowercase DNS label (up to 63 characters), which is stricter than
the Helm chart's label-value field; the helper checks the registration contract.

Use the isolated kubeconfig for all native commands:

```bash
export KUBECONFIG="$OPENCHOREO_LOCAL_STATE_DIR/kubeconfig.yaml"
export KUBE_CONTEXT="k3d-$OPENCHOREO_CLUSTER_NAME"
export OPENCHOREO_REVIEWED_REGISTRATION='/absolute/private/path/reviewed-plane-registration.yaml'
kubectl --kubeconfig "$KUBECONFIG" --context "$KUBE_CONTEXT" \
  apply --dry-run=server -f "$OPENCHOREO_REVIEWED_REGISTRATION"
kubectl --kubeconfig "$KUBECONFIG" --context "$KUBE_CONTEXT" \
  apply -f "$OPENCHOREO_REVIEWED_REGISTRATION"
```

The review input must already exist in the private configuration owner. Inspect
the resulting plane status and cluster-agent logs, then deploy one immutable
ARM64-compatible image using the reviewed Project, Environment, ComponentType,
Workload and release resources. A no-endpoint worker avoids application gateway
dependencies for this first check. Confirm actual workload reconciliation,
application behavior and rollback. Add endpoint routing, secret consumers,
workflow builds and observability one capability at a time, using the native
upstream owners and their exact prerequisites. Optional-plane dependencies may
have newer security fixes than the original 1.3.3 installer; review current
upstream guidance before enabling them.

## 5. Add private tailnet access to the API

First use a foreground loopback-only port forward. Keep its terminal open; the
process is intentionally not installed as a daemon or background service.

```bash
export OPENCHOREO_API_LOCAL_PORT='<free-owned-loopback-API-port>'
mise run local -- forward
```

This forwards only the `openchoreo-api` Service's native HTTP port. The Kubernetes
API and cluster-gateway's mTLS ports stay private. Use the installed Tailscale
CLI associated with the existing node; do not install a second client or run
`tailscale up` with different settings. In another terminal inspect:

```bash
tailscale status --json
tailscale serve status --json
tailscale funnel status --json
```

Obtain the connected node's actual `.Self.DNSName` and confirm its existing
tailnet access grants. Select an unused, approved Serve HTTPS port. Preserve any
existing portal handler on port 443; this profile assumes neither ownership of
that handler nor support for putting the API beneath an arbitrary URL prefix.
Only after the private API URL and existing identity client configuration agree:

```bash
export OPENCHOREO_TAILNET_HTTPS_PORT='<unused-owned-Serve-HTTPS-port>'
tailscale serve --bg --https="$OPENCHOREO_TAILNET_HTTPS_PORT" \
  "http://127.0.0.1:$OPENCHOREO_API_LOCAL_PORT"
tailscale serve status --json
```

Serve supplies tailnet HTTPS and forwards to the Mac's loopback endpoint.
OpenChoreo continues to enforce its own OIDC/RBAC; tailnet membership is not a
platform administrator role. If HTTPS certificates require enabling tailnet DNS
or HTTPS, review that exact account setting before changing it. Certificate
issuance makes the certificate name visible in public certificate-transparency
logs even though Serve's service remains private. Never use Funnel for this
pilot or proxy the internal cluster-gateway through an HTTP TLS terminator.
Never reset all Serve configuration to remove one pilot handler.

Sources: [Tailscale Serve](https://tailscale.com/kb/1312/serve),
[Serve command](https://tailscale.com/kb/1242/tailscale-serve),
[HTTPS certificates](https://tailscale.com/kb/1153/enabling-https),
[kubectl port-forward](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/).

## 6. Acceptance, daily operation and recovery

| Check | Evidence required |
| --- | --- |
| Host preflight | Actual Mac architecture, selected daemon, capacity, disk and version checks |
| Platform startup | Native Helm status, Ready nodes, expected pods and issued certificates |
| Data-plane enrollment | Matching identity/certificate, connected plane status and agent logs |
| Application functionality | Real workload ready, application behavior, change and rollback |
| Identity and least privilege | Real sign-in/token flow; an authorized action succeeds and a less privileged action is denied |
| Network boundary | Approved tailnet client succeeds; unapproved peer and ordinary LAN/public access fail |
| Restart/recovery | Stop/start and Docker/host restart tested; foreground forward restored deliberately |

`mise run local -- stop` and `mise run local -- start` operate only on the
recorded cluster. A sleeping or offline Mac cannot provide an always-on service.
Keep the private kubeconfig, receipt and reviewed desired state in their existing
appropriate owner; the private kubeconfig is cluster-administrator material.
Recreating the cluster changes its certificates and node ID and requires a new
registration. Helm rollback alone does not revert CRDs; follow the stable
[upgrade guidance](https://openchoreo.dev/docs/platform-engineer-guide/upgrades/overview/)
before changing the pinned platform version.

For removal, first inspect Serve status and remove only the owned handler using
its exact `--https` port and `off`, then stop the foreground forward. Run
`mise run local -- preflight` to verify ownership before a deliberate native
`k3d cluster delete "$OPENCHOREO_CLUSTER_NAME"` on the same selected context.
Delete only its reviewed private state directory after confirming the cluster
is gone. Never use Docker-wide prune, global Serve reset, or the demo uninstall
script to clean up this private profile.

Offline validation in this repository is `mise run local:validate` plus
`mise run platform:validate`. The existing always-on workflow lint owner checks
the shell script with Bash and ShellCheck. Those checks do not prove any row of
the runtime acceptance table succeeded on a Mac; record actual results after
executing them on the selected host.
