# Downstream Hermes (OpenShell / KubeVirt)

Private layers on top of the public lean bootc image from
[`shanemcd/openshell-kubevirt`](https://github.com/shanemcd/openshell-kubevirt).
Use this tree for site-specific guest config that should **not** go into the
agent-sandbox / public Hermes contribution.

**CI:** builds are centralized in the openshell-kubevirt
[nightly rebuild](https://github.com/shanemcd/openshell-kubevirt/actions/workflows/nightly-rebuild.yml)
(`build_site_hermes`, default on). This directory stays the source for
`Containerfile` / `guest/`; do not rely on the old toolbox
“Downstream Hermes images” workflow.

## Two images (yes, you need the containerDisk)

KubeVirt does **not** boot a bootc OCI image directly. The Sandbox
`containers[0].image` must be a **containerDisk**: a scratch image that
contains `/disk/*.qcow2`.

```text
ghcr.io/shanemcd/hermes-sandbox-bootc:nightly   # public lean OS (bootc)
        │  FROM + COPY guest overlays
        ▼
ghcr.io/shanemcd/hermes-site-bootc:latest       # this Containerfile (toolbox-owned)
        │  bootc-image-builder → qcow2
        │  Containerfile.disk (FROM scratch)
        ▼
ghcr.io/shanemcd/hermes-site-kubevirt:latest    # what CRC / create --from uses
```

Package names are intentionally **not** `hermes-sandbox-*` — those are the
public lean images. Site packages are `hermes-site-bootc` /
`hermes-site-kubevirt`.

Nightly pushes site images from **openshell-kubevirt** Actions. If GHCR
rejects the push, grant that repo **Write** under each package’s
Manage Actions access (packages may still be linked to this toolbox repo
from the first publish).

So after every meaningful guest change: **rebuild bootc layer → rebuild
containerDisk** (or wait for / dispatch nightly with `build_site_hermes`).
Pointing `openshell sandbox create --from` at the bootc image alone will
not work.

`policy.yaml` here is applied at create time (`--policy`), not baked into the
disk (OpenShell hot-reloads policy).

## Build bootc layer

```bash
cd openshell-kubevirt
podman build \
  --build-arg BASE_IMAGE=ghcr.io/shanemcd/hermes-sandbox-bootc:nightly \
  -t localhost/hermes-site-bootc:latest \
  -f Containerfile .
```

## Package containerDisk

Needs rootful podman + [bootc-image-builder](https://github.com/osbuild/bootc-image-builder)
(same path as the public nightly workflow):

```bash
# 1) Convert bootc → qcow2 (example; prefer the GH Action / bib action locally)
mkdir -p output disk
sudo podman run --rm -it --privileged \
  --pull=newer \
  --security-opt label=type:unconfined_t \
  -v "$PWD/bib-qcow2.toml:/config.toml:ro" \
  -v "$PWD/output:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 --rootfs ext4 --use-librepo=True \
  --config /config.toml \
  localhost/hermes-site-bootc:latest

cp output/qcow2/disk.qcow2 disk/fedora.qcow2   # path may vary by bib version

# 2) Wrap as containerDisk
podman build -t localhost/hermes-site-kubevirt:latest -f Containerfile.disk .
```

Then create / recreate Hermes with **all providers** (links are wiped on delete; do not skip):

```bash
openshell sandbox create \
  --name hermes \
  --from localhost/hermes-site-kubevirt:latest \
  --policy ./policy.yaml \
  --provider vertex-prod --provider slack --provider github --provider atlassian --provider gws --provider gitlab \
  --env "SIGNAL_HTTP_URL=http://signal-cli.default.svc.cluster.local:8080" \
  --env "SIGNAL_ACCOUNT=+1…" \
  --env "SIGNAL_ALLOWED_USERS=+1…" \
  --env "SLACK_ALLOWED_USERS=U…" \
  -- /usr/local/bin/nemoclaw-start-vm

# Always verify; attach any that are missing (Vertex inference can work without attach).
for p in github slack vertex-prod atlassian gws gitlab; do
  openshell sandbox provider attach hermes "$p" 2>/dev/null || true
done
openshell sandbox provider list hermes
```

Do not commit real Signal/Slack allowlist values; keep them on `--env` only
(Hermes `load_dotenv(override=True)` would otherwise fight baked placeholders).
Skip `discord` (image disables that platform).

## Layout

| Path | Role |
|------|------|
| `Containerfile` | Site CLIs + guest files on public bootc (no rust toolchain) |
| `Containerfile.disk` | Scratch + `/disk/fedora.qcow2` |
| `bib-qcow2.toml` | bootc-image-builder config |
| `guest/` | SOUL/docs + placeholder configs for jirahhh / gws / glab / kube |
| `guest/jirahhh-config.yaml` | → `/sandbox/.config/jirahhh/config.yaml` |
| `guest/gws-credentials.json` | → `/sandbox/.config/gws/credentials.json` |
| `guest/glab-config.yml` | → `/sandbox/.config/glab-cli/config.yml` |
| `guest/git-credential-openshell` | → `/usr/local/bin/git-credential-openshell` |
| `policy.yaml` | OpenShell network/FS policy for `--policy` |

## Site CLIs (baked here, not in public bootc)

| Tool | Install | Credentials |
|------|---------|-------------|
| `gh` | GitHub release → `/usr/local/bin` | `--provider github` |
| `glab` | GitLab release → `/usr/local/bin` | `--provider gitlab` + `glab-config.yml` |
| `gws` | `dnf install nodejs npm` + `npm i -g @googleworkspace/cli` | `--provider gws` + `gws-credentials.json` |
| `jirahhh` | pip into Hermes venv | `--provider atlassian` |
| `oc` / `kubectl` | OpenShift client tarball → `/usr/local/bin` | not wired (no kube proxy; `:6443` blocked by OpenShell SSRF) |

Public `hermes-sandbox-bootc` stays lean (Hermes runtime + supervisor + podman). Node/npm and the CLIs above live only in this site image.

`NEMOCLAW_SKIP_HERMES_CONFIG_INTEGRITY=1` is baked on `openshell-sandbox` /
`sandbox-workload` systemd drop-ins (and recorded in `.env`) so retained PVC
config mutations from Hermes onboarding do not fail-close startup. Needs a
NemoClaw `nemoclaw-start` that honors the env var.

## jirahhh / Atlassian

Bakes `guest/jirahhh-config.yaml` (Red Hat URL + `openshell:resolve` for
`JIRA_EMAIL` / `JIRA_API_TOKEN`). Create with `--provider atlassian`.

## Google Workspace (`gws`)

`guest/gws-credentials.json` uses `openshell:resolve:env:GWS_*`. Token refresh
POSTs to `oauth2.googleapis.com` use `request_body_credential_rewrite`.

```bash
gws auth login --readonly -s gmail,calendar
openshell provider create --name gws --type generic \
  --credential "GWS_CLIENT_ID=..." \
  --credential "GWS_CLIENT_SECRET=..." \
  --credential "GWS_REFRESH_TOKEN=..."
```

## GitLab (`glab`)

```bash
openshell provider create --name gitlab --type generic \
  --credential "GITLAB_TOKEN=..."
```

Override host at build time with `--build-arg GITLAB_HOST=...` and edit
`guest/glab-config.yml` (see `.example`).

Note: an existing `/sandbox` PVC keeps its tree; rootfs binaries update with
the disk, but `.config/*` only seeds on first PVC init.
