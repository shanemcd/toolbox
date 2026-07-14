# Bootstrap a fresh CRC with Hermes (from scratch or from backup)

Stand up the full Hermes stack on a brand-new CRC instance. Works for
both a clean install and restoring from a GCS backup.

## What lives on the cluster

| Namespace | Component | Installed by |
|-----------|-----------|--------------|
| `openshift-cnv` | OpenShift Virtualization (KubeVirt) | OLM subscription + HyperConverged CR |
| `agent-sandbox-system` | agent-sandbox controller | `pin-crc-from-ghcr.sh` |
| `openshell` | OpenShell gateway (Helm) | Helm install, then pin script |
| `openshift-adp` | OADP operator (Velero + Kopia) | OLM subscription |
| `default` | Sandbox CR, VM, workspace PVC, secrets, signal-cli | Backup restore or manual create |

## Phase 1: CRC basics

```bash
crc start
eval $(crc oc-env)
export KUBECONFIG=~/.crc/machines/crc/kubeconfig
oc whoami   # expect: kubeadmin
```

## Phase 2: Install OpenShift Virtualization

```bash
# 1. Namespace + OperatorGroup + Subscription
oc create namespace openshift-cnv

oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kubevirt-hyperconverged-group
  namespace: openshift-cnv
spec:
  targetNamespaces:
    - openshift-cnv
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: hco-operatorhub
  namespace: openshift-cnv
spec:
  channel: stable
  name: kubevirt-hyperconverged
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

# 2. Wait for operator (this can take several minutes)
echo "Waiting for CNV operator..."
until oc get csv -n openshift-cnv 2>/dev/null | grep -q Succeeded; do
  sleep 15
done
echo "CNV operator ready"

# 3. Create HyperConverged CR to deploy KubeVirt
oc apply -f - <<'EOF'
apiVersion: hco.kubevirt.io/v1beta1
kind: HyperConverged
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec:
  virtualization:
    evictionStrategy: None
EOF

# 4. Wait for KubeVirt to be ready
echo "Waiting for KubeVirt..."
oc wait hyperconverged kubevirt-hyperconverged -n openshift-cnv \
  --for=condition=Available --timeout=600s
```

## Phase 3: Install the agent-sandbox controller + gateway

From the [openshell-kubevirt](https://github.com/shanemcd/openshell-kubevirt) repo:

```bash
# Pin controller + gateway to latest nightly digests
./scripts/pin-crc-from-ghcr.sh

# Apply KubeVirt RBAC (from the agent-sandbox fork checkout)
cd /path/to/agent-sandbox
kubectl apply -f k8s/kubevirt-rbac.generated.yaml -f k8s/kubevirt.yaml
```

If starting from scratch (no backup), install OpenShell via Helm first
(see the OpenShell repo for chart instructions), then pin the image.
If restoring from backup, the Helm release secrets and `openshell-config`
ConfigMap will be restored in Phase 5.

## Phase 4: Install OADP and connect to GCS

```bash
# 1. Namespace + operator
oc create namespace openshift-adp

oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-adp
  namespace: openshift-adp
spec:
  targetNamespaces:
    - openshift-adp
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: redhat-oadp-operator
  namespace: openshift-adp
spec:
  channel: stable
  name: redhat-oadp-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

# 2. Wait for operator
echo "Waiting for OADP operator..."
until oc get csv -n openshift-adp 2>/dev/null | grep -q Succeeded; do
  sleep 10
done
echo "OADP operator ready"

# 3. GCP credentials (export a fresh key if the old one was deleted)
#    gcloud iam service-accounts keys create /tmp/credentials-velero \
#      --iam-account velero@shanemcd-rh.iam.gserviceaccount.com
oc create secret generic cloud-credentials-gcp \
  -n openshift-adp \
  --from-file cloud=/tmp/credentials-velero

# 4. DataProtectionApplication
oc apply -f - <<'EOF'
apiVersion: oadp.openshift.io/v1alpha1
kind: DataProtectionApplication
metadata:
  name: hermes-dpa
  namespace: openshift-adp
spec:
  configuration:
    velero:
      defaultPlugins:
        - kubevirt
        - gcp
        - csi
        - openshift
      resourceTimeout: 10m
    nodeAgent:
      enable: true
      uploaderType: kopia
  backupLocations:
    - velero:
        provider: gcp
        default: true
        credential:
          key: cloud
          name: cloud-credentials-gcp
        objectStorage:
          bucket: shanemcd-rh-oadp-backups
          prefix: crc-hermes
EOF

# 5. Wait for BSL
oc wait backupstoragelocations.velero.io -n openshift-adp --all \
  --for=jsonpath='{.status.phase}'=Available --timeout=120s
```

## Phase 5a: Restore from backup

Velero auto-discovers backups in the GCS bucket once the BSL is Available.

```bash
# List available backups
oc get backups.velero.io -n openshift-adp

# Restore (replace <backup-name> with the name from the list)
oc apply -f - <<EOF
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: hermes-restore
  namespace: openshift-adp
spec:
  backupName: <backup-name>
  includedNamespaces:
    - default
    - openshell
  restorePVs: true
EOF

# Monitor
watch oc get restores.velero.io -n openshift-adp hermes-restore

# Verify
oc get sandbox hermes -n default
oc get pvc workspace-hermes -n default
oc get vm hermes -n default
openshell sandbox list
openshell sandbox provider list hermes
```

The controller will reconcile the restored Sandbox CR and create the VM.
The workspace PVC will be restored from GCS via Kopia and adopted by the
controller. Provider attaches are restored with the `openshell` namespace.

## Phase 5b: Create from scratch (no backup)

If there is no backup, create the Hermes sandbox manually. See the
[site README](README.md) for the full `openshell sandbox create` command
with all providers and env vars.

After create, deploy signal-cli:

```bash
oc create deploy signal-cli -n default \
  --image=registry.gitlab.com/packaging/signal-cli/signal-cli-native:latest
oc expose deploy signal-cli -n default --port=8080
oc set volumes deploy/signal-cli -n default \
  --add --name=data --type=pvc --claim-name=signal-cli-data \
  --claim-size=2Gi --mount-path=/home/.local/share/signal-cli
```

Then link the Signal account (see `signal/link.sh` in the openshell-kubevirt
repo).

## Phase 6: Smoke test

```bash
export OPENSHELL_GATEWAY=crc
unset OPENSHELL_GATEWAY_ENDPOINT

openshell gateway info
openshell sandbox list
openshell sandbox provider list hermes
# expect: github, slack, vertex-prod, atlassian, gws

# SSH (network-only mode; exec only works in combined mode)
virtctl ssh root@vmi/hermes -n default -i ~/.ssh/id_rsa \
  --local-ssh-opts="-oStrictHostKeyChecking=no" \
  --local-ssh-opts="-oUserKnownHostsFile=/dev/null" \
  --command='systemctl is-active openshell-sandbox && whoami'
```

## Ongoing backups

See [BACKUP.md](BACKUP.md) for creating backups. Quick one-shot:

```bash
oc apply -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: hermes-backup-$(date +%Y%m%d-%H%M)
  namespace: openshift-adp
spec:
  defaultVolumesToFsBackup: true
  includedNamespaces:
    - default
    - openshell
  ttl: 720h0m0s
EOF
```

For automatic daily backups:

```bash
oc apply -f - <<'EOF'
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: hermes-daily
  namespace: openshift-adp
spec:
  schedule: "0 6 * * *"
  template:
    defaultVolumesToFsBackup: true
    includedNamespaces:
      - default
      - openshell
    ttl: 720h0m0s
EOF
```

## Reference

| Resource | Location |
|----------|----------|
| GCP project | `shanemcd-rh` |
| GCS bucket | `gs://shanemcd-rh-oadp-backups` (us-central1) |
| GCP service account | `velero@shanemcd-rh.iam.gserviceaccount.com` |
| Controller image | `ghcr.io/shanemcd/agent-sandbox-controller:nightly` |
| Gateway image | `ghcr.io/shanemcd/openshell-gateway:nightly` |
| Hermes containerDisk | `ghcr.io/shanemcd/hermes-site-kubevirt:nightly` |
| agent-sandbox fork | `github.com/shanemcd/agent-sandbox` branch `kubevirt-backend` |
| OpenShell fork | `github.com/shanemcd/OpenShell` branch `vm-runtime-backend` |
