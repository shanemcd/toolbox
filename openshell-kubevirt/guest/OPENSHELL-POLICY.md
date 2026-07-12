# OpenShell policy — Hermes instructions

You run inside an OpenShell sandbox. Outbound network and which binaries may dial which hosts are enforced by **sandbox policy**. Credentials may be rewritten at the proxy; missing policy shows up as `DENIED` / `NET:FAIL` in supervisor logs, not as a normal HTTP 403 from the site.

Canonical YAML for this CRC Hermes image: repo `shanemcd/openshell-kubevirt` → [`hermes/policy.yaml`](./policy.yaml).

## Who can change policy

| Where | Tool | Notes |
|-------|------|--------|
| Owner workstation / CRC host | `openshell policy …` | Preferred. Needs `OPENSHELL_GATEWAY=crc` (or a gateway endpoint). |
| Inside this VM | Same CLI if installed | Gateway: in-cluster OpenShell service. |
| You (Hermes) without `openshell` | Diagnose + propose YAML / `policy update` args | Ask Shane to apply, or apply yourself once `openshell` is on `PATH`. |

Policy hot-reloads — **no sandbox restart** for network rule changes. Do **not** shrink `filesystem_policy` on a live sandbox (OpenShell rejects shrinking RO/RW sets).

## View current policy

```bash
export OPENSHELL_GATEWAY=crc
unset OPENSHELL_GATEWAY_ENDPOINT

# Human-readable summary
openshell policy get hermes

# Full effective policy (includes provider-composed `_provider_*` rules)
openshell policy get hermes --full

# Machine-readable
openshell policy get hermes --full -o json

# Base policy only (no provider overlays)
openshell policy get hermes --base -o json

# History / older revision
openshell policy list hermes
openshell policy get hermes --rev N --full
```

Useful JSON peek (network rule names + hosts):

```bash
openshell policy get hermes --full -o json | python3 -c '
import json,sys
p=json.load(sys.stdin)["policy"]
for name, rule in (p.get("network_policies") or {}).items():
    hosts=[e.get("host") for e in rule.get("endpoints") or []]
    bins=[b.get("path") for b in rule.get("binaries") or []]
    print(f"{name}: hosts={hosts} bins={bins}")
'
```

## Diagnose blocks (from this VM)

```bash
export PATH=/sandbox/bin:/sandbox/.hermes/bin:$PATH
export KUBECONFIG=/sandbox/.kube/config
export HOME=/sandbox

virtctl ssh root@vmi/hermes -n default \
  --local-ssh-opts='-i/sandbox/.ssh/id_ed25519' \
  --local-ssh-opts='-oStrictHostKeyChecking=no' \
  --local-ssh-opts='-oBatchMode=yes' \
  -c 'journalctl -u openshell-sandbox --since "15 min ago" --no-pager | grep -iE "DENIED|NET:FAIL|ALLOWED"'
```

How to read lines:

| Log | Meaning |
|-----|---------|
| `DENIED … reason:endpoint X:port is not allowed by any policy` | Add a `network_policies` endpoint (and binary). |
| `DENIED … engine:ssrf … port 6443` | Hard block — do **not** try to allow `:6443`. Use an in-cluster proxy on another port (see `kube-proxy/`). |
| `ALLOWED` then `NET:FAIL` | Policy permitted the dial; upstream/proxy still failed (TLS, rewrite, routing). |
| `DENIED … failed to resolve peer binary` | Short-lived connect; retry or ensure the binary path is listed. |

## Manage entries

### A. Incremental update (preferred for one host)

```bash
export OPENSHELL_GATEWAY=crc
unset OPENSHELL_GATEWAY_ENDPOINT

# host:port[:access[:protocol[:enforcement]]]
openshell policy update hermes --wait \
  --rule-name myapi \
  --add-endpoint 'api.example.com:443:full:rest:enforce' \
  --binary /opt/hermes/.venv/bin/python \
  --binary /usr/bin/curl

# Optional path allow/deny (REST)
openshell policy update hermes --wait \
  --add-allow 'api.example.com:443:GET:/v1/**'

# Remove
openshell policy update hermes --wait --remove-endpoint 'api.example.com:443'
openshell policy update hermes --wait --remove-rule myapi

# Preview only
openshell policy update hermes --dry-run \
  --add-endpoint 'api.example.com:443:full:rest:enforce' \
  --binary /usr/bin/curl
```

Access values: `full`, `read-only`, `read-write` (as accepted by your OpenShell version).  
Protocols: `rest` (HTTPS L7 / credential rewrite), `websocket`, or omit for coarse TCP allow when appropriate.

### B. Full replace from YAML

Edit `hermes/policy.yaml` (keep existing rules; live apply cannot shrink filesystem lists), then:

```bash
openshell policy set hermes --policy /path/to/hermes/policy.yaml --wait
```

### C. YAML shape for a network rule

```yaml
network_policies:
  myapi:
    name: myapi
    endpoints:
      - host: api.example.com          # or "*.example.com"
        port: 443
        protocol: rest                 # use for HTTPS + placeholder rewrite
        enforcement: enforce
        access: full
    binaries:
      - path: /opt/hermes/.venv/bin/python
      - path: /usr/bin/curl
      - path: /sandbox/.hermes/bin/mytool   # Landlock: install under /sandbox
      - path: /sandbox/**/bin/mytool        # glob OK
```

## Rules of thumb (CRC Hermes)

1. **Binary identity** — the path that appears in `DENIED` / `ALLOWED` logs must be listed under `binaries` (resolve symlinks; venv `python` → often `/usr/bin/python3.13`).
2. **Landlock** — `/usr` and `/usr/local` are read-only. Install CLIs under `/sandbox/.hermes/bin` (or `/sandbox/bin`) and allow those paths.
3. **GitHub releases** — allow `github.com`, `api.github.com`, and `*.githubusercontent.com` (CDN redirects). Attach the `github` provider if using `openshell:resolve:` tokens.
4. **Kube API** — never dial `:6443` from the sandbox. Use `http://hermes-kube-proxy.default.svc.cluster.local:8080` (`kubernetes` rule + `oc`/`virtctl` binaries). See [`kube-proxy/README.md`](../kube-proxy/README.md).
5. **In-cluster HTTP services** — same pattern as Signal: `host: name.ns.svc.cluster.local`, `port: 8080`, `protocol: rest`.
6. **Providers** — `openshell sandbox provider attach` adds `_provider_*` policy overlays; `--full` shows them. Placeholders only rewrite when the provider is attached and the header/body uses `openshell:resolve:env:KEY`.
7. **Persist** — after a working live `policy update` / `set`, copy the same change into `hermes/policy.yaml` in git so the next recreate matches.

## Workflow when you are blocked

1. Reproduce once; capture `DENIED` / `NET:FAIL` lines (virtctl + `journalctl` above).
2. Identify **host**, **port**, and **binary path**.
3. Propose either an `openshell policy update …` command or a YAML snippet for `hermes/policy.yaml`.
4. Apply (`--wait`), retest, then remind Shane to commit the YAML if it should stick.

Do not suggest opening port **6443**, PyPI/npm “just whitelist everything”, or writing tools into `/usr/local` under Landlock.
