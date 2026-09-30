# Environment Template

Use this template when adding a new selectable Minecraft environment.

Each environment must define:

- a unique systemd service name
- a unique Podman container name
- a separate persistent Podman volume
- a world name via `LEVEL`
- an optional first-start world template via `WORLD`
- the Packwiz URL it uses
- the shared public Minecraft port `25565`

Only one environment may run at a time.

## Compatibility rules

Do not move or rename the current Vanilla runtime:

- root `pack.toml`, `index.toml` and `mods/`
- `gsr/`
- `gsr.service`
- `gayshitdata`

New environments are additive. They must use separate services and volumes.
