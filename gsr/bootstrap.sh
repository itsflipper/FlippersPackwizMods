#!/bin/bash
set -e

REPO_URL="https://github.com/itsflipper/FlippersPackwizMods.git"
BRANCH="main"
SYSTEMD_DIR="$HOME/.config/containers/systemd"
SERVICE_NAME="gsr"
SYMLINK_PATH="$SYSTEMD_DIR/$SERVICE_NAME"
DEFAULT_REPO_PATH="$HOME/projects/FlippersPackwizMods"

mkdir -p "$SYSTEMD_DIR"

is_running() {
    systemctl --user is-active --quiet "$SERVICE_NAME" 2>/dev/null
}

sync_systemd() {
    local repo_path; repo_path="$(cd "$1" && pwd)"
    echo "==> Linking quadlet + reloading systemd"
    rm -f "$SYMLINK_PATH"
    ln -s "$repo_path/$SERVICE_NAME" "$SYMLINK_PATH"
    systemctl --user daemon-reload
}

inside_repo() {
    local repo_path="$1" cwd; cwd="$(pwd -P)"
    [[ "$cwd" == "$repo_path" || "$cwd" == "$repo_path"/* ]]
}

clone_fresh() {
    echo "==> Cloning into $1"
    git clone -b "$BRANCH" "$REPO_URL" "$1"
}

fresh_install() {
    local repo_path="$1"
    clone_fresh "$repo_path"
    sync_systemd "$repo_path"

    read -rp "Start the GSR Server now? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        systemctl --user start "$SERVICE_NAME"
        echo "==> Started. Following logs (Ctrl+C to exit):"
        journalctl --user -u "$SERVICE_NAME" -f
    else
        echo "==> Done. Start with: systemctl --user start $SERVICE_NAME"
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
    podman build -t "$SERVICE_NAME" "$repo_path/gsr"

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

if [[ ! -L "$SYMLINK_PATH" ]]; then
    fresh_install "$DEFAULT_REPO_PATH"
    exit 0
fi

repo_path="$(dirname "$(readlink -f "$SYMLINK_PATH")")"

# Dangling/broken link: target gone or not a real checkout -> repair.
if [[ -z "$repo_path" || ! -d "$repo_path/$SERVICE_NAME" ]]; then
    echo "Symlink dangling (repo missing) — repairing via fresh install." >&2
    rm -f "$SYMLINK_PATH"
    fresh_install "$DEFAULT_REPO_PATH"
    exit 0
fi

was_running=false
if is_running; then was_running=true; fi

echo "Existing install at $repo_path"
read -rp "[u]pdate / [r]einstall / [d]elete / [l]eave repo (resync only)? " mode
case "$mode" in
    u|U)
        if ! git -C "$repo_path" pull; then
            echo "Pull failed (conflict or dirty tree) — server left untouched." >&2
            exit 1
        fi
        sync_systemd "$repo_path"
        if $was_running; then systemctl --user restart "$SERVICE_NAME"; fi
        ;;
    r|R)
        read -rp "This wipes $repo_path and reclones. Sure? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted" >&2; exit 1; }
        if inside_repo "$repo_path"; then
            echo "You're inside $repo_path — cd out before nuking." >&2
            exit 1
        fi
        if $was_running; then systemctl --user stop "$SERVICE_NAME"; fi
        rm -rf "$repo_path"
        clone_fresh "$repo_path"
        sync_systemd "$repo_path"
        if $was_running; then systemctl --user restart "$SERVICE_NAME"; fi
        ;;
    d|D)
        read -rp "Uninstall: stop service, remove $repo_path + symlink. Sure? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted" >&2; exit 1; }
        if $was_running; then systemctl --user stop "$SERVICE_NAME"; fi
        rm -rf "$repo_path"
        rm -f "$SYMLINK_PATH"
        systemctl --user daemon-reload
        echo "==> Removed."
        ;;
    l|L)
        sync_systemd "$repo_path"
        if $was_running; then systemctl --user restart "$SERVICE_NAME"; fi
        ;;
    *)
        echo "Invalid choice" >&2
        exit 1
        ;;
esac