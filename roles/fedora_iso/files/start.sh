#!/bin/bash

set -x

# Check for FEDORA_ISO_PATH environment variable
if [ -z "${FEDORA_ISO_PATH}" ]; then
  echo "Error: FEDORA_ISO_PATH environment variable is not set."
  exit 1
fi

FEDORA_ISO_DIR=$(dirname "${FEDORA_ISO_PATH}")
FEDORA_ISO_FILE_NAME=$(basename "${FEDORA_ISO_PATH}")

mkksiso --ks /context/ks.cfg ${FEDORA_ISO_DIR}/${FEDORA_ISO_FILE_NAME} ${FEDORA_ISO_DIR}/ks-${FEDORA_ISO_FILE_NAME}
