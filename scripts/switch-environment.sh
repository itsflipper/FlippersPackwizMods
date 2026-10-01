#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_PATH="$(readlink -f "$0")"
REPO_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
ENVIRONMENTS_ROOT="$REPO_ROOT/environments"

mapfile -t ENVIRONMENTS < <(
  find "$ENVIRONMENTS_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' |
    sort
)

if ((${#ENVIRONMENTS[@]} == 0)); then
  echo "No environments found." >&2
  exit 1
fi

service_for() {
  local environment="$1"
  local container_files=("$ENVIRONMENTS_ROOT/$environment"/*.container)

  if [[ ${#container_files[@]} -ne 1 || ! -f "${container_files[0]}" ]]; then
    return 1
  fi

  basename "${container_files[0]}" .container
}

service_exists() {
  systemctl --user cat "$1.service" >/dev/null 2>&1
}

show_list() {
  local environment service state

  echo "Available environments:"
  for environment in "${ENVIRONMENTS[@]}"; do
    if ! service="$(service_for "$environment")"; then
      printf '  %-16s invalid (expected exactly one .container file)\n' "$environment"
      continue
    fi

    if ! service_exists "$service"; then
      state="not installed"
    elif systemctl --user is-active --quiet "$service.service"; then
      state="active"
    else
      state="stopped"
    fi

    printf '  %-16s (%-10s) %s\n' "$environment" "$service" "$state"
  done
}

resolve_environment() {
  local requested="$1" environment service

  for environment in "${ENVIRONMENTS[@]}"; do
    if ! service="$(service_for "$environment")"; then
      continue
    fi

    if [[ "$requested" == "$environment" || "$requested" == "$service" ]]; then
      printf '%s\n' "$environment"
      return 0
    fi
  done

  return 1
}

case "${1:-list}" in
  list|ls)
    show_list
    ;;
  *)
    requested="$1"

    if ! environment="$(resolve_environment "$requested")"; then
      echo "Unknown environment: $requested" >&2
      show_list
      exit 2
    fi

    if ! service="$(service_for "$environment")"; then
      echo "Invalid environment: $environment" >&2
      exit 1
    fi

    if ! service_exists "$service"; then
      echo "$environment is not installed as a systemd service yet." >&2
      exit 1
    fi

    if systemctl --user is-active --quiet "$service.service"; then
      echo "$environment is already active."
      exit 0
    fi

    echo "Stopping active Minecraft environments ..."
    for other_environment in "${ENVIRONMENTS[@]}"; do
      if ! other_service="$(service_for "$other_environment")"; then
        continue
      fi

      if service_exists "$other_service" &&
        systemctl --user is-active --quiet "$other_service.service"; then
        systemctl --user stop "$other_service.service"
      fi
    done

    echo "Starting $environment ($service) ..."
    systemctl --user start "$service.service"
    systemctl --user --no-pager --full status "$service.service"
    ;;
esac
