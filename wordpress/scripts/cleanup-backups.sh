#!/bin/bash
# cleanup-backups.sh
# Rotation-aware cleanup:
#  - keep most recent KEEP_DAILY backups (one per day)
#  - keep most recent KEEP_WEEKLY backups (one per week) beyond daily
#  - keep most recent KEEP_MONTHLY backups (one per month) beyond weekly
#
# Config via env (set in docker-compose.yml or exported into cron's environment):
#   KEEP_DAILY (default 7)
#   KEEP_WEEKLY (default 4)
#   KEEP_MONTHLY (default 6)
#   MIN_AGE_MINUTES (default 60) -> safety: don't remove files newer than this
#
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backups}"
KEEP_DAILY="${KEEP_DAILY:-7}"
KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
KEEP_MONTHLY="${KEEP_MONTHLY:-6}"
MIN_AGE_MINUTES="${MIN_AGE_MINUTES:-60}"
LOGFILE="${LOGFILE:-/var/log/cleanup.log}"
LOCKDIR="$BACKUP_DIR/.cleanup.lock"

# simple lock (atomic mkdir)
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  echo "$(date '+%F %T') - Another cleanup running. Exiting." >> "$LOGFILE"
  exit 0
fi
trap 'rm -rf "$LOCKDIR"' EXIT

echo "$(date '+%F %T') - Cleanup started. keep: daily=$KEEP_DAILY weekly=$KEEP_WEEKLY monthly=$KEEP_MONTHLY" >> "$LOGFILE"

now=$(date +%s)
min_age_seconds=$((MIN_AGE_MINUTES * 60))

# associative arrays for bookkeeping (requires bash)
declare -A keep
declare -A seen_day
declare -A seen_week
declare -A seen_month

daily_count=0
weekly_count=0
monthly_count=0

# Get files sorted by mtime desc (newest first). Each entry is "<mtime> <fullpath>\0"
mapfile -d '' -t entries < <(find "$BACKUP_DIR" -maxdepth 1 -type f -printf '%T@ %p\0' | sort -z -rn)

# 1) pick most recent per day until KEEP_DAILY
for entry in "${entries[@]}"; do
  mtime=${entry%% *}
  file=${entry#* }
  epoch=${mtime%.*}
  day=$(date -d "@$epoch" +%Y-%m-%d)

  if [[ $daily_count -lt $KEEP_DAILY && -z ${seen_day[$day]:-} ]]; then
    keep["$file"]=1
    seen_day[$day]=1
    ((daily_count++))
  fi
done

# 2) pick most recent per ISO-week until KEEP_WEEKLY (skip already kept)
for entry in "${entries[@]}"; do
  mtime=${entry%% *}
  file=${entry#* }
  [[ -n ${keep["$file"]:+x} ]] && continue

  epoch=${mtime%.*}
  week=$(date -d "@$epoch" +%G-%V)   # ISO week-year
  if [[ $weekly_count -lt $KEEP_WEEKLY && -z ${seen_week[$week]:-} ]]; then
    keep["$file"]=1
    seen_week[$week]=1
    ((weekly_count++))
  fi
done

# 3) pick most recent per month until KEEP_MONTHLY (skip already kept)
for entry in "${entries[@]}"; do
  mtime=${entry%% *}
  file=${entry#* }
  [[ -n ${keep["$file"]:+x} ]] && continue

  epoch=${mtime%.*}
  month=$(date -d "@$epoch" +%Y-%m)
  if [[ $monthly_count -lt $KEEP_MONTHLY && -z ${seen_month[$month]:-} ]]; then
    keep["$file"]=1
    seen_month[$month]=1
    ((monthly_count++))
  fi
done

# Delete everything not marked as keep, but skip files younger than MIN_AGE_MINUTES
deleted=0
skipped_recent=0
for entry in "${entries[@]}"; do
  file=${entry#* }
  [[ -n ${keep["$file"]:+x} ]] && { echo "$(date '+%F %T') - Keeping $file" >> "$LOGFILE"; continue; }

  mtime=${entry%% *}
  epoch=${mtime%.*}

  if (( epoch > now - min_age_seconds )); then
    echo "$(date '+%F %T') - Skipping recent file (age < ${MIN_AGE_MINUTES}m): $file" >> "$LOGFILE"
    ((skipped_recent++))
    continue
  fi

  if rm -f -- "$file"; then
    echo "$(date '+%F %T') - Deleted $file" >> "$LOGFILE"
    ((deleted++))
  else
    echo "$(date '+%F %T') - Failed to delete $file" >> "$LOGFILE"
  fi
done

echo "$(date '+%F %T') - Cleanup finished. deleted=$deleted skipped_recent=$skipped_recent kept_daily=$daily_count kept_weekly=$weekly_count kept_monthly=$monthly_count" >> "$LOGFILE"
