#!/usr/bin/env bash
set -euo pipefail

install_dir="${1:-/usr/local/bin}"

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) platform="x64" ;;
  aarch64|arm64) platform="arm64" ;;
  *) echo "Unsupported arch: $arch" >&2; exit 1 ;;
esac

page="$(curl -fsSL https://cursor.com/install)"

version="$(printf '%s\n' "$page" | grep -oP '(?<=lab/)[^/]+' | head -1)"
[ -n "${version:-}" ] || { echo "Could not determine cursor-agent version." >&2; exit 1; }

url="https://downloads.cursor.com/lab/${version}/linux/${platform}/agent-cli-package.tar.gz"
echo "Downloading: $url"

mkdir -p "$install_dir"
curl -fSL "$url" | tar --strip-components=1 -xzf - -C "$install_dir"

echo "Cursor Agent version: ${version}"
