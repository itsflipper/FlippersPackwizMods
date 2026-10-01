#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_PATH="$(readlink -f "$0")"
REPO_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

mapfile -t ENVIRONMENTS < <(
  find "$REPO_ROOT" -mindepth 2 -maxdepth 2 -type f -name '*.container' -printf '%f\n' |
    sed 's/\.container$//' |
    sort -u
)

if ((${#ENVIRONMENTS[@]} == 0)); then
  echo "No environments found." >&2
  exit 1
fi

service_exists() {
  systemctl --user cat "$1.service" >/dev/null 2>&1
}

show_list() {
  echo "Available environments:"
  for environment in "${ENVIRONMENTS[@]}"; do
    if ! service_exists "$environment"; then
      state="not installed"
    elif systemctl --user is-active --quiet "$environment.service"; then
      state="active"
    else
      state="stopped"
    fi
    printf '  %-16s %s\n' "$environment" "$state"
  done
}

case "${1:-list}" in
  list|ls)
    show_list
    ;;
  *)
    target="$1"

    if [[ ! " ${ENVIRONMENTS[*]} " =~ " $target " ]]; then
      echo "Unknown environment: $target" >&2
      show_list
      exit 2
    fi

    if ! service_exists "$target"; then
      echo "$target is not installed as a systemd service yet." >&2
      exit 1
    fi

    if systemctl --user is-active --quiet "$target.service"; then
      echo "$target is already active."
      exit 0
    fi

    echo "Stopping active Minecraft environments ..."
    for environment in "${ENVIRONMENTS[@]}"; do
      if service_exists "$environment"; then
        systemctl --user stop "$environment.service"
      fi
    done

    echo "Starting $target ..."
    systemctl --user start "$target.service"
    systemctl --user --no-pager --full status "$target.service"
    ;;
esac
