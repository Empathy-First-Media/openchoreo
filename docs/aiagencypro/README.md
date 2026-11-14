# AI Agency Pro platform implementation

This fork keeps OpenChoreo source compatible with upstream while adding explicit
fork controls and a reproducible development workflow. Use the released platform
for deployment and the fork source when developing platform changes.

The design is Kubernetes for the OpenChoreo control/data planes, Cloudflare for
selected HTTP edge routes, the existing developer portal and catalog for ownership,
GitHub Actions for builds, and a single GitOps owner for desired cluster state.
The public fork contains reusable configuration inputs. Business identities,
deployment endpoints, credentials, and tenant bindings stay with their existing
private owners.

## Read in this order

1. [Development and CI](development.md): install the toolchain, run native checks,
   and configure the fork's opt-in automation.
2. [Hosting decision](hosting.md): Cloudflare's role, Kubernetes options, TLS,
   capacity and operational tradeoffs.
3. [Platform integration](integration.md): existing Backstage, identity, catalog,
   GitOps, tenant boundaries, MCP, promotion and acceptance criteria.
4. [Private pilot configuration](../../deploy/aiagencypro/README.md): render and
   install the released charts into an explicitly selected existing cluster.

## Release boundaries

The selected deployment baseline is OpenChoreo **v1.3.3**, source commit
`5336791f421b3efb79603b09b8ce0c98e8ef077d`. The fork's default branch follows
upstream development and may contain prerelease APIs. The release selection in
`mise.toml` controls downloaded deployment charts and the local quickstart image;
it does not rewrite upstream `VERSION` or the Go module path.

Review release changes together with their chart values, CLI compatibility,
identity behavior, CRD upgrade procedure, and rollback/restore plan. A successful
source build does not approve a different platform release for deployment.

## Delivery stages

| Stage | Implementation owner | Evidence required |
| --- | --- | --- |
| Source changes | Fork branch and reviewed PR | Native lint, tests, build, and generated-code checks on the PR commit |
| Development pilot | Official quickstart or selected existing Kubernetes cluster | Login, one useful workload, logs, negative authorization, repeatable cleanup |
| Platform desired state | Existing private infrastructure/GitOps source | Pinned charts, native schema/render checks, explicit identities, secrets and prerequisite owners |
| Application release | Application CI and native `occ` generators | Tested image digest, scan/signing evidence, configuration PR |
| Reconciliation | One GitOps controller per desired-state scope | Source revision, controller readiness, OpenChoreo release readiness and authenticated application checks |
| Production admission | Platform and application owners | Tenant isolation, promotion, rollback, restore, alert ownership and approved spend |

Each stage is independently verifiable. Configuration files and successful offline
validation are preparation; deployment requires live owner readback and functional
acceptance. Do not infer production readiness from a workflow that skipped gated
jobs, an accepted API request, or a merged configuration PR.

## Scope of the current automation

The fork reuses upstream source CI and dependency maintenance. Fork publishing,
release orchestration, cluster tests and inherited maintenance require explicit
repository variables. Upstream synchronization opens a draft PR and never merges
the default branch automatically. Deployment configuration is reconciled from its
private owner after the selected cluster and identity configuration are available.

Cloudflare applications have their own source and deployment lifecycle. Use one
deployment owner per Worker/environment, either the existing Workers Builds
integration or the official GitHub Actions/Wrangler route. This repository does
not fabricate an unrelated website just to produce a deployment URL.

## References

- [OpenChoreo v1.3.3 release](https://github.com/openchoreo/openchoreo/releases/tag/v1.3.3)
- [OpenChoreo GitOps model](https://openchoreo.dev/docs/platform-engineer-guide/gitops/overview/)
- [External CI](https://openchoreo.dev/docs/platform-engineer-guide/workflows/external-ci/)
- [Production sizing](https://openchoreo.dev/docs/platform-engineer-guide/production-sizing/)
- [Cloudflare Workers CI/CD](https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/)
