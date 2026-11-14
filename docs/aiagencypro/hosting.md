# Hosting and rollout decisions

Research date: 2026-11-14. This document describes a proposed topology and generic
implementation inputs. It does not identify a cloud account, a tenant, or a live
deployment. Existing private architecture and catalog records remain authoritative.

## Recommended topology

Run OpenChoreo on an ordinary managed Kubernetes cluster. Use Cloudflare for DNS,
HTTP application ingress, employee access, and separate compatible edge workloads.
Preserve the current public website until its repository, deployment owner, DNS,
and traffic have been inspected.

The initial [private pilot profile](../../deploy/aiagencypro/README.md) deploys only
the control plane and data plane agent. External CI produces application images.
The bundled Backstage portal, example public ingress, in-cluster build plane,
remote-development router, and agent-facing MCP endpoint are disabled during
bootstrap. Integrate with the existing portal and catalog instead of creating a
second production source of truth.

OpenChoreo's [deployment topology guide](https://openchoreo.dev/docs/platform-engineer-guide/deployment-topology/)
documents Kubernetes 1.34+ and a production baseline of three nodes with at least
4 CPU cores and 8 GB RAM each. That is a topology floor, not sizing proof for every
optional module or application. Its
[production-sizing guide](https://openchoreo.dev/docs/platform-engineer-guide/production-sizing/)
separates platform overhead from workloads and excludes the identity provider,
secrets/key vault, and managed PostgreSQL from its calculator.

## Where Cloudflare fits

| Capability | Role | Implementation consideration |
| --- | --- | --- |
| DNS and HTTP proxy | Approved public app hostnames | Inspect current routes, TLS, and zone ownership first |
| Tunnel | Outbound connection from Kubernetes to edge | Run a separate `cloudflared` deployment with fixed redundant replicas |
| Access | Employee portal access and explicit machine policies | Keep application OIDC and OpenChoreo RBAC intact |
| Workers Static Assets | New compatible frontend and full-stack applications | Separate source and release cycle from the OpenChoreo software fork |
| Workers | Edge APIs, webhooks, and supported asynchronous workloads | Validate runtime, memory, CPU and dependency compatibility |
| Containers | Selected Linux workloads or sandboxes | No supported drop-in replacement for OpenChoreo's Kubernetes cluster |

Cloudflare [recommends Workers Static Assets for new projects](https://developers.cloudflare.com/workers/best-practices/workers-best-practices/).
That is not a reason to migrate an existing Pages deployment without a benefit.
[Workers limits](https://developers.cloudflare.com/workers/platform/limits/) include
128 MB memory per isolate and bounded CPU time. Conventional backend processes
must be evaluated individually rather than assumed compatible.

[Containers](https://developers.cloudflare.com/containers/) are generally available.
Their [FAQ](https://developers.cloudflare.com/containers/faq/) describes ephemeral
disk by default, constrained Docker-in-Docker, and no iptables manipulation.
Together with OpenChoreo's Kubernetes APIs, controllers, storage, and networking
requirements, this supports using a real Kubernetes provider for the platform.
Cloudflare can host selected product components without hosting the platform itself.

### Keep cluster-agent mTLS separate from web ingress

OpenChoreo's [multicluster protocol](https://openchoreo.dev/docs/platform-engineer-guide/multi-cluster-connectivity/)
uses client-certificate authentication over WebSockets. The native options include
a direct load balancer and TLS passthrough. The pilot keeps this traffic inside one
cluster with `clusterGateway.agentAuth.mode: mtls` and internal API mTLS enabled.

Do not place that endpoint behind ordinary HTTP TLS termination and assume the
client certificate survives. A forwarded-certificate mode is a distinct trust
design requiring a validated proxy boundary and current upstream guidance; it is
not enabled by this profile. Keep a future remote-plane gateway private or use
explicit end-to-end TLS passthrough. Route portal and application HTTP separately.

### Plan certificates with domain depth

[Universal SSL on a full DNS zone](https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/limitations/)
covers its apex and first-level subdomains. Deeper environment/application names
need appropriate advanced or custom certificates.
[Total TLS](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/total-tls/)
does not automatically issue certificates for Cloudflare Tunnel hostnames; plan
those certificates explicitly. Proposed naming must follow the existing domain
contract rather than embedding new hostnames into this fork.

The [Kubernetes Tunnel guide](https://developers.cloudflare.com/tunnel/guides/kubernetes/)
recommends a separate `cloudflared` deployment and warns that scaling replicas down
breaks existing connections. Replicas provide availability, not traffic balancing.
[Access service policies](https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/)
must support the actual headless clients alongside the platform's own tokens.

## Provider decision

Existing account ownership, identity, region, contracts, and operating expertise
take precedence over selecting a new provider. With no established provider,
DigitalOcean Kubernetes offers a straightforward cost baseline for a standard
Kubernetes pilot. GKE Standard is another practical target when broader Google
Cloud integration is useful. EKS or AKS are appropriate when their respective
cloud is already the organization's operating environment.

| Provider | Verified pricing anchor | Decision limit |
| --- | --- | --- |
| DigitalOcean Kubernetes | Three regular Basic 4-vCPU/8-GiB nodes at $48/month each, plus $40/month HA control plane: $184/month floor | Shared vCPU baseline; storage, networking, databases, observability, apps, backups and support are additional |
| GKE Standard | $0.10/cluster-hour management fee; underlying compute is separate | Free-tier cluster credit does not cover regional Standard clusters |
| GKE Autopilot | Resource-request-based pricing for general-purpose workloads | Admission restrictions require rendered-chart validation |
| EKS | $0.10/cluster-hour in standard support; $0.60 in extended support | Compute, storage, networking and associated services are additional |
| AKS | Official Free tier for experimentation, Standard for production SLA | Obtain region- and account-specific price rather than invent a quote |

These are public price anchors, not a total-cost quote or authorization to spend.
At 730 hours, the EKS management examples are $73 and $438 respectively. The DOKS
floor does not assert that all default modules and applications fit on those nodes.
Sources: [DOKS pricing](https://docs.digitalocean.com/products/kubernetes/details/pricing/),
[Droplet sizes](https://www.digitalocean.com/pricing/droplets),
[GKE pricing](https://cloud.google.com/kubernetes-engine/pricing),
[EKS pricing](https://aws.amazon.com/eks/pricing/), and
[AKS pricing](https://azure.microsoft.com/en-us/pricing/details/kubernetes-service/).

### Autopilot compatibility is conditional

The [v1.3.3 Containerfile workflow](https://github.com/openchoreo/openchoreo/blob/v1.3.3/samples/getting-started/workflow-templates/containerfile-build.yaml)
uses a privileged Podman runner with user namespaces. GKE Autopilot
[rejects most privileged workloads without an applicable allowlist](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/about-autopilot-privileged-workloads).
External builds avoid this optional workflow-plane requirement, but do not prove
gateway, monitoring, storage, host access, or kernel-setting compatibility. Start
with a standard cluster unless those constraints have been tested.

## Delivery ownership and staged rollout

1. **Fork and review.** Keep upstream history recognizable. Organization-specific
   configuration and operational records belong in the existing private systems.
2. **Local validation.** Pin the toolchain, validate upstream release chart schemas,
   and inspect rendered resources. Source-tag chart metadata can still point to
   development images; use release packages for deployment.
3. **Private cluster pilot.** Use existing identity, no public ingress, one registered
   data plane, and one immutable application image. Verify denied access as well as
   permitted access, reconciliation, health, rollback and restart.
4. **Portal and operating integrations.** Add maintained plugins to the existing
   Backstage implementation in isolation. Reuse catalog identifiers and ownership.
   Configure monitoring, audit export, certificate rotation, and backup/restore.
5. **Staging ingress.** Add explicit Cloudflare hostnames, origin TLS, access policy,
   and real health checks. Confirm public/private routing and stream behavior.
6. **Production promotion.** Review capacity, budget, support, restore evidence,
   rollout/rollback, tenant boundaries, and the production traffic change.

Choose one deployment owner for each application/environment. GitHub Actions can
build, test, publish digest-addressed images and generate reviewable desired-state
changes. The existing GitOps controller reconciles Kubernetes. If a separate
Cloudflare application already uses Workers Builds, preserve it unless changing
owners has a clear purpose. Avoid two pipelines deploying the same environment.

Cloudflare supports both [native Workers Builds](https://developers.cloudflare.com/workers/ci-cd/builds/)
and its [official GitHub Actions integration](https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/).
Use scoped deployment credentials and reviewed action revisions. Current official
Actions guidance uses an API token; do not assume that cloud-provider OIDC support
implies an identical Cloudflare authentication flow.

Use independent nonproduction and production environment records, scoped service
identities, immutable image digests, and explicit promotion. Automated upstream
updates should produce reviewable changes, not silently upgrade a live control
plane. Upgrade tests must include schemas/CRDs, authentication, authorization,
registered-plane communication, a representative application, and restore.

## When a lighter platform is preferable

For a small number of services, existing CI plus managed application hosting may
deliver the required reliability with less platform ownership. Workers can host
compatible frontend/edge workloads; a managed container service can host other
applications while retaining the existing database and identity providers.
For example, Railway documents [GitHub deployment](https://docs.railway.com/deployments),
[health checks](https://docs.railway.com/deployments/healthchecks), and
[rollback](https://docs.railway.com/deployments/deployment-actions).

That is an alternative to adopting an internal Kubernetes platform, not a proposal
to run the entire OpenChoreo stack on an arbitrary container service. OpenChoreo
becomes more valuable when repeatable self-service across projects, reusable
platform types, governed promotion, controlled agent operations, and multiple
deployment environments justify operating the platform.

## Deployment evidence still required

The generic files establish intent only. A deployment is complete only after the
authoritative service reports successful reconciliation and functional checks
verify the application, identity boundaries, recovery, and expected image digest.
Cloud account quotas, cost ceiling, region, cluster access, identity registration,
domain configuration, and private desired-state ownership must be verified at use
time. No production system is implied by a successful schema render.
