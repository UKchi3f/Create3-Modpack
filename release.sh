#!/usr/bin/env bash
set -euo pipefail

# release.sh — Create 3 modpack one-click release
# Run from D:\Paul\Gaming\Minecraft\Modpack_Master, after mods are already
# updated, synced to Create01, and boot-tested clean (PACKWIZ_MODPACK_v1 §5.1-5.5).
# This script does NOT touch the running server and never selects mod updates.

REPO_DIR="/d/Paul/projects/server-configs"
TEMPLATE="$REPO_DIR/muscle/vm5-games/packs/index.html.template"
PACKS_HOST="packs@134.255.244.228"
PACKS_ROOT="/var/www/packs"

if [ $# -ne 1 ]; then
  echo "Usage: ./release.sh <version>   e.g. ./release.sh 1.0.2"
  exit 1
fi
VERSION="$1"
DATE=$(date +%d-%m-%Y)

# --- Pre-flight ---
[ -f pack.toml ] || { echo "ABORT: no pack.toml here — run this from Modpack_Master."; exit 1; }
[ -f "$TEMPLATE" ] || { echo "ABORT: template not found at $TEMPLATE"; exit 1; }
grep -q '\*\.mrpack' .gitignore 2>/dev/null || { echo "ABORT: .gitignore missing '*.mrpack' — export would blow the 100MB GitHub limit."; exit 1; }

echo "=== 1/8 Bumping pack.toml to $VERSION ==="
sed -i "s/^version = \".*\"/version = \"$VERSION\"/" pack.toml
[ "$(grep -c "^version = \"$VERSION\"" pack.toml)" -eq 1 ] || { echo "ABORT: version bump didn't land as expected."; exit 1; }

echo "=== 2/8 packwiz refresh ==="
./packwiz.exe refresh

echo "=== 3/8 git commit + push (Modpack_Master) ==="
git add .
git commit -m "Set pack version $VERSION"
git push

echo "=== 4/8 Exporting CurseForge + Modrinth ==="
./packwiz.exe curseforge export
./packwiz.exe modrinth export

CF_FILE="Create 3-$VERSION.zip"
MR_FILE="Create 3-$VERSION.mrpack"

echo "=== 5/8 Sanity-checking exports ==="
[ -f "$CF_FILE" ] || { echo "ABORT: $CF_FILE not found — export failed."; exit 1; }
[ -f "$MR_FILE" ] || { echo "ABORT: $MR_FILE not found — export failed (check for 'Found N manual downloads' above)."; exit 1; }

CF_BYTES=$(stat -c%s "$CF_FILE")
MR_BYTES=$(stat -c%s "$MR_FILE")
[ "$CF_BYTES" -ge 1000000 ] || { echo "ABORT: CF zip is only $CF_BYTES bytes — refusing to upload."; exit 1; }
[ "$MR_BYTES" -ge 100000000 ] || { echo "ABORT: mrpack is only $MR_BYTES bytes — likely the 0-byte export bug — refusing to upload."; exit 1; }

CF_MB=$(( (CF_BYTES + 500000) / 1000000 ))
MR_MB=$(( (MR_BYTES + 500000) / 1000000 ))
echo "CF zip: ${CF_MB} MB | mrpack: ${MR_MB} MB"

echo "=== 6/8 Uploading versioned files ==="
scp "$CF_FILE" "$PACKS_HOST:$PACKS_ROOT/Create3-$VERSION.zip"
scp "$MR_FILE" "$PACKS_HOST:$PACKS_ROOT/Create3-$VERSION.mrpack"

echo "=== 7/8 Overwriting unversioned pointers ==="
ssh "$PACKS_HOST" "cp $PACKS_ROOT/Create3-$VERSION.zip $PACKS_ROOT/Create3.zip && cp $PACKS_ROOT/Create3-$VERSION.mrpack $PACKS_ROOT/Create3.mrpack"

echo "=== 8/8 Regenerating and uploading the download page ==="
MOD_COUNT=$(grep -L '^side = "server"' mods/*.pw.toml | wc -l)
sed -e "s/{{VERSION}}/$VERSION/g" \
    -e "s/{{MOD_COUNT}}/$MOD_COUNT/g" \
    -e "s/{{CF_SIZE}}/${CF_MB} MB/g" \
    -e "s/{{MRPACK_SIZE}}/${MR_MB} MB/g" \
    -e "s/{{DATE}}/$DATE/g" \
    "$TEMPLATE" > /tmp/index.html.release
scp /tmp/index.html.release "$PACKS_HOST:$PACKS_ROOT/index.html"

echo "=== DONE — Create 3 v$VERSION released ==="
echo "CF:   https://packs.gamers.direct/Create3-$VERSION.zip"
echo "MR:   https://packs.gamers.direct/Create3-$VERSION.mrpack"
echo "Page: https://packs.gamers.direct/"
