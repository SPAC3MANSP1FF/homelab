#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- Parse Flags ---
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --dry-run|-n)
            DRY_RUN=true
            ;;
    esac
done

# Helper function to execute or echo commands
run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

# --- Environment Configuration ---
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.config/update.env"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
else
    echo "[ERROR] Configuration file not found at ${CONFIG_FILE}"
    exit 1
fi

# Resolve real user's home directory if run via sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(eval echo "~${REAL_USER}")"

# Replace any literal /root or $HOME occurrences with the real user's home path
RESOLVED_STACKS="${STACK_PATHS//\/root/$REAL_HOME}"
IFS=' ' read -r -a STACKS <<< "${RESOLVED_STACKS:-$REAL_HOME/homelab $REAL_HOME/medialab}"

echo "=================================================="
if [ "$DRY_RUN" = true ]; then
    echo " Starting Multi-Stack Update Process (DRY RUN)"
else
    echo " Starting Multi-Stack Update Process"
fi
echo " Date: $(date)"
echo "=================================================="

# --- 1. System Package Updates ---
echo "[INFO] Updating system packages..."
run_cmd sudo apt-get update
run_cmd sudo apt-get upgrade -y
run_cmd sudo apt-get autoremove -y
run_cmd sudo apt-get autoclean

# --- 2. Update Repositories & Stacks ---
for STACK_PATH in "${STACKS[@]}"; do
    STACK_NAME="$(basename "$STACK_PATH")"
    COMPOSE_DIR="${STACK_PATH}/docker-apps"

    if [ -d "$STACK_PATH" ]; then
        echo "--------------------------------------------------"
        echo "[INFO] Processing stack: ${STACK_NAME}"
        echo "--------------------------------------------------"

        # Git Pull as the real user to preserve SSH key/permission context
        echo "[INFO] Pulling latest repository changes for ${STACK_NAME}..."
        run_cmd sudo -u "$REAL_USER" git -C "$STACK_PATH" pull origin main

        # Docker Compose Operations
        if [ -d "$COMPOSE_DIR" ]; then
            echo "[INFO] Pulling container images for ${STACK_NAME}..."
            run_cmd docker compose -f "${COMPOSE_DIR}/compose.yaml" pull

            echo "[INFO] Deploying updated containers for ${STACK_NAME}..."
            run_cmd docker compose -f "${COMPOSE_DIR}/compose.yaml" up -d
        else
            echo "[WARN] Docker Compose directory missing for ${STACK_NAME}: ${COMPOSE_DIR}"
        fi
    else
        echo "[WARN] Stack path does not exist: ${STACK_PATH}"
    fi
done

# --- 3. Docker Cleanup ---
echo "--------------------------------------------------"
echo "[INFO] Pruning unused Docker images and build caches..."
run_cmd docker image prune -f

echo "=================================================="
echo " Update Process Completed Successfully!"
echo "=================================================="