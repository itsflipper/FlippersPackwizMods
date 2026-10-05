#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_PATH="$(readlink -f "$0")"
REPO_ROOT="${GSR_REPO_ROOT:-$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)}"
ENVIRONMENTS_ROOT="$REPO_ROOT/environments"

usage() {
  cat <<'EOF'
Usage:
  gsr status [environment]
  gsr start <environment>
  gsr stop
  gsr restart
  gsr switch <environment>
  gsr rcon

`start` refuses to stop another environment implicitly. Use `switch` for an
explicit, backed-up environment change.
EOF
}

mapfile -t ENVIRONMENTS < <(
  find "$ENVIRONMENTS_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' |
    sort
)

if ((${#ENVIRONMENTS[@]} == 0)); then
  echo "No environments found." >&2
  exit 1
fi

container_file_for() {
  local environment="$1"
  local files=("$ENVIRONMENTS_ROOT/$environment"/*.container)
  [[ ${#files[@]} -eq 1 && -f "${files[0]}" ]] || return 1
  printf '%s\n' "${files[0]}"
}

service_for() {
  local file
  file="$(container_file_for "$1")" || return 1
  basename "$file" .container
}

container_for() {
  local file
  file="$(container_file_for "$1")" || return 1
  sed -nE 's/^ContainerName=([^[:space:]#]+).*/\1/p' "$file" | head -n1
}

service_exists() {
  systemctl --user cat "$1.service" >/dev/null 2>&1
}

is_active() {
  systemctl --user is-active --quiet "$1.service"
}

require_environment() {
  local requested="$1"
  [[ "$requested" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || {
    echo "Invalid environment: $requested" >&2
    exit 2
  }
  container_file_for "$requested" >/dev/null || {
    echo "Unknown or invalid environment: $requested" >&2
    exit 2
  }
  SERVICE="$(service_for "$requested")"
  service_exists "$SERVICE" || {
    echo "$requested is not installed as a systemd service yet." >&2
    exit 1
  }
  ENVIRONMENT="$requested"
}

active_environments() {
  local environment service
  for environment in "${ENVIRONMENTS[@]}"; do
    service="$(service_for "$environment")" || continue
    service_exists "$service" && is_active "$service" && printf '%s\n' "$environment"
  done
}

require_one_active() {
  local -a active=()
  mapfile -t active < <(active_environments)
  if ((${#active[@]} != 1)); then
    if ((${#active[@]} == 0)); then
      echo "No GSR environment is active." >&2
    else
      echo "More than one GSR environment is active; refusing to guess." >&2
      printf 'Active: %s\n' "${active[*]}" >&2
    fi
    exit 1
  fi
  require_environment "${active[0]}"
}

show_list() {
  local environment service state
  echo "Available environments:"
  for environment in "${ENVIRONMENTS[@]}"; do
    service="$(service_for "$environment")" || {
      printf '  %-16s invalid\n' "$environment"
      continue
    }
    if ! service_exists "$service"; then
      state="not installed"
    elif is_active "$service"; then
      state="active"
    else
      state="stopped"
    fi
    printf '  %-16s (%-10s) %s\n' "$environment" "$service" "$state"
  done
}

start_environment() {
  local -a active=()
  mapfile -t active < <(active_environments)
  if ((${#active[@]})); then
    if ((${#active[@]} == 1)) && [[ "${active[0]}" == "$ENVIRONMENT" ]]; then
      echo "$ENVIRONMENT is already active."
      return 0
    fi
    echo "Cannot start $ENVIRONMENT while ${active[*]} is active. Use: gsr switch $ENVIRONMENT" >&2
    return 1
  fi
  echo "Starting $ENVIRONMENT ($SERVICE) ..."
  systemctl --user start "$SERVICE.service"
  systemctl --user --no-pager --full status "$SERVICE.service"
}

switch_environment() {
  local -a active=()
  local active_service
  mapfile -t active < <(active_environments)
  if ((${#active[@]} == 0)); then
    echo "No GSR environment is active. Use: gsr start $ENVIRONMENT" >&2
    return 1
  fi
  if ((${#active[@]} != 1)); then
    echo "More than one GSR environment is active; refusing to switch." >&2
    return 1
  fi
  if [[ "${active[0]}" == "$ENVIRONMENT" ]]; then
    echo "$ENVIRONMENT is already active."
    return 0
  fi
  active_service="$(service_for "${active[0]}")"
  echo "Stopping ${active[0]} ($active_service); its save and backup hooks will run ..."
  systemctl --user stop "$active_service.service"
  start_environment
}

case "${1:-status}" in
  status|list|ls)
    [[ $# -le 2 ]] || { usage >&2; exit 2; }
    if [[ $# -eq 2 ]]; then
      require_environment "$2"
      systemctl --user --no-pager --full status "$SERVICE.service"
    else
      show_list
    fi
    ;;
  start)
    [[ $# -eq 2 ]] || { usage >&2; exit 2; }
    require_environment "$2"
    start_environment
    ;;
  stop)
    [[ $# -eq 1 ]] || { usage >&2; exit 2; }
    require_one_active
    echo "Stopping $ENVIRONMENT ($SERVICE); its save and backup hooks will run ..."
    systemctl --user stop "$SERVICE.service"
    ;;
  restart)
    [[ $# -eq 1 ]] || { usage >&2; exit 2; }
    require_one_active
    echo "Restarting $ENVIRONMENT ($SERVICE); its save and backup hooks will run ..."
    systemctl --user restart "$SERVICE.service"
    systemctl --user --no-pager --full status "$SERVICE.service"
    ;;
  switch)
    [[ $# -eq 2 ]] || { usage >&2; exit 2; }
    require_environment "$2"
    switch_environment
    ;;
  rcon)
    [[ $# -eq 1 ]] || { usage >&2; exit 2; }
    require_one_active
    CONTAINER="$(container_for "$ENVIRONMENT")"
    [[ -n "$CONTAINER" ]] || { echo "Cannot determine container for $ENVIRONMENT." >&2; exit 1; }
    exec podman exec -it "$CONTAINER" rcon-cli
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown environment command: $1" >&2
    usage >&2
    exit 2
    ;;
esac
