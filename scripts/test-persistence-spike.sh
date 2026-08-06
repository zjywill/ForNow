#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/Packages/ForNowPersistence"

swift test --package-path "$PACKAGE"
swift build --package-path "$PACKAGE" --product PersistenceCrashWorker

BIN_DIR="$(swift build --package-path "$PACKAGE" --show-bin-path)"
WORKER="$BIN_DIR/PersistenceCrashWorker"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ForNowPersistenceCrash.XXXXXX")"
DB="$TMP/notes.sqlite"
BACKUPS="$TMP/Backups"
NOTE_ID="9F8B9C64-D597-46A8-8B9F-BA99002D9015"
BODY="flushed before SIGKILL 中文"
WRITE_READY="$TMP/write.ready"
BACKUP_READY="$TMP/backup.ready"
writer_pid=""
backup_pid=""

cleanup() {
  if [[ -n "$writer_pid" ]]; then
    kill -KILL "$writer_pid" 2>/dev/null || true
    wait "$writer_pid" 2>/dev/null || true
  fi
  if [[ -n "$backup_pid" ]]; then
    kill -KILL "$backup_pid" 2>/dev/null || true
    wait "$backup_pid" 2>/dev/null || true
  fi
  if [[ -d "$TMP" ]]; then
    rm -r "$TMP"
  fi
}
trap cleanup EXIT

wait_for_file() {
  local path="$1"
  for _ in {1..1000}; do
    if [[ -f "$path" ]]; then
      return 0
    fi
    sleep 0.01
  done
  echo "Timed out waiting for $path" >&2
  return 1
}

"$WORKER" write-and-wait "$DB" "$BACKUPS" "$NOTE_ID" "$WRITE_READY" "$BODY" &
writer_pid=$!
wait_for_file "$WRITE_READY"
kill -KILL "$writer_pid"
wait "$writer_pid" 2>/dev/null || true

reopened_body="$("$WORKER" read "$DB" "$BACKUPS" "$NOTE_ID" unused)"
if [[ "$reopened_body" != "$BODY" ]]; then
  echo "Flushed body did not survive SIGKILL" >&2
  exit 1
fi

"$WORKER" backup-and-wait "$DB" "$BACKUPS" "$NOTE_ID" "$BACKUP_READY" &
backup_pid=$!
wait_for_file "$BACKUP_READY"
kill -KILL "$backup_pid"
wait "$backup_pid" 2>/dev/null || true

if ! find "$BACKUPS" -maxdepth 1 -name '.*.tmp' -print -quit | rg -q .; then
  echo "Backup worker did not leave the expected interrupted temp file" >&2
  exit 1
fi

"$WORKER" read "$DB" "$BACKUPS" "$NOTE_ID" unused >/dev/null

if find "$BACKUPS" -maxdepth 1 -name '.*.tmp' -print -quit | rg -q .; then
  echo "Startup did not remove interrupted backup temp files" >&2
  exit 1
fi

if find "$BACKUPS" -maxdepth 1 -name 'backup-*.json' -print -quit | rg -q .; then
  echo "Interrupted backup was incorrectly published" >&2
  exit 1
fi

echo "persistence crash fault tests: PASS"
