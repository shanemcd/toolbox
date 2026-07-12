#!/usr/bin/env python3
"""Update NemoClaw config hashes after modifying config.yaml and .env.

Computes SHA256 hashes for config.yaml, .env, and the canonicalized
mcp_servers section, then writes the hash file in the format NemoClaw
expects. Run as root at image build time.
"""
import hashlib
import json
import sys

import yaml

HERMES_DIR = "/sandbox/.hermes"
HASH_FILES = [
    "/etc/nemoclaw/hermes.config-hash",
    f"{HERMES_DIR}/.config-hash",
]


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def mcp_digest(config_path):
    with open(config_path) as f:
        parsed = yaml.safe_load(f)
    servers = parsed.get("mcp_servers") or {}
    canonical = json.dumps(
        servers, allow_nan=False, ensure_ascii=True,
        sort_keys=True, separators=(",", ":"),
    ).encode()
    return hashlib.sha256(canonical).hexdigest()


def main():
    config_path = f"{HERMES_DIR}/config.yaml"
    env_path = f"{HERMES_DIR}/.env"

    config_hash = sha256_file(config_path)
    env_hash = sha256_file(env_path)
    mcp_hash = mcp_digest(config_path)

    content = (
        f"{config_hash}  {config_path}\n"
        f"{env_hash}  {env_path}\n"
        f"# nemoclaw-hermes-mcp-state-v1 intended={mcp_hash} applied={mcp_hash}\n"
    )

    for path in HASH_FILES:
        with open(path, "w") as f:
            f.write(content)

    print(f"config: {config_hash[:16]}...")
    print(f"env:    {env_hash[:16]}...")
    print(f"mcp:    {mcp_hash[:16]}...")


if __name__ == "__main__":
    main()
