#!/usr/bin/env bash
set -euo pipefail

# Default settings
RETAIN_HOURS=48
DATA_PATH=""
EXCLUDES=()
DRY_RUN=0
VERBOSE=0

log_fd="/proc/1/fd/1"
if [[ ! -w "$log_fd" ]]; then
  log_fd="/dev/stdout"
fi

log() {
  # always log
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" >> "$log_fd"
}

vlog() {
  (( VERBOSE )) && log "[verbose] $*"
}

usage() {
  cat <<'USAGE'
prune-data.sh - prune files older than a retention period while excluding directories.

Usage:
  prune-data.sh -p /path/to/data [-r HOURS] [-e dir1] [-e dir2,dir3] [-n] [-v]

Options:
  -p, --path PATH            Data directory to prune (required)
  -r, --retain-hours HOURS   Hours to retain (default: 48)
  -e, --exclude DIRS         Excluded subdirectory name(s). May be repeated, or comma-separated.
  -n, --dry-run              Show what would be deleted; do not delete
  -v, --verbose              Verbose logging
  -h, --help                 Show this help

Examples:
  prune-data.sh -p /data/cache
  prune-data.sh -p /data/cache -r 72 -e visor_child_stderr
  prune-data.sh -p /data/cache -e logs,tmp,keep -n -v
USAGE
}

# Parse args (supports GNU long options)
PARSED=$(getopt -o p:r:e:nvh --long path:,retain-hours:,exclude:,dry-run,verbose,help -- "$@" 2>/dev/null || true)
if [[ -z "${PARSED}" ]]; then
  usage; exit 1
fi
eval set -- "$PARSED"

while true; do
  case "$1" in
    -p|--path)          DATA_PATH="$2"; shift 2;;
    -r|--retain-hours)  RETAIN_HOURS="$2"; shift 2;;
    -e|--exclude)
      IFS=',' read -r -a parts <<< "$2"
      EXCLUDES+=("${parts[@]}")
      shift 2;;
    -n|--dry-run)       DRY_RUN=1; shift;;
    -v|--verbose)       VERBOSE=1; shift;;
    -h|--help)          usage; exit 0;;
    --) shift; break;;
    *) echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

# Validate
if [[ -z "${DATA_PATH}" ]]; then
  echo "Error: --path is required" >&2
  usage
  exit 1
fi
if [[ ! -d "${DATA_PATH}" ]]; then
  log "Error: Data directory ${DATA_PATH} does not exist."
  exit 1
fi
if ! [[ "${RETAIN_HOURS}" =~ ^[0-9]+$ ]]; then
  log "Error: retain-hours must be a non-negative integer."
  exit 1
fi

log "Prune script started"
log "Data path: ${DATA_PATH}"
log "Retention: ${RETAIN_HOURS} hours"
(( ${#EXCLUDES[@]} > 0 )) && log "Excludes: ${EXCLUDES[*]}" || log "Excludes: (none)"
(( DRY_RUN )) && log "Mode: DRY-RUN" || log "Mode: LIVE"
(( VERBOSE )) && log "Verbose: on"

# Snapshot before
size_before=$(du -sh -- "${DATA_PATH}" | cut -f1 || echo "n/a")
files_before=$(find "${DATA_PATH}" -type f 2>/dev/null | wc -l | awk '{print $1}')
log "Size before pruning: ${size_before} with ${files_before} files"

# Build prune args
PRUNE_ARGS=()
for dir in "${EXCLUDES[@]}"; do
  # Skip empty entries (can happen if user passes trailing comma)
  [[ -z "$dir" ]] && continue
  PRUNE_ARGS+=( -path "${DATA_PATH%/}/*/${dir}" -prune -o )
  PRUNE_ARGS+=( -path "${DATA_PATH%/}/${dir}" -prune -o )
done

MINS=$(( RETAIN_HOURS * 60 ))

log "Starting pruning process..."

if (( DRY_RUN )); then
  while IFS= read -r -d '' file; do
    log "would delete -> ${file}"
  done < <(
    find "${DATA_PATH}" -mindepth 1 \
      "${PRUNE_ARGS[@]}" -type f -mmin +"${MINS}" -print0 2>/dev/null
  )
else
  while IFS= read -r -d '' file; do
    (( VERBOSE )) && log "deleting -> ${file}"
    rm -f -- "${file}"
  done < <(
    find "${DATA_PATH}" -mindepth 1 \
      "${PRUNE_ARGS[@]}" -type f -mmin +"${MINS}" -print0 2>/dev/null
  )
fi

# Snapshot after
size_after=$(du -sh -- "${DATA_PATH}" | cut -f1 || echo "n/a")
files_after=$(find "${DATA_PATH}" -type f 2>/dev/null | wc -l | awk '{print $1}')
removed=$(( files_before - files_after ))
log "Size after pruning: ${size_after} with ${files_after} files"
log "Pruning completed. Reduced from ${size_before} to ${size_after} (${removed} files removed)."
