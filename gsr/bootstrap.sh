#!/bin/bash

set -e

REPO_URL="https://github.com/itsflipper/FlippersPackwizMods.git"
BRANCH="podman"
CONTAINER_FILE="gcr.container"
SYSTEMD_DIR="$HOME/.config/containers/systemd"
SERVICE_NAME="gcr"

TARGET_DIR="${1:-$(pwd)}"

symlink_path="$SYSTEMD_DIR/$CONTAINER_FILE"
repo_path="$TARGET_DIR/FlippersPackwizMods"

is_running() {
    systemctl --user is-active --quiet "$SERVICE_NAME" 2>/dev/null
}

fresh_install() {
    echo "==> Cloning repo into $repo_path"
    git clone "$REPO_URL" "-b" "$BRANCH" "$repo_path"

    cd "$repo_path"

    echo "==> Creating symlink"
    mkdir -p "$SYSTEMD_DIR"
    ln -s "$repo_path/$CONTAINER_FILE" "$symlink_path"

    echo "==> Building image"
    podman build -t "$SERVICE_NAME" .

    echo "==> Reloading systemd"
    systemctl --user daemon-reload

    read -rp "Start the server now? [y/N] " start
    if [[ "$start" =~ ^[Yy]$ ]]; then
        systemctl --user start "$SERVICE_NAME"
        echo "==> Started. Following logs (Ctrl+C to exit):"
        journalctl --user -u "$SERVICE_NAME" -f
    else
        echo "==> Done. Start manually with: systemctl --user start $SERVICE_NAME"
    fi
}

update() {
    cd "$repo_path"

    local was_running=false
    if is_running; then
        was_running=true
    fi

    echo "==> Pulling latest changes"
    git pull

    echo "==> Rebuilding image"
    podman build -t "$SERVICE_NAME" .

    echo "==> Reloading systemd"
    systemctl --user daemon-reload

    if $was_running; then
        echo "==> Restarting service"
        systemctl --user restart "$SERVICE_NAME"
    else
        echo "==> Service was not running, skipping restart"
    fi

    echo "==> Done"
}

# -- main --

if [[ -d "$repo_path" || -L "$symlink_path" ]]; then
    read -rp "Existing install detected. Fresh install or update? [f/u] " mode
    case "$mode" in
        f|F)
            read -rp "This will nuke $repo_path and reinstall from scratch. Are you sure? [y/N] " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "Aborted" >&2
                exit 1
            fi
            if is_running; then
                echo "==> Stopping service"
                systemctl --user stop "$SERVICE_NAME"
            fi
            echo "==> Removing existing install"
            rm -rf "$repo_path"
            rm -f "$symlink_path"
            fresh_install
            ;;
        u|U)
            update
            ;;
        *)
            echo "Invalid choice" >&2
            exit 1
            ;;
    esac
else
    fresh_install
fi
