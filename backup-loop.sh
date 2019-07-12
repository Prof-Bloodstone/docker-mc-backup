#!/bin/bash

set -eu

set -x # TODO: REMOVE ME!
# TODO: REMOVE ME!!!
rcon-cli() {
  true
}

poc_log() {
  if [ "$#" -lt 1 ]; then
    echo "Wrong number of arguments passed to poc_log function" >&2
    exit 1
  fi
  local level="${1}"
  shift
  logs="${*:-"$(cat -)"}"

  <<<"${logs}" awk -v level="${level}" '/^[[:space:]]*$/ {print $0; next;} { "date -Iseconds" | getline d; printf("%s %s %s\n", d, level, $0); close("date")}'
}

log() {
  if [ "$#" -lt 2 ]; then
    echo "Wrong number of arguments passed to log function" >&2
    exit 1
  fi
  local level="${1}"
  shift
  echo "$(date -Iseconds) ${level} $*"
}

find_old_backups() {
  find "${DEST_DIR}" -mtime "+${PRUNE_BACKUPS_DAYS}" "${@}"
}

: "${SRC_DIR:=/data}"
: "${DEST_DIR:=/backups}"
: "${BACKUP_NAME:=world}"
: "${INITIAL_DELAY:=2*60}" # 2*60 seconds = 2 minutes
: "${INTERVAL_SEC:=24*60*60}" # 24*60*60 = 24 hours
: "${PRUNE_BACKUPS_DAYS:=7}"
: "${TYPE:=VANILLA}" # unused
: "${RCON_PORT:=25575}"
: "${RCON_PASSWORD:=minecraft}"
: "${EXCLUDES:=*.jar,cache,logs}" # Comma separated list of glob(3) patterns

# We unfortunately can't use a here-string, as it inserts new line at the end
readarray -td, excludes_patterns < <(printf '%s' "${EXCLUDES}")

excludes=()
for pattern in "${excludes_patterns[@]}"; do
  excludes+=(--exclude "${pattern}")
done

# Should we even do this?
ftb_dir="${SRC_DIR}/FeedTheBeast"
if [ -d "${ftb_dir}" ]; then
  SRC_DIR="${ftb_dir}"
fi

log INFO "waiting initial delay of ${INITIAL_DELAY} seconds..."
sleep "$(( INITIAL_DELAY ))"

log INFO "waiting for rcon readiness..."
while true; do
  if rcon-cli save-on &> /dev/null; then
    break
  else
    sleep 10
  fi
done

while true; do
  ts=$(date -u +"%Y%m%d-%H%M%S")

  if rcon-cli save-off; then
    if rcon-cli save-all; then

      outFile="${DEST_DIR}/${BACKUP_NAME}-${ts}.tgz"
      log INFO "backing up content in ${SRC_DIR} to ${outFile}"
      # shellcheck disable=SC2086
      if tar "${excludes[@]}" -czf "${outFile}" -C "${SRC_DIR}" .; then
        log INFO "successfully backed up"
      else
        log ERROR "backup failed"
      fi

    fi
    rcon-cli save-on
  else
    log ERROR "rcon save-off command failed"
  fi

  if (( PRUNE_BACKUPS_DAYS > 0 )) && [ -n "$(find_old_backups -print -quit)" ]; then
    log INFO "pruning backup files older than ${PRUNE_BACKUPS_DAYS} days"
    find_old_backups -print -delete | poc_log INFO
  fi

  log INFO "sleeping ${INTERVAL_SEC} seconds..."
  sleep "$(( INTERVAL_SEC ))"
done
