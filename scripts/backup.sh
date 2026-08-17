#!/usr/bin/env bash

# Exit immediately if a command fails
set -e

# --- Parse Flags ---
DRY_RUN=false
RSYNC_DRY_FLAG=""

for arg in "$@"; do
    case "$arg" in
        --dry-run|-n)
            DRY_RUN=true
            RSYNC_DRY_FLAG="--dry-run"
            shift
            ;;
    esac
done

# Helper function to execute or echo container lifecycle commands
run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

# --- Environment Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.config/backup.env"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
else
    echo "[ERROR] Configuration file not found at ${CONFIG_FILE}"
    exit 1
fi

IFS=' ' read -r -a DOCKER_DIRS <<< "${DOCKER_STACK_DIRS:-$HOME/homelab/docker-apps $HOME/medialab/docker-apps}"

echo "=================================================="
if [ "$DRY_RUN" = true ]; then
    echo " Starting Multi-Stack Offsite Backup Process (DRY RUN)"
else
    echo " Starting Multi-Stack Offsite Backup Process"
fi
echo " Date: $(date)"
echo "=================================================="

# --- 1. Safely Stop Databases Before Sync ---
echo "[INFO] Pausing database services across stacks for consistent state..."
for COMPOSE_DIR in "${DOCKER_DIRS[@]}"; do
    if [ -f "${COMPOSE_DIR}/compose.yaml" ]; then
        echo "[INFO] Checking databases in ${COMPOSE_DIR}..."
        run_cmd docker compose -f "${COMPOSE_DIR}/compose.yaml" stop lamp-db nextcloud-db 2>/dev/null || true
    fi
done

# --- 2. Execute Offsite Backup via Rsync ---
echo "[INFO] Executing offsite rsync transfer..."
if [ -d "${DOCKER_APPDATA_PATH:-/var/lib/docker/appdata}" ]; then
    echo "[INFO] Syncing Appdata -> ${REMOTE_HOST}:${DOCKER_BACKUP_DEST}..."
    rsync -avz ${RSYNC_DRY_FLAG} --delete \
        -e "ssh -p ${REMOTE_SSH_PORT:-22} -i ${SSH_KEY_PATH}" \
        "${DOCKER_APPDATA_PATH}/" \
        "${REMOTE_USER}@${REMOTE_HOST}:${DOCKER_BACKUP_DEST}/"
fi

# --- 3. Restart Database Services ---
echo "[INFO] Restarting database services..."
for COMPOSE_DIR in "${DOCKER_DIRS[@]}"; do
    if [ -f "${COMPOSE_DIR}/compose.yaml" ]; then
        run_cmd docker compose -f "${COMPOSE_DIR}/compose.yaml" start lamp-db nextcloud-db 2>/dev/null || true
    fi
done

echo "=================================================="
echo " Backup Process Completed!"
echo "=================================================="