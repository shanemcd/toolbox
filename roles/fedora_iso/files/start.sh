#!/bin/bash

set -x

# Check if FEDORA_ISO_SRC and FEDORA_ISO_DEST are set
if [ -z "$FEDORA_ISO_SRC" ] || [ -z "$FEDORA_ISO_DEST" ]; then
    echo "Error: Both FEDORA_ISO_SRC and FEDORA_ISO_DEST must be set."
    exit 1
fi

# Check if source path exists
if [ ! -e "$FEDORA_ISO_SRC" ]; then
    echo "Error: Source ISO path does not exist."
    exit 1
fi

mkksiso --ks /context/ks.cfg "${FEDORA_ISO_SRC}" "${FEDORA_ISO_DEST}"
