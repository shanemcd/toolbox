#!/usr/bin/env bash
set -euo pipefail

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)
    ARCH_TAG="amd64"
    ;;
  aarch64 | arm64)
    ARCH_TAG="arm64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

# Download and extract
curl -fsSL -o podman-static.tar.gz \
  "https://github.com/mgoltzsche/podman-static/releases/download/v5.6.2/podman-linux-${ARCH_TAG}.tar.gz"

tar -xzf podman-static.tar.gz

# Set extracted directory name
EXTRACTED_DIR="podman-linux-${ARCH_TAG}"

# Install binaries and support files
cp -r "${EXTRACTED_DIR}/usr/"* /usr/
cp -r "${EXTRACTED_DIR}/etc/"* /etc/

# Clean up
rm -rf podman-static.tar.gz "${EXTRACTED_DIR}"

# https://github.com/containers/podman/issues/9164
rm /dev/shm/libpod_lock

# Avoids `Error: OCI runtime error: crun: unknown version specified`
echo -e "[engine]\nruntime = \"runc\"" > /etc/containers/containers.conf

# Verify install
podman --version
podman info
