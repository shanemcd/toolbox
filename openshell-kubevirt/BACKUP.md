# CRC Backup and Restore (OADP + GCS)

Back up the Hermes VM workspace and cluster state to Google Cloud Storage
using OADP (Velero + Kopia). Restore onto a completely fresh CRC cluster.

To **grow** the live workspace on CRC hostpath (no CSI expansion), see
[`GROW-WORKSPACE-PVC.md`](./GROW-WORKSPACE-PVC.md) — that is a local PVC clone
cutover, not an OADP backup.

## What gets backed up

| Data | Source | Notes |
|------|--------|-------|
| `/sandbox` workspace (PVC) | `workspace-hermes` PVC in `default` | Hermes agent state, configs, conversation history |
| Sandbox CR | `default` namespace | Controller recreates the VM from this |
| Secrets | `default` namespace | TLS certs, SA tokens, metadata |
| OpenShell gateway state | `openshell` namespace | Provider attaches, gateway config |

The containerDisk (root filesystem) is **not** backed up. It is ephemeral and
pulled from GHCR on every VM start. The controller, gateway, and KubeVirt are
infrastructure that gets reinstalled separately.

CRC uses `hostpath-provisioner` which has no CSI snapshot support, so backups
use Kopia filesystem-level copy (`defaultVolumesToFsBackup: true`) instead of
CSI snapshots.

## Prerequisites

- `gcloud` CLI authenticated (`gcloud auth login`)
- GCP project: `shanemcd-rh`
- GCS bucket: `shanemcd-rh-oadp-backups` (us-central1)
- GCP service account: `velero@shanemcd-rh.iam.gserviceaccount.com`

## One-time GCP setup

Already done. For reference, the bucket, service account, IAM role, and key
were created with:

```bash
export PROJECT_ID=shanemcd-rh
export BUCKET=shanemcd-rh-oadp-backups

gcloud storage buckets create gs://$BUCKET --project=$PROJECT_ID --location=us-central1

gcloud iam service-accounts create velero \
  --project=$PROJECT_ID \
  --display-name "Velero service account"

SERVICE_ACCOUNT_EMAIL=$(gcloud iam service-accounts list \
  --project=$PROJECT_ID \
  --filter="displayName:Velero service account" \
  --format 'value(email)')

ROLE_PERMISSIONS=(
  compute.disks.get compute.disks.create compute.disks.createSnapshot
  compute.snapshots.get compute.snapshots.create compute.snapshots.useReadOnly
  compute.snapshots.delete compute.zones.get
  storage.objects.create storage.objects.delete storage.objects.get storage.objects.list
  iam.serviceAccounts.signBlob
)

gcloud iam roles create velero.server \
  --project=$PROJECT_ID \
  --title "Velero Server" \
  --permissions "$(IFS=","; echo "${ROLE_PERMISSIONS[*]}")"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member serviceAccount:$SERVICE_ACCOUNT_EMAIL \
  --role projects/$PROJECT_ID/roles/velero.server

gsutil iam ch serviceAccount:$SERVICE_ACCOUNT_EMAIL:objectAdmin gs://$BUCKET

gcloud iam service-accounts keys create /tmp/credentials-velero \
  --iam-account $SERVICE_ACCOUNT_EMAIL
```

## Install OADP on a fresh CRC

```bash
export KUBECONFIG=~/.crc/machines/crc/kubeconfig

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
oc wait csv -n openshift-adp -l operators.coreos.com/redhat-oadp-operator.openshift-adp \
  --for=jsonpath='{.status.phase}'=Succeeded --timeout=300s

# 3. GCP credentials Secret (export a fresh key if needed)
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

# 5. Wait for BackupStorageLocation
oc wait backupstoragelocations.velero.io -n openshift-adp --all \
  --for=jsonpath='{.status.phase}'=Available --timeout=120s
```

## Create a backup

```bash
oc apply -f - <<'EOF'
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

Monitor progress:

```bash
# Overall status
oc get backups.velero.io -n openshift-adp -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,ITEMS:.status.progress.itemsBackedUp

# PVC upload progress (the workspace PVC is ~2GB)
oc get podvolumebackups -n openshift-adp \
  -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,BYTES:.status.progress.bytesDone,TOTAL:.status.progress.totalBytes
```

Expect 5-10 minutes depending on PVC size and upload speed.

## Restore on a fresh CRC

On the new cluster, install OADP and point it at the same GCS bucket (steps
1-5 from "Install OADP on a fresh CRC" above). Once the BSL is Available,
Velero automatically discovers existing backups in the bucket.

```bash
# 1. Verify the backup is visible
oc get backups.velero.io -n openshift-adp

# 2. Install prerequisites (controller, gateway, KubeVirt RBAC)
#    from the openshell-kubevirt repo:
./scripts/pin-crc-from-ghcr.sh
kubectl apply -f k8s/kubevirt-rbac.generated.yaml -f k8s/kubevirt.yaml

# 3. Restore
oc apply -f - <<'EOF'
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

# 4. Monitor
oc get restores.velero.io -n openshift-adp hermes-restore -o jsonpath='{.status.phase}'
# expect: Completed

# 5. Verify
oc get sandbox hermes -n default
oc get pvc workspace-hermes -n default
openshell sandbox list
openshell sandbox provider list hermes
```

The controller will reconcile the restored Sandbox CR and create the VM.
The restored `workspace-hermes` PVC will be adopted and attached. A
`virtctl restart` may be needed if the VM doesn't pick up the PVC
automatically.

## Notes

- Backups use `defaultVolumesToFsBackup: true` because CRC's
  `hostpath-provisioner` has no CSI snapshot support. On a cluster with
  ODF/Ceph, switch to `snapshotMoveData: true` for faster, block-level
  backups.
- The `ttl: 720h0m0s` (30 days) controls how long backups are retained in
  GCS. Expired backups are garbage-collected by Velero.
- Controller-generated resources (VirtualMachine, metadata Secret, SA token)
  are recreated from the Sandbox CR. They are included in the backup for
  completeness but are not strictly required.
- Provider attaches live in the `openshell` namespace. If you restore only
  `default`, you will need to re-attach providers manually.
- SSH host keys change on every VM restart (containerDisk is ephemeral).
  Always use `-oUserKnownHostsFile=/dev/null` with `virtctl ssh`.
- To list what is in the GCS bucket:
  `gsutil ls gs://shanemcd-rh-oadp-backups/crc-hermes/`
