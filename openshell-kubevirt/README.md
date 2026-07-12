# Downstream Hermes (OpenShell / KubeVirt)

Private layers on top of the public lean bootc image from
[`shanemcd/openshell-kubevirt`](https://github.com/shanemcd/openshell-kubevirt).
Use this tree for site-specific guest config that should **not** go into the
agent-sandbox / public Hermes contribution.

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

Package names are intentionally **not** `hermes-sandbox-*` — those GHCR packages are owned by `openshell-kubevirt` and this repo’s `GITHUB_TOKEN` cannot push to them.

So after every meaningful guest change: **rebuild bootc layer → rebuild
containerDisk**. Pointing `openshell sandbox create --from` at the bootc
image alone will not work.

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

Then create / recreate Hermes with:

```bash
openshell sandbox create \
  --name hermes \
  --from localhost/hermes-site-kubevirt:latest \
  --policy ./policy.yaml \
  --provider vertex-prod --provider slack --provider github --provider atlassian \
  --env "SIGNAL_HTTP_URL=http://signal-cli.default.svc.cluster.local:8080" \
  --env "SIGNAL_ACCOUNT=+1…" \
  --env "SIGNAL_ALLOWED_USERS=+1…" \
  --env "SLACK_ALLOWED_USERS=U…" \
  -- /usr/local/bin/nemoclaw-start-vm
```

Do not commit real Signal/Slack allowlist values; keep them on `--env` only
(Hermes `load_dotenv(override=True)` would otherwise fight baked placeholders).

## Layout

| Path | Role |
|------|------|
| `Containerfile` | Layer guest files onto public bootc |
| `Containerfile.disk` | Scratch + `/disk/fedora.qcow2` |
| `bib-qcow2.toml` | bootc-image-builder config |
| `guest/` | Files copied into `/sandbox/.hermes/` (+ jirahhh config) |
| `guest/jirahhh-config.yaml` | Baked to `/sandbox/.config/jirahhh/config.yaml` (placeholders) |
| `policy.yaml` | OpenShell network/FS policy for `--policy` |

## jirahhh / Atlassian

The Containerfile installs `jirahhh` into the Hermes venv and bakes
`guest/jirahhh-config.yaml` (Red Hat URL + `openshell:resolve` for
`JIRA_EMAIL` / `JIRA_API_TOKEN`). Create with `--provider atlassian` so the
gateway can rewrite Basic auth. Policy allows `*.atlassian.net`.

GitHub CLI (`gh` v2.96.0) is installed to `/usr/local/bin/gh` (allowed by
`policy.yaml` github binaries). Use `--provider github` for token rewrite.
