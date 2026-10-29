#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <release_v1.4.2.tar.gz>" >&2
    exit 2
fi

ARCHIVE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
WORK_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

command -v tar >/dev/null 2>&1
command -v sha256sum >/dev/null 2>&1
command -v docker >/dev/null 2>&1

echo "Extracting release archive..."
tar -xzf "$ARCHIVE" -C "$WORK_DIR"

RELEASE_DIR="$WORK_DIR/release_v1.4.2"

if [[ ! -d "$RELEASE_DIR" || ! -f "$RELEASE_DIR/SHA256SUMS" ]]; then
    echo "ERROR: Release directory or SHA256SUMS is missing." >&2
    exit 1
fi

echo "Verifying release checksums..."
(
    cd "$RELEASE_DIR"
    sha256sum --check SHA256SUMS
)

echo "Checksums verified. Loading Docker images..."
while IFS= read -r image_file; do
    [[ -n "$image_file" ]] || continue
    docker load -i "$image_file"
done < <(find "$RELEASE_DIR/images" -maxdepth 1 -type f -name 'image-*.tar' | sort)

echo
echo "Images loaded. Release files are verified."
echo "Copy the verified release directory to the deployment location,"
echo "create a target-specific .env from .env.example, then run:"
echo "  docker compose up -d"
echo
echo "This script intentionally does not start services automatically."
echo "Review RUNBOOK.md and confirm target architecture and runtime compatibility first."
