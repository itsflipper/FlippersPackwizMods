# Server Environments

An environment is one selectable Minecraft server setup.

Only one environment may be active at a time because all environments use the same public Minecraft port.

## Vanilla

The current production environment is Vanilla on Minecraft 26.3.

- Runtime configuration: `gsr/`
- Packwiz pack: repository root (`pack.toml`, `index.toml`, `mods/`)
- Systemd service: `gsr.service`
- Podman volume: `gayshitdata`
- World name: `world-26.3`
- Minecraft port: `25565`

The existing Vanilla paths are kept for backwards compatibility with current Prism Launcher instances, the Podman bootstrap, and the running server.

## Planned environments

- Skyblock: same Vanilla Packwiz pack, separate service, volume and generated world
- Create: separate Packwiz pack and separate service
- Minigames: separate Packwiz pack and separate service
