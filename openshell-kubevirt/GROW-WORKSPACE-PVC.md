# Grow Hermes workspace PVC (CRC hostpath)

CRC’s `crc-csi-hostpath-provisioner` does **not** support CSI volume
expansion (`allowVolumeExpansion: false`). A normal
`oc patch pvc … /spec/resources/requests/storage` will not enlarge the guest
disk. Status `capacity` on hostpath claims is also misleading (often huge);
trust what the guest sees on `/dev/vdc` / `df -h /sandbox`.

This runbook is how we grew live Hermes from the original VCT claim
(`workspace-hermes`, 2Gi) to a named passthrough claim
(`workspace-hermes-20gi`, 20Gi) on **2026-07-14**, without wiping `/sandbox`.

Related: cluster disaster backup is [`BACKUP.md`](./BACKUP.md) (OADP/GCS).
Product-side notes also live in
[`openshell-kubevirt` REDEPLOY §2c](https://github.com/shanemcd/openshell-kubevirt/blob/main/REDEPLOY.md).

## Prerequisites

```bash
export KUBECONFIG=~/.crc/machines/crc/kubeconfig
export OPENSHELL_GATEWAY=crc
unset OPENSHELL_GATEWAY_ENDPOINT
```

- agent-sandbox controller that supports **named PVC passthrough sync**
  (`syncVMPersistentVolumeClaims` / prefer
  `podTemplate.spec.volumes[].persistentVolumeClaim.claimName` over VCT).
- For **new** sandboxes: OpenShell gateway/CLI with `--workspace-pvc` (or
  `kubernetes.workspace_pvc` in driver config). Live cutover only needs an
  `oc` patch of the Sandbox CR once the controller can sync claimNames.
- Enough free host disk for a second claim of the target size.

## Critical KubeVirt detail

Workspace PVCs used by KubeVirt are **filesystem PVCs that hold a raw
`disk.img`**, not a directory tree of guest files.

So:

1. `rsync` old PVC → new PVC copies **`disk.img`** (still the old virtual size).
2. Grow the raw image: `qemu-img resize … 20G`.
3. Grow the ext filesystem inside the image offline: `losetup` + `e2fsck` +
   `resize2fs`.

Skipping steps 2–3 leaves a 20Gi PVC that still presents ~2G to the guest.

Jobs that touch these volumes need **`privileged: true`** and `runAsUser: 0`
on CRC (otherwise permission denied on `disk.img`).

## Phase 1 — Stop Hermes and free the RWO claim

The controller will set `spec.running=true` again if left up. Scale it down
for the whole clone/resize window.

```bash
oc -n agent-sandbox-system scale deploy/agent-sandbox-controller --replicas=0
virtctl stop hermes -n default

# Wait until VMI is gone and VM is stopped
for i in $(seq 1 60); do
  phase=$(oc -n default get vmi hermes -o jsonpath='{.status.phase}' 2>/dev/null || echo Gone)
  run=$(oc -n default get vm hermes -o jsonpath='{.spec.running}' 2>/dev/null)
  echo "try=$i phase=$phase running=$run"
  if { [ "$phase" = "Gone" ] || [ -z "$phase" ]; } && [ "$run" = "false" ]; then
    break
  fi
  [ "$run" = "true" ] && virtctl stop hermes -n default || true
  sleep 3
done
```

Confirm no pod still mounts `workspace-hermes` (especially leftover Jobs).

## Phase 2 — Create the larger claim

```bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: workspace-hermes-20gi
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: crc-csi-hostpath-provisioner
  resources:
    requests:
      storage: 20Gi
EOF

# WaitForFirstConsumer: may stay Pending until a consumer exists — that is OK.
# It binds when the rsync Job starts.
oc -n default get pvc workspace-hermes workspace-hermes-20gi
```

Keep **`workspace-hermes`** as backup until the guest is verified on the new
claim. Do not delete it in this phase.

## Phase 3 — Rsync `disk.img` (privileged Job)

Both claims are RWO: VM must stay stopped; only one Job may mount them.

```bash
oc -n default delete job hermes-workspace-rsync --ignore-not-found
oc apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: hermes-workspace-rsync
  namespace: default
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: rsync
        image: public.ecr.aws/docker/library/alpine:3.20
        securityContext:
          privileged: true
          runAsUser: 0
        command:
        - /bin/sh
        - -c
        - |
          set -eux
          apk add --no-cache rsync
          echo "=== source ==="
          du -sh /from
          ls -la /from | head -30
          echo "=== rsync ==="
          rsync -aHAX --info=progress2 /from/ /to/
          echo "=== dest ==="
          du -sh /to
          ls -la /to | head -30
          test -f /to/disk.img
          echo DONE
        volumeMounts:
        - name: from
          mountPath: /from
        - name: to
          mountPath: /to
      volumes:
      - name: from
        persistentVolumeClaim:
          claimName: workspace-hermes
      - name: to
        persistentVolumeClaim:
          claimName: workspace-hermes-20gi
EOF

oc -n default wait --for=condition=complete job/hermes-workspace-rsync --timeout=30m
oc -n default logs job/hermes-workspace-rsync --tail=40
oc -n default delete job hermes-workspace-rsync
```

Expect `/from` and `/to` to show a large `disk.img`, not a `.hermes/` tree.

## Phase 4 — Grow the raw image

```bash
oc -n default delete job hermes-workspace-resize --ignore-not-found
oc apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: hermes-workspace-resize
  namespace: default
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: resize
        image: quay.io/kubevirt/virt-launcher:v1.4.0
        securityContext:
          privileged: true
          runAsUser: 0
        command:
        - /bin/bash
        - -c
        - |
          set -eux
          ls -la /data
          qemu-img info /data/disk.img
          qemu-img resize /data/disk.img 20G
          qemu-img info /data/disk.img
          echo RESIZE_DONE
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: workspace-hermes-20gi
EOF

oc -n default wait --for=condition=complete job/hermes-workspace-resize --timeout=20m
oc -n default logs job/hermes-workspace-resize --tail=40
oc -n default delete job hermes-workspace-resize
```

Pin a `virt-launcher` tag that matches your CRC KubeVirt version if `v1.4.0`
is missing; any image with `qemu-img` works.

## Phase 5 — Offline `resize2fs` inside `disk.img`

On this layout the filesystem is **whole-disk ext** on the raw image (no
partition table). Use `losetup` without assuming `p1`.

```bash
oc -n default delete job hermes-workspace-growfs --ignore-not-found
oc apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: hermes-workspace-growfs
  namespace: default
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: growfs
        image: public.ecr.aws/docker/library/alpine:3.20
        securityContext:
          privileged: true
          runAsUser: 0
        command:
        - /bin/sh
        - -c
        - |
          set -eux
          apk add --no-cache e2fsprogs e2fsprogs-extra util-linux
          ls -la /data
          LOOP=$(losetup -f --show -P /data/disk.img)
          lsblk "$LOOP"
          blkid "$LOOP" || true
          e2fsck -fy "$LOOP"
          resize2fs "$LOOP"
          tune2fs -l "$LOOP" | grep -E 'Block count|Block size|Filesystem volume'
          losetup -d "$LOOP"
          echo GROWFS_DONE
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: workspace-hermes-20gi
EOF

oc -n default wait --for=condition=complete job/hermes-workspace-growfs --timeout=20m
oc -n default logs job/hermes-workspace-growfs --tail=40
oc -n default delete job hermes-workspace-growfs
```

If `lsblk` shows a partition (`${LOOP}p1`), grow that partition first
(`growpart`) and run `e2fsck`/`resize2fs` on the partition device instead.

## Phase 6 — Point Sandbox at the named claim

Still with the controller scaled to 0 and the VM stopped:

1. Remove `spec.volumeClaimTemplates` (so reconcile does not keep recreating
   `workspace-hermes`).
2. Set `podTemplate.spec.volumes` entry `workspace` →
   `persistentVolumeClaim.claimName: workspace-hermes-20gi`.
3. Keep `volumeMounts` `workspace` → `/sandbox` on the first container.
4. Preserve all other env / mounts (TLS, SA token, Signal, etc.).

Example replace flow used on CRC:

```bash
oc -n default get sandbox hermes -o json > /tmp/hermes-sb.json
python3 <<'PY'
import json
with open("/tmp/hermes-sb.json") as f:
    s = json.load(f)
s.pop("status", None)
md = s["metadata"]
for k in ("managedFields", "resourceVersion", "uid", "generation", "creationTimestamp"):
    md.pop(k, None)
spec = s["spec"]
spec.pop("volumeClaimTemplates", None)
pt = spec.setdefault("podTemplate", {}).setdefault("spec", {})
vols = pt.setdefault("volumes", [])
found = False
for v in vols:
    if v.get("name") == "workspace":
        v.clear()
        v["name"] = "workspace"
        v["persistentVolumeClaim"] = {"claimName": "workspace-hermes-20gi"}
        found = True
        break
if not found:
    vols.append({
        "name": "workspace",
        "persistentVolumeClaim": {"claimName": "workspace-hermes-20gi"},
    })
with open("/tmp/hermes-sb-patched.json", "w") as f:
    json.dump(s, f)
print([v for v in vols if v.get("name") == "workspace"])
PY
oc replace -f /tmp/hermes-sb-patched.json
```

## Phase 7 — Scale controller back up and verify

```bash
oc -n agent-sandbox-system scale deploy/agent-sandbox-controller --replicas=1
oc -n agent-sandbox-system rollout status deploy/agent-sandbox-controller --timeout=180s

# Controller should sync VM claimName then resume running=true
oc -n default get vm hermes -o jsonpath='claim={.spec.template.spec.volumes[?(@.name=="workspace")].persistentVolumeClaim.claimName} running={.spec.running} status={.status.printableStatus}{"\n"}'
oc -n default get vmi hermes -o wide
```

Guest check (after SSH works again — re-inject authorized keys via QGA if the
VM was recreated):

```bash
virtctl ssh root@vmi/hermes -n default --local-ssh-opts="-F/tmp/ssh_config_hermes" -c '
df -h /sandbox
ls -la /sandbox/.hermes | head
systemctl is-active openshell-sandbox sandbox-workload
'
```

Expect `df -h /sandbox` ≈ **20G** with `.hermes/` present. Only then consider
deleting the old `workspace-hermes` backup claim.

## New creates (after OpenShell `--workspace-pvc` lands)

```bash
openshell sandbox create \
  --name hermes \
  --workspace-pvc workspace-hermes-20gi \
  --from "$IMAGE" \
  ...
# or:
# --driver-config-json '{"kubernetes":{"workspace_pvc":"workspace-hermes-20gi"}}'
```

That omits VCT and emits the PVC volume + `/sandbox` mount. Sandbox delete
does **not** delete a passthrough claim (unlike the VCT-owned
`workspace-<name>` claim).

## Gotchas we hit

| Issue | Fix |
|-------|-----|
| Controller restarts a stopped VM mid-rsync | Scale `agent-sandbox-controller` to 0 for the whole clone/resize |
| Non-privileged rsync → permission denied | `privileged: true`, `runAsUser: 0` |
| Rsync “succeeds” but guest still 2G | You only copied `disk.img`; still need `qemu-img resize` + `resize2fs` |
| WaitForFirstConsumer PVC Pending | Normal until the Job mounts it |
| SSH fails after long stop/restart | Re-add authorized key via QGA on the virt-launcher domain |
| Empty `hermes-meta` env after VM recreate | Sandbox CR must keep env + volumeMounts; meta is only written on VM create |

## Current CRC state (after 2026-07-14 cutover)

- Live claim: `workspace-hermes-20gi`
- Backup claim: `workspace-hermes` (safe to delete only after you no longer need it)
- Sandbox: named PVC passthrough, no workspace VCT
