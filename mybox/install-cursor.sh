#!/usr/bin/env bash
set -euo pipefail

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) platform="linux-x64-rpm" ;;
  aarch64|arm64) platform="linux-arm64-rpm" ;;
  *) echo "Unsupported arch: $arch" >&2; exit 1 ;;
esac

page="$(curl -fsSL -A 'Mozilla/5.0' https://cursor.com/download)"

# Prefer new api2 URLs
url="$(printf '%s\n' "$page" \
  | grep -oE "https://api2\.cursor\.sh/updates/download/golden/${platform}/cursor/[^\"<]+" \
  | head -n1 || true)"

# Fallback for legacy versions
if [ -z "${url:-}" ]; then
  url="$(printf '%s\n' "$page" \
    | grep -oE 'https://downloads\.cursor\.com/production/[^"]+/linux/[^/]+/rpm/[^"]+\.rpm' \
    | grep -i "/${platform%*-rpm}/" \
    | sort -u | sort -V | tail -n1 || true)"
fi

[ -n "${url:-}" ] || { echo "Could not find RPM link on download page." >&2; exit 1; }

echo "Downloading: $url"

# Make a temp directory for the download
tmpdir="$(mktemp -d)"
echo "Download directory: $tmpdir"

# Determine filename from Content-Disposition header
fname="$(curl -fsSLI "$url" \
  | awk -F'filename=' 'tolower($0) ~ /^content-disposition:/ {sub(/;.*/,"",$2); gsub(/"/,"",$2); print $2}' \
  | tr -d '\r')"
: "${fname:=cursor.rpm}"

# Download there
curl -fL -o "${tmpdir}/${fname}" "$url"

echo "Saved RPM as: ${tmpdir}/${fname}"

rpm -qip "${tmpdir}/${fname}" >/dev/null || {
  echo "Downloaded file isn't a valid RPM." >&2
  exit 1
}

# Install
if command -v rpm-ostree >/dev/null 2>&1; then
  sudo rpm-ostree install "${tmpdir}/${fname}"
  echo "Reboot required to finalize rpm-ostree install."
else
  sudo dnf install -y "${tmpdir}/${fname}"
fi
