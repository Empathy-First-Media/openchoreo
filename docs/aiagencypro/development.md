# Development and fork automation

## Install the project tools

Use [mise](https://mise.jdx.dev/getting-started.html) at the minimum version declared
in `mise.toml`. Tool versions are task-scoped, so linting workflows does not install
the Go compiler. The generated `mise.lock` contains Linux x64, macOS ARM64 and
macOS x64 download URLs and checksums; regenerate it through mise when changing
versions. Do not edit a lockfile manually.

```bash
git clone https://github.com/Empathy-First-Media/openchoreo.git
cd openchoreo
git switch -c feat/my-platform-change
mise trust
mise tasks validate
mise install --include-task-tools --locked
```

Mise owns tool selection and tasks here. Keep the existing environment/secret
activation owner. This project does not create a parallel dotenv store or use
mise to copy credentials into the shell.

The native source targets remain authoritative:

| Command | Native consumer |
| --- | --- |
| `mise run ci:workflow-lint` | Current GitHub Actions correctness checks across the repository; full default policy checks for the two new fork workflows; pinned ShellCheck |
| `mise run ci:workflow-audit` | Full inherited workflow security and policy audit; resolve or review findings before enabling publishing, releases or maintenance |
| `mise run ci:lint` | `make lint` |
| `mise run ci:generate` | `make code.gen-check` |
| `mise run ci:test` | `make test`, including upstream Go and independent uv agent projects |
| `mise run ci:build` | `make go.build` |
| `mise run ci:charts` | `make helm-package`, including upstream generators |
| `mise run platform:validate` | Strict Helm lint and template against published stable charts |

The workflow checker supports GitHub's current `job.workflow_repository` and
`job.workflow_sha` fields, used by upstream reusable workflows. Do not rewrite
valid upstream workflow context or suppress validation to accommodate an obsolete
checker.

The existing upstream workflows have additional policy findings, including missing
timeouts/concurrency controls, release-cache use, and privileged trigger handling.
The separate audit task reports them without suppression and can return a nonzero
status. Passing the correctness task is not a clean security audit. Publishing and
maintenance remain opt-in while those findings are reviewed for the selected use.

`platform:validate` supplies a reserved example issuer only for offline rendering.
It performs no cluster writes and proves neither identity interoperability nor
deployment health. Rendered output goes under the already ignored `bin/` directory.
Use reviewed private values and the pilot guide for a real installation.

## Run the released platform locally

The simplest functional evaluation uses the official release quickstart container.
This is separate from building the platform's own Go code. It requires a working
Docker daemon, sufficient memory, and an isolated development Docker context.

```bash
docker context ls
export DOCKER_CONTEXT='<your-isolated-development-context>'
export OPENCHOREO_DEV_CONTAINER='<your-unique-development-container-name>'
mise run dev:quickstart
```

Inside the official container:

```bash
./install.sh --version v1.3.3
./check-status.sh
./deploy-react-starter.sh
```

The task uses the upstream privileged container, mounts the selected Docker
daemon's socket, and uses host networking. Run it only on the explicitly selected
disposable development daemon. On macOS, verify the chosen Docker/Colima host-network
configuration and resources against the official guide. The quickstart creates a
local k3d cluster and supplies demo identities and services. Keep this environment
local. The installer uses the fixed k3d cluster name `openchoreo-quick-start`;
choosing a unique helper-container name does not create a separate cluster.
Inspect that cluster on the selected daemon before installation or cleanup, and
use the container's native uninstall procedure only for the intended disposable
cluster. Separate simultaneous pilots require separate Docker daemons.

Complete the functional loop: sign in, deploy the sample, invoke its endpoint,
inspect logs, change a release, roll it back, and verify a denied action using a
less privileged identity. Add observability through the documented
`--with-observability` installation option when evaluating that plane. In-cluster
builds are optional and require separate privileged-workload review.

## Configure fork automation

Review the workflow changes before enabling inherited Actions. Set repository
variables through GitHub's native settings or the official `gh variable set`
command. Variables are controls; a saved value is not proof that a job ran.

| Repository variable | Purpose | Initial policy |
| --- | --- | --- |
| `FORK_CI_ENABLED` | Upstream source checks and CodeQL | Enable for reviewed source CI |
| `FORK_PUBLISH_ENABLED` | Custom fork image/chart publication | Keep disabled until registry ownership and all chart image references are verified |
| `FORK_RELEASE_ENABLED` | Release/version orchestration | Keep disabled until a fork release process is needed |
| `FORK_E2E_ENABLED` | Upstream cluster and quickstart tests | Enable deliberately after runner capacity and target artifacts are selected |
| `FORK_SCHEDULED_CHECKS_ENABLED` | Inherited scheduled checks | Enable after choosing the useful schedules and costs |
| `FORK_MAINTENANCE_ENABLED` | Inherited label/backport/stale/cleanup automation | Enable only the maintained behaviors the organization wants |
| `FORK_NOTIFICATIONS_ENABLED` | External workflow notifications | Keep disabled until destinations and authorization to send are established |
| `UPSTREAM_SYNC_SCHEDULE_ENABLED` | Scheduled draft upstream sync PR | Enable after the sync token/permissions and first manual run are verified |
| `CODECOV_ENABLED` | External coverage upload | Disabled by default in forks; configure the integration before enabling |

Release orchestration requires all four of `FORK_RELEASE_ENABLED`,
`FORK_CI_ENABLED`, `FORK_PUBLISH_ENABLED` and `FORK_E2E_ENABLED` to be `true`.
Enabling release orchestration alone does not bypass its build and validation gates.

Fork publishing also requires explicit `OCI_REGISTRY_HOST`, `IMAGE_REPO_PREFIX`
and `HELM_OCI_REGISTRY`. GHCR paths must be under the repository owner's lowercase
namespace. `PUBLISH_LATEST` defaults off for forks. The initial deployment uses
upstream released artifacts; building a custom distribution is a separate decision.

Upstream's build recipes currently disable BuildKit SBOM and provenance output.
The upstream release signs images, but signing alone is not an SBOM or provenance
attestation. A custom distribution must add the required evidence and verify
image references in every published chart before promotion.

## Upstream synchronization

The `Propose Upstream Synchronization` workflow discovers the actual fork parent and its default
branch through GitHub. It merges upstream into a managed review branch and opens
or updates a draft PR. Conflicts fail the run for review; the workflow never
force-pushes or merges the default branch.

Use a scoped GitHub App installation for unattended automation where supported.
The App needs the permissions used by the workflow, including workflow-file
updates when upstream changes `.github/workflows`. Its installation and private
key remain with the existing secret owner. Do not copy an organization-wide
credential into this public repository.

With the default `GITHUB_TOKEN`, GitHub-created PR runs can require human workflow
approval, and workflow-file changes may require additional authorization. Treat
either as an explicit automation boundary. Verify an actual sync PR and its
checks before enabling the recurring schedule.

Upstream synchronization does not change the selected deployed release. Upgrade
`openchoreo_version`, chart configuration and required CLI/plugin versions through
a separate reviewed change, apply the documented CRD upgrade sequence, and test
staging before production.

## References

- [Mise tasks and tools](https://mise.jdx.dev/tasks/task-configuration.html)
- [Generated mise lockfiles](https://mise.jdx.dev/dev-tools/mise-lock.html)
- [Official quickstart](https://openchoreo.dev/docs/getting-started/quick-start-guide/)
- [GitHub workflow contexts](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts)
- [GitHub token behavior](https://docs.github.com/en/actions/concepts/security/github_token)
- [jactionlint releases](https://github.com/jdx/jactionlint/releases)
