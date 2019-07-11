#!/bin/bash

set -eu

log() {
  if [ "$#" -lt 2 ]; then
    echo "Wrong number of arguments passed to log function" >&2
    exit 1
  fi
  local level=${1}
  shift
  echo "$(date -Iseconds) ${level} $*"
}


backupSet="${BACKUP_SET:-}"
# shellcheck disable=SC2089
excludes="${EXCLUDES:-"--exclude '*.jar'"}"

: "${SRC_DIR:=/data}"
: "${DEST_DIR:=/backups}"
: "${BACKUP_NAME:=world}"
: "${INITIAL_DELAY:=120}"
: "${INTERVAL_SEC:=86400}"
: "${PRUNE_BACKUPS_DAYS:=7}"
: "${TYPE:=VANILLA}"
: "${RCON_PORT:=25575}"
: "${RCON_PASSWORD:=minecraft}"

case "${TYPE}" in
  FTB|CURSEFORGE)
    cd "${SRC_DIR}/FeedTheBeast"
    ;;
  BUKKIT|SPIGOT|PAPER)
    cd "${SRC_DIR}"
    if [ -z "${LEVEL:-}" ]; then
      LEVEL="world world_nether world_the_end"
    fi
    ;;
  *)
    cd "${SRC_DIR}"
    ;;
esac

: "${LEVEL:=world}"

log INFO "waiting initial delay of ${INITIAL_DELAY} seconds..."
sleep ${INITIAL_DELAY}

backupSet="${backupSet} ${LEVEL}"
backupSet="${backupSet} $(find . -maxdepth 1 -name '*.properties' -o -name '*.yml' -o -name '*.yaml' -o -name '*.json' -o -name '*.txt')"

if [ -d plugins ]; then
  backupSet="${backupSet} plugins"
fi

log INFO "waiting for rcon readiness..."
while true; do
  rcon-cli save-on >& /dev/null && break
  sleep 10
done

old_backup_find_command=(
  find
  "${DEST_DIR}"
  -mtime
  "+${PRUNE_BACKUPS_DAYS}"
  -print
  )

while true; do
  ts=$(date -u +"%Y%m%d-%H%M%S")

  if rcon-cli save-off; then
    if rcon-cli save-all; then

      outFile="${DEST_DIR}/${BACKUP_NAME}-${ts}.tgz"
      log INFO "backing up content in $(pwd) to ${outFile}"
      # shellcheck disable=SC2086
      if tar cz -f "${outFile}" ${backupSet} ${excludes}; then
        log ERROR "backup failed"
      else
        log INFO "successfully backed up"
      fi

    fi
    rcon-cli save-on
  else
    log ERROR "rcon save-off command failed"
  fi

  if (( PRUNE_BACKUPS_DAYS > 0 )) && [ -n "$("${old_backup_find_command[@]}" -quit)" ]; then
    log INFO "pruning backup files older than ${PRUNE_BACKUPS_DAYS} days"
    "${old_backup_find_command[@]}" -delete
  fi

  log INFO "sleeping ${INTERVAL_SEC} seconds..."
  sleep ${INTERVAL_SEC}
done
