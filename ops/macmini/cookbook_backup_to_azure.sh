#!/bin/bash
# Nightly cookbook backup on the Mac mini -> age encryption -> Azure Blob container "cookbook".
# Runbook: docs/Runbook_Move_to_Mac_mini.md, step 11. Run by the LaunchAgent
# ~/Library/LaunchAgents/ai.adapticlaw.cookbook-backup.plist (3:15 AM).
#
# - Database: mariadb-dump of `openeats` from the running db container (its own root password,
#   from env_macmini.list inside the container; nothing secret passes through this script).
# - Photos: site-media from the api container, as a tar stream.
# - Encryption: age, public key only (same key as the OpenClaw backup; the private key is in the
#   Keychain item openclaw-backup-age-key and the password manager, needed only to restore).
# - Upload: azcopy with an upload-only container SAS read from the Keychain (cookbook-backup-sas).
#   The token is never printed.
set -euo pipefail

CONTAINER_URL="https://stadapticlawbkp39847.blob.core.windows.net/cookbook"
AGE_RECIPIENT="age1ydye6mvndhg7kk0xms3zawy2f0rctcxujf08pm3lypvwhllak4gsl7lem7"
KEEP_LOCAL=14
COMPOSE_DIR="$HOME/OpenEats"
COMPOSE_FILE="docker-compose.macmini.yml"

export PATH="$HOME/.orbstack/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
DATA="$HOME/adapticlaw-data"
BK="$DATA/cookbook-backups"
LOGDIR="$DATA/logs"
mkdir -p "$BK" "$LOGDIR"
chmod 700 "$BK"
umask 077

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$LOGDIR/cookbook-backup-$(date +%Y-%m).log"
WORK="$(mktemp -d "$BK/.work-$STAMP.XXXX")"
ARCHIVE="$BK/cookbook-backup-$STAMP.tar.gz"
ENCRYPTED="$ARCHIVE.age"
export AZCOPY_LOG_LOCATION="$LOGDIR/azcopy"
export AZCOPY_JOB_PLAN_LOCATION="$LOGDIR/azcopy/plans"
mkdir -p "$AZCOPY_LOG_LOCATION" "$AZCOPY_JOB_PLAN_LOCATION"

exec >>"$LOG" 2>&1
echo "=== $(date -u +%FT%TZ) cookbook backup start"
cleanup() { rm -rf "$WORK" "$ARCHIVE"; }
trap cleanup EXIT
fail() { echo "FAILED: $1"; exit 1; }

cd "$COMPOSE_DIR"
dc() { docker compose -f "$COMPOSE_FILE" "$@"; }

# 1. Database dump (consistent snapshot without locking the site).
dc exec -T db sh -c 'exec mariadb-dump --single-transaction --routines openeats -uroot -p"$MYSQL_ROOT_PASSWORD"' \
  > "$WORK/openeats.sql" || fail "database dump"
[[ $(stat -f %z "$WORK/openeats.sql") -gt 10000 ]] || fail "database dump is suspiciously small"
grep -q "CREATE TABLE" "$WORK/openeats.sql" || fail "database dump has no tables"

# 2. Recipe photos.
dc exec -T api tar -C /code -czf - site-media > "$WORK/site-media.tar.gz" || fail "photo archive"
tar -tzf "$WORK/site-media.tar.gz" >/dev/null || fail "photo archive is not readable"

# 3. A small manifest, then one archive.
{
  echo "created_utc=$STAMP"
  echo "host=$(hostname -s)"
  echo "sql_bytes=$(stat -f %z "$WORK/openeats.sql")"
  echo "photo_files=$(tar -tzf "$WORK/site-media.tar.gz" | grep -vc '/$')"
} > "$WORK/MANIFEST.txt"
tar -C "$WORK" -czf "$ARCHIVE" MANIFEST.txt openeats.sql site-media.tar.gz || fail "archive"

# 4. Encrypt (public key only); the plaintext is removed by the cleanup trap.
age -r "$AGE_RECIPIENT" -o "$ENCRYPTED" "$ARCHIVE" || fail "age encryption"
BYTES="$(stat -f %z "$ENCRYPTED")"

# 5. Upload. Strip a leading '?' from the SAS if present.
SAS="$(security find-generic-password -a adapticlaw -s cookbook-backup-sas -w 2>/dev/null)" \
  || fail "SAS token not readable from Keychain (locked, or item cookbook-backup-sas missing)"
SAS="${SAS#\?}"
azcopy copy "$ENCRYPTED" "$CONTAINER_URL/$(basename "$ENCRYPTED")?$SAS" \
  --overwrite=true --output-level essential || { unset SAS; fail "azcopy upload"; }
unset SAS
echo "uploaded $(basename "$ENCRYPTED") ($BYTES bytes); $(grep photo_files "$WORK/MANIFEST.txt")"

# 6. Keep the newest copies locally (Azure's lifecycle rule handles the cloud).
ls -1t "$BK"/cookbook-backup-*.age 2>/dev/null | tail -n +$((KEEP_LOCAL + 1)) | while read -r old; do
  rm -f "$old"
done
echo "=== done"
