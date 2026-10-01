#!/bin/bash
set -e

REPO_URL="https://github.com/itsflipper/FlippersPackwizMods.git"
BRANCH="main"
SYSTEMD_DIR="$HOME/.config/containers/systemd"
ANCHOR_SERVICE="gsr"
ANCHOR_SYMLINK="$SYSTEMD_DIR/$ANCHOR_SERVICE"
ENVIRONMENTS_DIR="environments"
USER_BIN_DIR="$HOME/.local/bin"
COMMANDS_DIR="scripts/bin"
BASHRC_FILE="$HOME/.bashrc"

mkdir -p "$SYSTEMD_DIR"

is_running() {
    local service_name="$1"
    systemctl --user is-active --quiet "$service_name" 2>/dev/null
}

environment_container_files() {
    local repo_path="$1" container_file

    for container_file in "$repo_path/$ENVIRONMENTS_DIR"/*/*.container; do
        [[ -f "$container_file" ]] || continue
        printf '%s\n' "$container_file"
    done
}

environment_services() {
    local repo_path="$1" container_file

    while IFS= read -r container_file; do
        basename "$container_file" .container
    done < <(environment_container_files "$repo_path")
}

active_environment_services() {
    local repo_path="$1" service_name

    while IFS= read -r service_name; do
        if is_running "$service_name"; then
            printf '%s\n' "$service_name"
        fi
    done < <(environment_services "$repo_path")
}

sync_systemd() {
    local repo_path container_file environment_dir service_name link_path
    repo_path="$(cd "$1" && pwd)"
    echo "==> Linking environments + reloading systemd"
    while IFS= read -r container_file; do
        [[ -f "$container_file" ]] || continue
        environment_dir="$(dirname "$container_file")"
        service_name="$(basename "$container_file" .container)"
        link_path="$SYSTEMD_DIR/$service_name"
        if [[ -e "$link_path" && ! -L "$link_path" ]]; then
            echo "Refusing to replace non-symlink: $link_path" >&2
            return 1
        fi
        rm -f "$link_path"
        ln -s "$environment_dir" "$link_path"
        echo "    $service_name -> $environment_dir"
    done < <(environment_container_files "$repo_path")
    systemctl --user daemon-reload
    sync_user_commands "$repo_path"
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

    read -rp "Start the default Vanilla server now? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        systemctl --user start "$ANCHOR_SERVICE"
        echo "==> Started. Following logs (Ctrl+C to exit):"
        journalctl --user -u "$ANCHOR_SERVICE" -f
    else
        echo "==> Done. Start with: systemctl --user start $ANCHOR_SERVICE"
    fi
}

update() {
    local repo_path="$1" service_name
    local -a running_services=()

    mapfile -t running_services < <(active_environment_services "$repo_path")

    echo "==> Pulling latest changes"
    if ! git -C "$repo_path" pull; then
        echo "Pull failed (conflict or dirty tree) — services left untouched." >&2
        return 1
    fi

    sync_systemd "$repo_path"

    if ((${#running_services[@]})); then
        echo "==> Rebuilding and restarting active environment(s)"
        for service_name in "${running_services[@]}"; do
            systemctl --user restart "${service_name}-build.service"
            systemctl --user restart "$service_name.service"
        done
    else
        echo "==> No environment was running, skipping rebuild and restart"
    fi

    echo "==> Done"
}

ensure_user_bin_path() {
    local marker="# FlippersPackwizMods user commands"

    mkdir -p "$USER_BIN_DIR"
    export PATH="$USER_BIN_DIR:$PATH"

    if [[ ! -f "$BASHRC_FILE" ]] || ! grep -Fqx "$marker" "$BASHRC_FILE"; then
        {
            printf '\n%s\n' "$marker"
            printf 'case ":$PATH:" in\n'
            printf '  *":$HOME/.local/bin:"*) ;;\n'
            printf '  *) export PATH="$HOME/.local/bin:$PATH" ;;\n'
            printf 'esac\n'
        } >> "$BASHRC_FILE"
    fi
}

sync_user_commands() {
    local repo_path command_dir command_path command_name link_path

    repo_path="$(cd "$1" && pwd)"
    command_dir="$repo_path/$COMMANDS_DIR"
    [[ -d "$command_dir" ]] || return 0

    ensure_user_bin_path

    for command_path in "$command_dir"/*; do
        [[ -f "$command_path" && -x "$command_path" ]] || continue

        command_name="$(basename "$command_path")"
        link_path="$USER_BIN_DIR/$command_name"

        if [[ -e "$link_path" && ! -L "$link_path" ]]; then
            echo "Refusing to replace non-symlink command: $link_path" >&2
            return 1
        fi

        ln -sfn "$command_path" "$link_path"
        echo "    command: $command_name"
    done
}

# -- main --

if [[ ! -L "$ANCHOR_SYMLINK" ]]; then
    fresh_install "$DEFAULT_REPO_PATH"
    exit 0
fi

anchor_target="$(readlink -f "$ANCHOR_SYMLINK")"
repo_path="$(git -C "$anchor_target" rev-parse --show-toplevel 2>/dev/null || true)"

# Dangling/broken link: target gone or not a real checkout -> repair.
if [[ -z "$repo_path" || ! -d "$repo_path/$ENVIRONMENTS_DIR" ]]; then
    echo "Anchor symlink is broken or not part of an environment checkout — repairing via fresh install." >&2
    rm -f "$ANCHOR_SYMLINK"
    fresh_install "$DEFAULT_REPO_PATH"
    exit 0
fi

mapfile -t managed_services < <(environment_services "$repo_path")
mapfile -t running_services < <(active_environment_services "$repo_path")

echo "Existing install at $repo_path"
read -rp "[u]pdate / [r]einstall / [d]elete / [l]eave repo (resync only)? " mode
case "$mode" in
    u|U)
        update "$repo_path"
        ;;
    r|R)
        read -rp "This wipes $repo_path and reclones. Sure? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted" >&2; exit 1; }
        if inside_repo "$repo_path"; then
            echo "You're inside $repo_path — cd out before nuking." >&2
            exit 1
        fi
        for service_name in "${running_services[@]}"; do
            systemctl --user stop "$service_name.service"
        done
        rm -rf "$repo_path"
        clone_fresh "$repo_path"
        sync_systemd "$repo_path"
        for service_name in "${running_services[@]}"; do
            systemctl --user start "$service_name.service"
        done
        ;;
d|D)
    read -rp "Uninstall: stop environments, remove $repo_path and environment links. Sure? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted" >&2; exit 1; }
    if inside_repo "$repo_path"; then
        echo "You're inside $repo_path — cd out before deleting." >&2
        exit 1
    fi
    for service_name in "${running_services[@]}"; do
        systemctl --user stop "$service_name.service"
    done
    for service_name in "${managed_services[@]}"; do
        if [[ -L "$SYSTEMD_DIR/$service_name" ]]; then
            rm -f "$SYSTEMD_DIR/$service_name"
        fi
    done
    systemctl --user daemon-reload
    rm -rf "$repo_path"
    echo "==> Removed."
    ;;
    l|L)
        sync_systemd "$repo_path"
        for service_name in "${running_services[@]}"; do
            systemctl --user restart "$service_name.service"
        done
        ;;
    *)
        echo "Invalid choice" >&2
        exit 1
        ;;
esac
