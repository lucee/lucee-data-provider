#!/usr/bin/env bash
# Upload a local folder of extension logo PNGs to the artifacts R2 bucket.
#
# Object keys: extension-logos/<filename>.png
# Public URL:  https://artifacts.lucee.org/extension-logos/<filename>.png
#
# Usage:
#   ./scripts/upload-extension-logos.sh /Users/mic/Downloads/artifacts [bucket] [--dry-run]
#
# Defaults: bucket=lucee-artifacts
# Requires: npx wrangler, logged in to the Cloudflare account that owns the bucket.
# wrangler must be called with --remote so the objects go to the real bucket, not local miniflare storage.
#
# To print an rclone equivalent instead of uploading with wrangler:
#   ./scripts/upload-extension-logos.sh /Users/mic/Downloads/artifacts lucee-artifacts --rclone

set -euo pipefail

usage() {
	sed -n '2,16p' "$0" | sed 's/^# \?//'
	exit "${1:-0}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	usage 0
fi

SRC="${1:-}"
BUCKET="${2:-lucee-artifacts}"
MODE="${3:-}"
PREFIX="extension-logos"
CACHE_CONTROL="public, max-age=86400"

if [[ -z "$SRC" ]]; then
	usage 1
fi
if [[ ! -d "$SRC" ]]; then
	echo "Source folder not found: $SRC" >&2
	exit 1
fi

mapfile -t FILES < <(find "$SRC" -maxdepth 1 -type f -iname '*.png' | sort)
if [[ ${#FILES[@]} -eq 0 ]]; then
	echo "No .png files in $SRC" >&2
	exit 1
fi

echo "Source:  $SRC"
echo "Bucket:  $BUCKET"
echo "Prefix:  $PREFIX/  (${#FILES[@]} png files)"
echo "Headers: Content-Type: image/png"
echo "         Cache-Control: $CACHE_CONTROL"
echo

if [[ "$MODE" == "--rclone" ]]; then
	cat <<RCLONE
# rclone (configure an "r2" remote first: type=s3, provider=Cloudflare, endpoint=https://<accountid>.r2.cloudflarestorage.com)
rclone copy "$SRC" "r2:${BUCKET}/${PREFIX}" \\
  --include "*.png" --include "*.PNG" \\
  --header-upload "Cache-Control: ${CACHE_CONTROL}" \\
  --header-upload "Content-Type: image/png"
RCLONE
	exit 0
fi

DRY=0
if [[ "$MODE" == "--dry-run" ]]; then
	DRY=1
fi

for f in "${FILES[@]}"; do
	name="$(basename "$f")"
	key="${PREFIX}/${name}"
	if [[ $DRY -eq 1 ]]; then
		echo "dry-run: $f -> ${BUCKET}/${key}"
		continue
	fi
	echo "put ${BUCKET}/${key}"
	npx wrangler r2 object put "${BUCKET}/${key}" \
		--file "$f" \
		--content-type "image/png" \
		--cache-control "$CACHE_CONTROL" \
		--remote
done

if [[ $DRY -eq 0 ]]; then
	echo
	echo "Done. Example: https://artifacts.lucee.org/${PREFIX}/$(basename "${FILES[0]}")"
fi
