#!/bin/bash

# Check for FEDORA_ISO_LINK environment variable
if [ -z "${FEDORA_ISO_LINK}" ]; then
  echo "Error: FEDORA_ISO_LINK environment variable is not set."
  exit 1
fi

# Default output directory, can be overridden by FEDORA_ISO_OUTPUT_DIR env var
OUTPUT_DIR="/tmp"

# Check if custom output directory is specified in the environment variables
if [ -n "${FEDORA_ISO_OUTPUT_DIR}" ]; then
  OUTPUT_DIR="${FEDORA_ISO_OUTPUT_DIR}"
fi

# Extract file name from URL using parameter expansion
FILE_NAME=$(basename "${FEDORA_ISO_LINK}")

wget --directory-prefix "${FEDORA_ISO_OUTPUT_DIR}" "$FEDORA_ISO_LINK"

# Print completion message
echo "Fedora ISO downloaded successfully to ${OUTPUT_DIR}/${FILE_NAME}"

sleep infinity
