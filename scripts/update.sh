#!/usr/bin/env bash

set -e

# --- Environment Configuration ---
# Get the true canonical directory of this script, even through symlinks or sudo
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.config/update.env"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
else
    echo "[ERROR] Configuration file not found at ${CONFIG_FILE}"
    exit 1
fi

# Set default stack directories if not defined in update.env
STACK_PATHS=("${HOMELAB_DIR:-$HOME/homelab}" "${MEDIALAB_DIR:-$HOME/medialab}")

echo "=================================================="
echo " Starting System & Multi-Stack Update Process"
echo " Date: $(date)"
echo "=================================================="

# --- 1. System Package Updates ---
echo "[INFO] Updating system packages..."
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get autoremove -y && sudo apt-get autoclean

# --- 2. Update Repositories & Stacks ---
for STACK_PATH in "${STACK_PATHS[@]}"; do
    STACK_NAME="$(basename "$STACK_PATH")"
    COMPOSE_DIR="${STACK_PATH}/docker-apps"

    if [ -d "$STACK_PATH" ]; then
        echo "--------------------------------------------------"
        echo "[INFO] Processing stack: ${STACK_NAME}"
        echo "--------------------------------------------------"

        # Git Pull
        echo "[INFO] Pulling latest repository changes for ${STACK_NAME}..."
        git -C "$STACK_PATH" pull origin main

        # Docker Compose Operations
        if [ -d "$COMPOSE_DIR" ]; then
            echo "[INFO] Pulling container images for ${STACK_NAME}..."
            docker compose -f "${COMPOSE_DIR}/compose.yaml" pull

            echo "[INFO] Deploying updated containers for ${STACK_NAME}..."
            docker compose -f "${COMPOSE_DIR}/compose.yaml" up -d
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
docker image prune -f

echo "=================================================="
echo " Update Process Completed Successfully!"
echo "=================================================="