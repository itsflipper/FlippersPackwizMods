# Skyblock Environment

This environment is planned as a Vanilla Skyblock server.

## Shared components

- Minecraft version: 26.3
- Loader: Fabric
- Packwiz pack: the existing root `pack.toml`
- Mod set: same as the current Vanilla environment
- Public Minecraft port: `25565`

## Separate components

- Future service: `skyblock.service`
- Future container name: `skyblock`
- Future persistent volume: `skyblockdata`
- World name: `skyblock`
- First-start world: a pre-generated empty Skyblock world template

The Skyblock environment is not deployed yet. Its service, container configuration and world template will be added without changing the existing `gsr` Vanilla environment.
