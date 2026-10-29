#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.4.2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_DIR="${ROOT_DIR}/release_v${VERSION}"
ARCHIVE="${ROOT_DIR}/release_v${VERSION}.tar.gz"

cd "$ROOT_DIR"

for command in docker tar sha256sum; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "ERROR: Required command not found: $command" >&2
        exit 1
    }
done

test -f docker-compose.yml
test -f models/manifest.json
test -f models/eo_detector_fp16.engine
test -f .env.example

echo "Validating Compose configuration..."
docker compose --env-file .env.example config --quiet

echo "Running unit tests..."
python3 -m unittest discover -s tests -v

echo "Verifying model checksum..."
python3 - <<'PY'
import hashlib
import json
from pathlib import Path

manifest = json.loads(Path("models/manifest.json").read_text())
actual = hashlib.sha256(
    Path("models/eo_detector_fp16.engine").read_bytes()
).hexdigest()

if actual != manifest.get("sha256"):
    raise SystemExit("ERROR: Model checksum does not match manifest")

print("Model checksum verified")
PY

echo "Building application images..."
docker compose --env-file .env.example build

echo "Preparing release directory..."
rm -rf "$RELEASE_DIR"
rm -f "$ARCHIVE"
mkdir -p "$RELEASE_DIR/images"

# Export each service's actual image, including locally built images.
docker compose config --format json |
python3 -c '
import json, sys
config = json.load(sys.stdin)
for name, service in config["services"].items():
    image = service.get("image")
    if not image and service.get("build"):
        image = "devops_challenge-" + name
    if not image:
        raise SystemExit("ERROR: No image reference for service: " + name)
    print("{} {}".format(name, image))
' > "$RELEASE_DIR/service-images.txt"


: > "$RELEASE_DIR/image-ids.txt"

while read -r service image_ref; do
    [[ -n "$service" && -n "$image_ref" ]] || continue

    docker image inspect "$image_ref" >/dev/null

    image_id="$(docker image inspect --format '{{.Id}}' "$image_ref")"
    printf '%s %s\n' "$service" "$image_id" >> "$RELEASE_DIR/image-ids.txt"

done < "$RELEASE_DIR/service-images.txt"

index=0
while read -r service image_ref; do
    [[ -n "$service" && -n "$image_ref" ]] || continue

    docker save -o "$RELEASE_DIR/images/image-${index}.tar" "$image_ref"
    index=$((index + 1))

done < "$RELEASE_DIR/service-images.txt"



cp docker-compose.yml "$RELEASE_DIR/"
cp .env.example "$RELEASE_DIR/"
cp -a models "$RELEASE_DIR/"
cp RUNBOOK.md "$RELEASE_DIR/"

cat > "$RELEASE_DIR/IMAGE-IMPORT.txt" <<'TXT'
Docker images are provided as images/image-N.tar archives.
Import them with: docker load -i images/image-N.tar
Use the image IDs in image-ids.txt to identify imported images.
Review docker-compose.yml and provide a target-specific .env before deployment.
TXT

# Create checksums for every release file except the checksum manifest itself.
(
    cd "$RELEASE_DIR"
    find . -type f ! -name SHA256SUMS -print0 \
        | sort -z \
        | xargs -0 sha256sum > SHA256SUMS
)

tar -czf "$ARCHIVE" -C "$ROOT_DIR" "$(basename "$RELEASE_DIR")"

echo "Release created: $ARCHIVE"
echo "Release file checksums:"
sha256sum "$ARCHIVE"
