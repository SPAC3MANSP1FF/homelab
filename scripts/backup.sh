#!/bin/bash

# --- Load Configuration ---
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONFIG_FILE="$SCRIPT_DIR/.config/backup.env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "❌ Error: Configuration file $CONFIG_FILE not found."
    exit 1
fi

# Convert comma-separated strings to arrays
IFS=',' read -r -a HOME_SOURCES_ARRAY <<< "$HOME_SOURCES"
IFS=',' read -r -a MEDIA_FOLDERS_ARRAY <<< "$MEDIA_FOLDERS"

# --- Handle Flags & Logging ---
DRY_RUN_FLAG=""
[[ "$1" == "--dry-run" ]] && DRY_RUN_FLAG="--dry-run"

# Use a static path since $HOME might be unpredictable in cron
LOG_DIR="/var/log/homelab"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")
LOG_FILE="$LOG_DIR/${TIMESTAMP}_$(basename "$0" .sh).log"

exec > >(tee -a "$LOG_FILE") 2>&1

# --- Execution ---
if [ -n "$DRY_RUN_FLAG" ]; then
    echo "⚠️  DRY RUN MODE ENABLED."
fi

# Connection Check
if ! ping -c 1 -W 2 "$REMOTE_HOST" &> /dev/null; then
    echo "❌ Error: Cannot reach $REMOTE_HOST."
    exit 1
fi

# Part 1: Home Folders
echo -e "\n📂 [Part 1] Backing up Home Folders..."
for SRC in "${HOME_SOURCES_ARRAY[@]}"; do
    if [ -d "$SRC" ]; then
        rsync $DRY_RUN_FLAG -avh --progress -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" \
            --rsync-path="mkdir -p $HOME_DEST && rsync" \
            "$SRC" "$REMOTE_USER@$REMOTE_HOST:$HOME_DEST/"
    fi
done

# Part 2: Media Folders
echo -e "\n🎬 [Part 2] Backing up Mixed Media..."
for FOLDER in "${MEDIA_FOLDERS_ARRAY[@]}"; do
    SRC_PATH="$MEDIA_BASE/$FOLDER"

    if [ -d "$SRC_PATH" ]; then
        echo -e "\n🔄 Processing Media: $FOLDER..."

        rsync $DRY_RUN_FLAG -avh --progress \
            --usermap="*:$BACKUP_USER" \
            --groupmap="*:$BACKUP_GROUP" \
            --numeric-ids \
            -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" "$SRC_PATH" "$REMOTE_USER@$REMOTE_HOST:$MEDIA_DEST/"

        echo "✅ Finished: $FOLDER"
    else
        echo "⚠️  Warning: $SRC_PATH does not exist, skipping."
    fi
done

# --- Part 3: Docker AppData Backup ---
echo -e "\n🐳 [Part 3] Backing up Docker AppData..."

# 1. Stop containers to ensure database consistency
echo "🛑 Stopping containers..."
docker compose -f "$DOCKER_COMPOSE_YAML" down --timeout 5

# 2. Sync the data
rsync $DRY_RUN_FLAG -avh --progress \
    -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" \
    "$DOCKER_APPDATA_PATH" "$REMOTE_USER@$REMOTE_HOST:$DOCKER_BACKUP_DEST/"

# 3. Start containers back up
echo "🚀 Restarting containers..."
docker compose -f "$DOCKER_COMPOSE_YAML" up -d

echo "✅ Finished: Docker AppData"


echo -e "\n🎉 Process complete!"