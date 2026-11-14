# OpenChoreo integration and delivery guide

This guide describes a staged integration with an existing developer portal, catalog, identity provider, and delivery system. It is a deployment design and operational checklist, not evidence that a cluster, DNS record, identity application, or production service has been created.

Research baseline: **2026-11-14**. The deployment baseline is **OpenChoreo v1.3.3**, released on 2026-10-29. Keep its chart, CLI, images, and documentation aligned. This fork's development branch can be ahead of the stable release; building its source is a separate operation from installing the released charts. Recheck the [release](https://github.com/openchoreo/openchoreo/releases/tag/v1.3.3) and [upgrade guidance](https://openchoreo.dev/docs/platform-engineer-guide/upgrades/overview/) before changing the baseline.

## 1. Ownership and architecture

Use OpenChoreo as the Kubernetes application platform behind the existing developer experience. Begin with the control and data planes, external CI, and the existing GitOps controller; use Flux when it is the selected owner. Add a workflow plane when an application actually needs platform-managed Argo workflows. Add observability capabilities against explicit retention, cost, and operating requirements. These planes and their dependencies are described in the [installation guide](https://openchoreo.dev/docs/getting-started/try-it-out/on-your-environment/).

| Concern | Recommended owner | Integration contract |
| --- | --- | --- |
| Platform source and upstream changes | This fork | Small, reviewed changes; upstream synchronization through pull requests |
| Installed versions and desired infrastructure | A private configuration repository | Pinned charts, environment values, selected GitOps controller resources, and reviewed OpenChoreo definitions |
| Application source and image builds | Existing application repositories and CI | Tested image digest, source commit, provenance, and release proposal |
| Catalog identity, ownership, taxonomy, and documentation | Existing authoritative catalog | Preserve canonical identifiers and owner references; document mappings to OpenChoreo resources |
| Developer portal | Existing Backstage application | Official OpenChoreo packages after compatibility and authentication validation |
| Workload reconciliation | OpenChoreo controllers | Render and apply the resources described by releases and bindings |
| Desired-state reconciliation | Existing GitOps controller; Flux when selected | One declared owner for each managed resource and field |
| Public HTTP traffic and access controls | Existing edge and gateway systems | Explicit route ownership, origin TLS, and access policy |
| Secrets | Existing supported secret store | References and narrowly scoped access; no secret values in Git |

Keep customer configuration, credentials, and account inventories out of this public fork. Keep canonical catalog UUIDs/URNs as references in approved metadata contracts. Kubernetes object UIDs identify object lifetimes; they should not become business identity keys. A catalog projection is useful; another independent identity registry is not part of this design.

### Kubernetes and Cloudflare boundaries

OpenChoreo needs Kubernetes; Cloudflare Workers or Pages alone do not provide its runtime. The stable installation guide requires Kubernetes 1.34+, a default StorageClass, and LoadBalancer support. Evaluate capacity using the [deployment topology](https://openchoreo.dev/docs/platform-engineer-guide/deployment-topology/) and [production sizing](https://openchoreo.dev/docs/platform-engineer-guide/production-sizing/) guides, then add workload, telemetry, recovery, and growth headroom.

Use Cloudflare for appropriate HTTP delivery, DNS, and access controls. A Cloudflare Tunnel can reach Kubernetes services through an adjacent `cloudflared` deployment; fixed redundant replicas improve connector availability. Follow the [official Kubernetes tunnel guide](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/deployment-guides/kubernetes/), including its warning that connector replicas do not themselves provide application load balancing.

Treat ClusterGateway traffic separately. Remote plane agents use mutually authenticated TLS over WebSockets to the external gateway endpoint. Its internal API is a separate endpoint. Use private connectivity or the documented TLS passthrough arrangement, and preserve the agent/server certificate contract. An ordinary HTTP proxy terminating TLS is therefore not a drop-in route for this connection. Do not expose the internal ClusterGateway API. See [multi-cluster connectivity](https://openchoreo.dev/docs/platform-engineer-guide/multi-cluster-connectivity/).

OpenChoreo supports alternative Gateway API implementations. Verify the existing gateway's controller, GatewayClass, route support, policies, and TLS behavior against the [gateway module documentation](https://openchoreo.dev/docs/platform-engineer-guide/api-gateway/modules/). An existing HTTP proxy is not automatically a Kubernetes Gateway API controller. Start with a dedicated compatible inner gateway behind the existing edge when direct reuse has not been proven; give each hostname and route one owner.

## 2. Integrate the existing Backstage portal

The [official installation guide](https://openchoreo.dev/docs/platform-engineer-guide/backstage-plugins/installing-into-existing-backstage/) supports installing published packages into an existing Backstage app. Use this path for the eventual production portal. The bundled portal is useful for an isolated local pilot while the integration is being validated.

### Compatibility gate

The [v1.3 compatibility matrix](https://openchoreo.dev/docs/platform-engineer-guide/backstage-plugins/compatibility-matrix/) lists this tested combination:

| Component | Tested version |
| --- | --- |
| Backstage | 1.51.0 |
| Node.js | 22.x or 24.x |
| Yarn | 4.13.x |
| `@backstage/cli` | 0.36.x |
| OpenChoreo plugin packages | 1.3.x |

Inspect `backstage.json`, workspace manifests, the lockfile, frontend architecture, and the current permission module before making changes. A newer host version is an unverified combination, not proof of incompatibility or compatibility. Test on a review branch; do not downgrade a working production portal merely to make an installation command resolve. If a supported combination cannot be achieved without breaking existing features, retain the isolated pilot and resolve package compatibility first.

Use New Frontend System `/alpha` features for a host that already uses `createApp({ features: [...] })`. Use the documented legacy recipe for a legacy host. Do not combine automatic mounting with manual legacy entity tabs. Keep the OpenChoreo package set on the same release line and review the exact lockfile. The official install page and compatibility matrix contain somewhat different dependency-resolution advice; validate the selected complete dependency graph, including React/MUI and frontend API versions, rather than copying partial pins into a newer host.

Start with the core frontend, backend, catalog, scaffolder, and authentication integrations. Add optional observability or workflow packages only when their corresponding planes exist. The external-package installation does not provide every bundled-portal feature or prebuilt scaffolder template. Its Build tab is not a substitute for an existing external GitHub Actions view. See the [plugin overview](https://openchoreo.dev/docs/platform-engineer-guide/backstage-plugins/overview/).

### Three separate identity and permission contracts

1. **Human requests:** OpenChoreo tabs need a user identity-provider token accepted by the OpenChoreo API. A Backstage identity token or an edge access cookie alone does not establish that contract. Follow the official frontend authentication integration and backend IDP-token middleware wiring.
2. **Catalog synchronization:** The catalog provider uses its own OAuth client credentials. Give this client only the catalog-reading privileges it needs. Do not reuse a human administrator's token for background synchronization.
3. **Authorization:** Backstage has one top-level permission policy. OpenChoreo's stock policy handles its own permissions and allows unrelated permissions through. Preserve the host's policy for unrelated requests and integrate OpenChoreo evaluation through supported extension points. Installing two independent policy modules or replacing existing restrictions with the stock module is not acceptable.

Verify issuer, discovery/JWKS endpoints, audience, callback URLs, grant types, scopes, group claims, expiration, logout, and revocation against the [identity configuration](https://openchoreo.dev/docs/platform-engineer-guide/identity-configuration/). Explicitly configure audience validation where appropriate. Keep TLS verification enabled. Match portal authentication/authorization feature flags to the API. Use the [permission-policy guide](https://openchoreo.dev/docs/platform-engineer-guide/backstage-plugins/permission-policy/) to implement and test policy composition; the exact adapter depends on the existing host's supported permission extension points.

### Catalog integration without duplicate ownership

The [catalog provider](https://openchoreo.dev/docs/platform-engineer-guide/backstage-plugins/catalog-sync/) projects namespaces, projects, components, and API definitions into Backstage entities. Before enabling it, define which provider owns each entity reference, how existing ownership and canonical identifiers are preserved, and which entities are projections of OpenChoreo state. Reconcile collisions before continuous sync starts. Configure a real existing owner instead of accepting a nonexistent default group.

Do not install the optional ThunderID user/group provider when another system is authoritative for users and groups. Include the necessary entity kinds in catalog rules. The documented provider schedule uses integer seconds; verify configuration against the selected package schema.

Acceptance requires a real user to see the right component, deployment state, and allowed actions, while an unrelated user cannot see or change it. Also verify that existing portal permissions, discovery, templates, and documentation still work. After acceptance, configure the control-plane chart with `backstage.enabled=false` and the required external-portal integration settings. This switch is present in the [v1.3.3 values](https://github.com/openchoreo/openchoreo/blob/v1.3.3/install/helm/openchoreo-control-plane/values.yaml); it does not configure the external portal by itself.

## 3. Tenant, secret, and release contracts

Use an OpenChoreo namespace for an organizational isolation boundary, projects for related applications, and environment-specific release bindings for lifecycle stages. This is a proposed starting model, not a claim that namespaces alone provide hostile-tenant isolation. Add Kubernetes network policies, quotas, workload identities, storage boundaries, and admission controls. Use separate data-plane clusters when the required security or availability boundary calls for them. Namespace-scoped and cluster-scoped plane registrations have different visibility; choose intentionally. See [namespace management](https://openchoreo.dev/docs/platform-engineer-guide/namespace-management/) and [platform abstractions](https://openchoreo.dev/docs/concepts/platform-abstractions/).

Use narrowly scoped human and machine roles. Higher-scope permissions cascade down. The default developer role includes secret-related capabilities, so validate its actions before assigning it to a broad group. Preserve required internal integration roles when replacing bootstrap arrays; those arrays replace rather than merge their contents. See [authorization configuration](https://openchoreo.dev/docs/platform-engineer-guide/authorization/).

Test users with multiple group memberships. OpenChoreo evaluates entitlements independently: a deny on one group does not revoke a separate group's allow. Revoke or narrow every applicable grant when removing access. Include this behavior in offboarding and tenant-isolation tests. See [authorization semantics](https://openchoreo.dev/docs/platform-engineer-guide/authorization/overview/).

Reuse an approved External Secrets Operator provider and store. Separate tenants' secret paths and workload identities, verify rotation reaches consumers, and keep secret values out of values files, workflow output, PR bodies, and generated manifests. Published quickstart credentials and development secret-store settings are unsuitable for an exposed installation. Use the stable [secret-management guide](https://openchoreo.dev/docs/platform-engineer-guide/secret-management/) and the selected provider's production configuration.

Build each application image once, record its digest and source revision, and promote the same artifact between environments. Generate an immutable ComponentRelease and change the appropriate ReleaseBinding or ProjectReleaseBinding through a reviewed configuration change. Retain previous releases/images long enough to support the recovery objective. Database migrations require their own compatibility and recovery plan; changing an image binding does not reverse data changes. See [GitOps delivery](https://openchoreo.dev/docs/platform-engineer-guide/gitops/using-flux-cd/).

## 4. Prepare the installation with native tools

Use project-scoped tooling, preferably the repository's mise configuration. Install the stable `occ` CLI separately from a development binary built from this fork's current source. Record the actual CLI, Helm, selected GitOps controller, Kubernetes, and chart versions in deployment evidence.

Required deployment inputs belong in private environment configuration: cluster/context names, region, namespaces, domains, identity applications, secret-store references, registry, image retention, approved gateway, and budget. Shell variables in the examples are placeholders for those reviewed inputs. Supply them before running commands. Never put credentials in command arguments or committed shell files.

### Inspect and render

Use the [private pilot runbook](../../deploy/aiagencypro/README.md) as the canonical preflight, render, and installation procedure. It applies the restrictive public control-plane profile first and the reviewed private values second, pins the published release charts, and keeps the control and data planes in the upstream installation namespaces. Do not render or install only the private identity values: doing so would omit the profile that disables the bundled portal, example ingress, and example entitlement mappings.

The profile requires `openchoreo-control-plane` and `openchoreo-data-plane` because the upstream internal service URLs and certificate SANs refer to those namespaces. A different namespace layout requires coordinated native value overrides and validation; changing only Helm's namespace argument is insufficient. Review merged manifests privately before distributing them because supplied values can cause a chart to render Secrets.

Reuse existing cert-manager, External Secrets Operator, Gateway API, and GitOps components when their installed versions and settings satisfy the selected features. Avoid installing competing controllers. The private pilot starts without public ingress; add gateway and secret-store prerequisites when enabling the corresponding workload features. Resolve storage, identity, certificates, secrets, and hostnames before exposing an endpoint. Use the [official installation sequence](https://openchoreo.dev/docs/getting-started/try-it-out/on-your-environment/) as the release-specific reference; its development credentials, self-signed shortcuts, and destructive cleanup instructions are not a production runbook.

For ongoing management, commit reviewed Helm releases/values through the existing GitOps mechanism. Decide explicitly which controller owns Helm releases and CRD upgrades. A server-side dry run verifies schema and admission behavior only after the required CRDs/webhooks are available; it does not establish runtime health.

### Generate Flux integration resources

Use this subsection only when Flux is the selected GitOps owner. Reuse its existing installation and established credential mechanism. If Flux has been selected but is absent, separately review the official bootstrap procedure and its repository/cluster changes. With another controller, use that controller's native repository and reconciliation resources instead of installing a parallel owner. Prepare the private configuration repository using OpenChoreo's [GitOps layout](https://openchoreo.dev/docs/platform-engineer-guide/gitops/overview/).

The following [Flux source command](https://fluxcd.io/flux/cmd/flux_create_source_git/) exports a manifest locally. `FLUX_GIT_SECRET` must reference an existing appropriately scoped credential; this command does not create one.

```bash
: "${FLUX_NAMESPACE:?Existing Flux namespace}"
: "${FLUX_SOURCE:?Name for the approved Git source}"
: "${GITOPS_URL:?Private configuration repository URL}"
: "${GITOPS_BRANCH:?Reviewed desired-state branch}"
: "${FLUX_GIT_SECRET:?Existing repository credential Secret}"
: "${FLUX_SOURCE_FILE:?New local source manifest path}"

flux create source git "$FLUX_SOURCE" \
  --namespace "$FLUX_NAMESPACE" \
  --url "$GITOPS_URL" --branch "$GITOPS_BRANCH" \
  --secret-ref "$FLUX_GIT_SECRET" --interval=1m \
  --export > "$FLUX_SOURCE_FILE"
```

Use [native Kustomization generation](https://fluxcd.io/flux/cmd/flux_create_kustomization/) for each declared scope. Define dependencies in this order: release CRDs/controllers and namespaces; shared platform resources; namespace platform resources; application resources and bindings. The example below assumes the preceding platform dependency already exists in the same Flux namespace.

```bash
: "${FLUX_APP_KUSTOMIZATION:?Name for this application reconciliation}"
: "${FLUX_PLATFORM_KUSTOMIZATION:?Existing platform dependency name}"
: "${GITOPS_APPLICATION_PATH:?Application directory relative to repository root}"
: "${FLUX_RECONCILER_SERVICE_ACCOUNT:?Existing least-privilege reconciler}"
: "${OC_NAMESPACE:?Approved OpenChoreo namespace}"
: "${FLUX_APP_FILE:?New local Kustomization manifest path}"

flux create kustomization "$FLUX_APP_KUSTOMIZATION" \
  --namespace "$FLUX_NAMESPACE" \
  --source "GitRepository/$FLUX_SOURCE" \
  --path "$GITOPS_APPLICATION_PATH" \
  --target-namespace "$OC_NAMESPACE" \
  --service-account "$FLUX_RECONCILER_SERVICE_ACCOUNT" \
  --depends-on "$FLUX_PLATFORM_KUSTOMIZATION" \
  --interval=5m --prune=false --wait=true \
  --export > "$FLUX_APP_FILE"
```

Start with pruning disabled while validating ownership and deletion behavior. Then enable the intended pruning policy in a reviewed change, with explicit handling for retained data and release history. Include generated manifests in explicit `kustomization.yaml` resource lists. Keep controller-generated objects outside Flux-owned paths. Verify health checks against actual OpenChoreo status conditions; reconciliation completion and application readiness are separate acceptance checks.

## 5. Generate application releases and promote them

Create the namespace, project, component, deployment pipeline, and approved types using the stable UI/CLI or the matching official examples. Export/review the resulting definitions before placing them under GitOps ownership. For a typed project, `occ project scaffold` can generate the project from an existing ProjectType or ClusterProjectType; inspect the selected release's help and required parameters. Avoid maintaining a second custom CRD generator.

The following examples use the **v1.3.3 CLI** and write local desired-state files. Workload creation otherwise defaults to API-server mode. The explicit `--mode file-system` prevents accidental API mutation. Inputs include an application-authored workload descriptor, the private repository root, and an immutable image digest.

```bash
: "${GITOPS_ROOT:?Existing private repository root}"
: "${OC_NAMESPACE:?Approved OpenChoreo namespace}"
: "${OC_PROJECT:?Existing project name}"
: "${OC_COMPONENT:?Existing component name}"
: "${WORKLOAD_DESCRIPTOR:?Application workload descriptor path}"
: "${IMAGE_DIGEST:?Full registry image reference with sha256 digest}"
: "${WORKLOAD_FILE:?Reviewed workload output path}"
: "${SOURCE_COMMIT:?Image source commit SHA}"
: "${SOURCE_REPOSITORY:?Image source repository URL}"
: "${OC_RELEASE:?New lowercase immutable release name}"

occ workload create \
  --mode file-system --root-dir "$GITOPS_ROOT" \
  --descriptor "$WORKLOAD_DESCRIPTOR" \
  --namespace "$OC_NAMESPACE" --project "$OC_PROJECT" \
  --component "$OC_COMPONENT" --image "$IMAGE_DIGEST" \
  --source-commit "$SOURCE_COMMIT" --source-repository "$SOURCE_REPOSITORY" \
  --output-path "$WORKLOAD_FILE"

occ componentrelease generate \
  --mode file-system --root-dir "$GITOPS_ROOT" \
  --namespace "$OC_NAMESPACE" --project "$OC_PROJECT" \
  --component "$OC_COMPONENT" --name "$OC_RELEASE"
```

Review output after each generator before running the next. The repository must contain the referenced definitions in the native file-system layout. Use `--dry-run` on an individual generator to inspect its output first. See the stable command sources for [workloads](https://github.com/openchoreo/openchoreo/blob/v1.3.3/internal/occ/cmd/workload/cmd.go) and [component releases](https://github.com/openchoreo/openchoreo/blob/v1.3.3/internal/occ/cmd/componentrelease/cmd.go).

In v1.3.3, `releasebinding generate` has **no `--namespace` flag**: it resolves the namespace through the active `occ` context. Configure an existing context locally, inspect it, and verify the intended namespace before generating a binding. This context change is local CLI configuration, not a cluster deployment. Follow the [CLI configuration guide](https://openchoreo.dev/docs/platform-engineer-guide/cli-configuration/) when creating/authenticating a context.

```bash
: "${OC_CONTEXT:?Existing reviewed occ context}"
: "${OC_ENVIRONMENT:?Approved target environment in the project pipeline}"

occ config context update "$OC_CONTEXT" \
  --namespace "$OC_NAMESPACE" --project "$OC_PROJECT"
occ config context use "$OC_CONTEXT"
occ config context list

# Continue only after confirming the selected namespace and project above.
occ releasebinding generate \
  --mode file-system --root-dir "$GITOPS_ROOT" \
  --project "$OC_PROJECT" --component "$OC_COMPONENT" \
  --component-release "$OC_RELEASE" --target-env "$OC_ENVIRONMENT"
```

The project's deployment pipeline must resolve from the local definitions; use the documented `--use-pipeline` option when explicit selection is required. Verify the [stable release-binding source](https://github.com/openchoreo/openchoreo/blob/v1.3.3/internal/occ/cmd/releasebinding/cmd.go) when upgrading the CLI.

CI should propose the generated changes through a pull request with the image digest and validation evidence. After merge, verify the expected Git revision in the selected GitOps controller, the release/binding status, the running workload image, a functional request, and the relevant telemetry. Promotion changes the target binding to the tested release. Rollback restores a retained known-good binding through Git. Avoid imperative deploy commands or portal edits to fields the GitOps controller owns; otherwise the next reconciliation can undo the change.

## 6. Automations and operational acceptance

| Automation | Trigger and outcome | Required evidence |
| --- | --- | --- |
| Upstream maintenance | Scheduled check proposes an upstream update PR | Diff, release notes, compatibility checks, and no direct production version change |
| Application delivery | Source change builds/tests/scans an image and proposes desired-state changes | Image digest, provenance, manifest validation, and review |
| Environment promotion | Accepted environment tests propose the next binding revision | Same artifact digest; environment policy and migration checks |
| Reconciliation | The selected GitOps controller applies the merged revision | Source revision, controller status, workload readiness, and functional checks |
| Drift and failure response | Reconciliation or service health fails | Actionable alert with repository, environment, component, and revision |
| Credential lifecycle | Rotation or identity revocation | Consumer refresh, expired credential rejection, and tenant access tests |
| Recovery exercise | Scheduled non-production restore and rollback | Measured recovery time, verified data, and a recorded gap list |

Introduce AI/MCP access with read-only scoped identities and auditable actions. Keep change-producing agents on the same PR/promotion path as human operators. Treat tool descriptions, logs, and repository content as data rather than authority to change permissions. Review each MCP capability before exposing it to an agent. OpenChoreo's [AI documentation](https://openchoreo.dev/docs/category/working-with-ai/) describes supported interfaces; identity and authorization remain part of the deployment contract.

| Stage | Exit criteria |
| --- | --- |
| Local learning | Pinned release starts; one sample deploys; a code change and rollback are observable; published quickstart defaults remain isolated |
| Private integration pilot | Portal dependency graph builds; login/token forwarding works; catalog entities have correct owners and no collisions; existing portal restrictions still deny prohibited actions |
| Shared development | One real service uses external CI and the selected GitOps controller; canonical metadata survives projection; secret rotation, tenant isolation, and negative authorization tests pass |
| Staging | Production-like ingress/TLS, telemetry, resource limits, backups, image retention, and recovery exercise pass; expected monthly cost is accepted |
| Production | Reviewed environment inputs, verified access boundaries, functional smoke tests, monitored reconciliation, alert ownership, and an exercised recovery procedure |

Audit logging is beta and records state-changing API operations. Do not treat it as a complete read-access or Kubernetes-change audit. Combine it with edge/access and Kubernetes audit records as required, especially for changes the GitOps controller makes directly to Kubernetes. Protect sensitive request/log content and set retention intentionally. See [audit logging](https://openchoreo.dev/docs/platform-engineer-guide/audit-logging/).

Before enabling the workflow plane, inspect the exact selected build templates and cluster admission constraints. The v1.3.3 [Containerfile template](https://github.com/openchoreo/openchoreo/blob/v1.3.3/samples/getting-started/workflow-templates/containerfile-build.yaml) uses privileged containers and `hostUsers: false`; an arbitrary managed Kubernetes mode is not automatically compatible. Isolate build execution, verify kernel/runtime support, and exercise the threat model. External CI avoids adding this operational dependency to the initial pilot.

Follow the [upgrade procedure](https://openchoreo.dev/docs/platform-engineer-guide/upgrades/overview/): advance supported minor versions sequentially, apply target CRDs before upgrading controllers, and test stored-resource compatibility. Helm does not automatically upgrade chart CRDs. Back up platform state and persistent application/observability data; a manifest export alone is not a complete data backup. Verify each plane and portal integration after an upgrade. A three-node cluster alone does not prove every platform component is highly available; validate replica topology, storage, gateway behavior, and failure recovery for the chosen release.
