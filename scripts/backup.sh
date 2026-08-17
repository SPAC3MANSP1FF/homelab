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
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.config/backup.env"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
else
    echo "[ERROR] Configuration file not found at ${CONFIG_FILE}"
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(eval echo "~${REAL_USER}")"
RESOLVED_DIRS="${DOCKER_STACK_DIRS//\/root/$REAL_HOME}"
IFS=' ' read -r -a DOCKER_DIRS <<< "${RESOLVED_DIRS:-$REAL_HOME/homelab/docker-apps $REAL_HOME/medialab/docker-apps}"

echo "=================================================="
if [ "$DRY_RUN" = true ]; then
    echo " Starting Multi-Stack Offsite Backup Process (DRY RUN)"
else
    echo " Starting Multi-Stack Offsite Backup Process"
fi
echo " Date: $(date)"
echo " Target Remote Host: ${REMOTE_USER}@${REMOTE_HOST}"
echo "=================================================="

# --- 1. Database Pause ---
echo ""
echo "[1/5] Pausing database services across stacks..."
for COMPOSE_DIR in "${DOCKER_DIRS[@]}"; do
    STACK_NAME="$(basename "$(dirname "$COMPOSE_DIR")")"
    if [ -f "${COMPOSE_DIR}/compose.yaml" ]; then
        echo "  -> Stopping database containers in ${STACK_NAME}..."
        run_cmd docker compose -f "${COMPOSE_DIR}/compose.yaml" stop lamp-db nextcloud-db 2>/dev/null || true
    fi
done

# --- 2. Docker Appdata Backup ---
echo ""
echo "[2/5] Syncing Docker persistent appdata..."
if [ -d "${DOCKER_APPDATA_PATH}" ]; then
    echo "  -> ${DOCKER_APPDATA_PATH} -> ${REMOTE_USER}@${REMOTE_HOST}:${DOCKER_BACKUP_DEST}"
    rsync -avhP ${RSYNC_DRY_FLAG} --delete \
        --usermap=*:${BACKUP_USER} --groupmap=*:${BACKUP_GROUP} \
        -e "ssh -p ${REMOTE_SSH_PORT:-22} -i ${SSH_KEY_PATH}" \
        "${DOCKER_APPDATA_PATH}/" \
        "${REMOTE_USER}@${REMOTE_HOST}:${DOCKER_BACKUP_DEST}/"
fi

# --- 3. Home Directories Backup ---
echo ""
echo "[3/5] Syncing local Home directories..."
IFS=',' read -r -a HOME_PATHS <<< "${HOME_SOURCES}"
for SRC in "${HOME_PATHS[@]}"; do
    if [ -d "$SRC" ]; then
        echo "  -> Syncing ${SRC}..."
        rsync -avhP ${RSYNC_DRY_FLAG} --delete \
            -e "ssh -p ${REMOTE_SSH_PORT:-22} -i ${SSH_KEY_PATH}" \
            "${SRC}" \
            "${REMOTE_USER}@${REMOTE_HOST}:${HOME_DEST}/"
    fi
done

# --- 4. Media Folders Backup ---
echo ""
echo "[4/5] Syncing Media directories..."
IFS=',' read -r -a FOLDERS <<< "${MEDIA_FOLDERS}"
for FOLDER in "${FOLDERS[@]}"; do
    SRC="${MEDIA_BASE}/${FOLDER}"
    if [ -d "$SRC" ]; then
        echo "  -> Syncing ${SRC}..."
        rsync -avhP ${RSYNC_DRY_FLAG} --delete \
            -e "ssh -p ${REMOTE_SSH_PORT:-22} -i ${SSH_KEY_PATH}" \
            "${SRC}/" \
            "${REMOTE_USER}@${REMOTE_HOST}:${MEDIA_DEST}/${FOLDER}/"
    fi
done

# --- 5. Database Resume ---
echo ""
echo "[5/5] Restarting database services..."
for COMPOSE_DIR in "${DOCKER_DIRS[@]}"; do
    STACK_NAME="$(basename "$(dirname "$COMPOSE_DIR")")"
    if [ -f "${COMPOSE_DIR}/compose.yaml" ]; then
        echo "  -> Starting database containers in ${STACK_NAME}..."
        run_cmd docker compose -f "${COMPOSE_DIR}/compose.yaml" start lamp-db nextcloud-db 2>/dev/null || true
    fi
done

echo ""
echo "=================================================="
echo " Backup Process Completed Successfully!"
echo " Finished at: $(date)"
echo "=================================================="