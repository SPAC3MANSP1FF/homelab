#!/bin/bash

# Exit immediately if any command fails
set -e

# --- LOAD CONFIGURATION ---
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONFIG_FILE="$SCRIPT_DIR/.config/update.env"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "❌ Error: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

# --- Logging Setup ---
# Use a static path since $HOME might be unpredictable in cron
LOG_DIR="/var/log/homelab"
mkdir -p "${LOG_DIR}"
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")
LOG_FILE="$LOG_DIR/${TIMESTAMP}_$(basename "$0" .sh).log"

exec > >(tee -a "$LOG_FILE") 2>&1


# Ensure the script is being run with sudo
if [ "$EUID" -ne 0 ]; then
  echo "❌ Error: This script must be run with sudo (e.g., sudo ./update.sh)"
  exit 1
fi

echo "=============================================="
echo "📦 PHASE 1: Ubuntu OS System Maintenance"
echo "=============================================="

echo "📥 Fetching latest package lists..."
apt-get update

echo "🚀 Upgrading Ubuntu system packages..."
apt-get dist-upgrade -y

echo "🧹 Cleaning up old kernels and orphaned packages..."
apt-get autoremove -y

echo "🗑️ Clearing local repository of retrieved package files..."
apt-get autoclean

echo ""
echo "=============================================="
echo "🐳 PHASE 2: Docker Media Stack Maintenance"
echo "=============================================="

# Navigate to your Docker Compose directory
cd "$DOCKER_DIR"

echo "📥 Checking for new Docker image updates..."
docker compose pull

echo "🔄 Recreating containers (respecting pinned versions)..."
docker compose up -d

echo "🧹 Cleaning up old, dangling Docker images..."
docker image prune -f

# --- Auto-Update Script from Git ---
echo ""
echo "=============================================="
echo "🐙 PHASE 3: Script Updates"
echo "=============================================="

# Navigate to the repo using the variable from .env
cd "$REPO_DIR"

# Run git pull using the specific SSH key defined in .config/update.env
# We use sudo -E to keep the environment, but force the key explicitly
export GIT_SSH_COMMAND="ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=accept-new"

git pull origin main

if [ $? -eq 0 ]; then
    echo "✅ Scripts are up to date."
else
    echo "⚠️  Warning: Could not pull updates from Git. Please check your network/repo status."
fi

echo ""
echo "=============================================="
echo "✅ SUCCESS: System, scripts, and containers are fully updated!"
echo "=============================================="
