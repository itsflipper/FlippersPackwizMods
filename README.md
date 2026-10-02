# GSR - Personalized Fabric Server

### INCLUDES

- Separate Packwiz modpacks per environment
  - Vanilla: `environments/vanilla/pack/`
  - Skyblock: `environments/skyblock/pack/`
- MC-Server:
  - Podman Quadlets using [itzg/minecraft-server](https://hub.docker.com/r/itzg/minecraft-server) as base image
  - Fetches the matching modpack automatically
  - Bootstrap script for both fresh installs and infrastructure updates
- `scripts/switch-environment.sh` switches safely between environments
- `mc-whitelist` maintains one private whitelist for every environment
- `gsr-backup` keeps one verified full-volume backup per environment
- Worlds, player data and runtime configuration remain separate per environment

## Environments

| Environment | Minecraft | Service | Container | Volume | World |
|---|---:|---|---|---|---|
| Vanilla | 26.3 | `gsr.service` | `gsr` | `gayshitdata` | `world-26.3` |
| Skyblock | 26.2 | `skyblock.service` | `skyblock` | `skyblockdata` | `skyblock` |

Both environments use port `25565`; only one may run at a time.

## Shared private whitelist

On its first run, `bootstrap.sh` creates the server-private identity source and
the generated master whitelist under `~/.config/gsr/`:

- `shared/identities.json` is the source of truth: it records the exact player
  name, deterministic offline UUID, optional Mojang UUID, and which identities
  are allowed.
- `shared/whitelist.json` is generated from it and used by every environment.
  Neither file is committed to Git.

The old environment-local `whitelist.json` files are intentionally gone.
`defaults/identities.example.json` documents the format with fictional names
and UUIDs only; bootstrap never copies it into a real server profile.

Bootstrap preserves existing private data:

- If both private files exist, it changes neither of them.
- If `identities.json` exists but `whitelist.json` is missing, it rebuilds the
  master whitelist from the identities.
- If `whitelist.json` exists but `identities.json` is missing, it migrates the
  master once into the identity source.
- If neither file exists, it creates an empty identity source. For an existing
  server without private files, its current local whitelist is migrated once.

For a manual setup, the real files belong here, never in the repository:

```text
~/.config/gsr/shared/identities.json  # source of truth, mode 600
~/.config/gsr/shared/whitelist.json   # generated file, mode 644
```

Only the generated whitelist is mounted read-only into Minecraft containers;
`identities.json` is never exposed to them.

### Whitelist command

After running bootstrap once, use:

```bash
mc-whitelist list
mc-whitelist add premium PlayerName
mc-whitelist add offline PlayerName
mc-whitelist remove PlayerName [premium|offline|all]
mc-whitelist apply
mc-whitelist audit
```

`add premium` looks up the global Java UUID at Mojang and also allows the
matching deterministic offline UUID. This is necessary because the current
environments use `online-mode=false`: a premium owner can initially receive
the offline UUID before EasyAuth classifies the account.

`add offline` enables only the deterministic offline UUID. The command updates
`identities.json`, rebuilds the master whitelist, and applies it immediately to
the single running environment. Without a running environment, it is applied
on the next start.

A player can deliberately have both a premium and an offline UUID in the
master whitelist. `mc-whitelist audit` verifies that the generated file matches
the private identity source. Changes made directly through the Minecraft game,
RCON, or `whitelist.json` are not authoritative and can be replaced by the next
`mc-whitelist apply`; record permanent changes in `identities.json` or use
`mc-whitelist`.

“Private” means server-local and outside the repository. The generated
whitelist contains no passwords or EasyAuth database data.

## Environment backups

`gsr-backup` keeps exactly one verified, complete local backup for each
environment under `~/.local/share/gsr/backups/`. It is outside the repository,
so bootstrap and Git updates never replace it. It contains the whole Podman
`/data` volume, including the world, player data, EasyAuth database, mods, and
runtime configuration. The private shared whitelist source is copied alongside
it.

Before a planned stop, restart, or environment switch, the service flushes the
Minecraft save. After the container has stopped, its now-idle volume is
exported, compressed with zstd, verified, and made current. The previous local
backup is only removed after the new archive has passed its integrity checks.

The normal server start always uses its live volume; a backup is never mounted
automatically. Direct `podman stop` commands bypass this protection. Use
`systemctl`, `switchenv`, or the bootstrap script for planned maintenance.

```bash
gsr-backup list
gsr-backup verify vanilla
gsr-backup create skyblock
gsr-backup restore vanilla restored-vanilla
```

`create` is only for a stopped environment. The automatic hooks handle running
environments. `restore` verifies the archive and imports it only into a newly
created, separately named volume; it refuses to touch the live volume or any
existing volume. Point an environment at that new volume only after inspecting
it. The saved `shared/` directory is reference material and is not copied back
automatically.

## Quick install
``` bash
curl -fsSL https://raw.githubusercontent.com/itsflipper/FlippersPackwizMods/refs/heads/main/gsr/bootstrap.sh -o /tmp/bootstrap.sh && bash /tmp/bootstrap.sh
```
The bootstrap acts in two modes:
- **[f] fresh install** — clone the repo, symlink the quadlet into the systemd path, build the image, reload and start the service
- **[u] update** — `git pull`, rebuild the image, reload and restart the service

## Pre-Requisite
If multiple users on the host need access to the server, run it under a dedicated service user. ([advice that prompted this](https://github.com/podman-container-tools/podman/discussions/28320#discussioncomment-16233449))

```
# Create a system user with no login shell
sudo useradd -r -m -s /usr/sbin/nologin gsr-podman

# Allocate subuid/subgid ranges — REQUIRED for rootless podman.
# `useradd -r` does NOT do this automatically; without it, image builds
# fail with "no subuid ranges found". Pick a 65536-wide block that doesn't
# overlap existing entries in /etc/subuid and /etc/subgid.
sudo usermod --add-subuids 231072-296607 --add-subgids 231072-296607 gsr-podman

# Enable lingering so systemd user services survive logout
sudo loginctl enable-linger gsr-podman

# Interactive shell for gsr user
sudo machinectl shell gsr-podman@ /usr/bin/bash

# Run a one-off command as the service user
sudo machinectl shell gsr-podman@ /usr/bin/podman ps
```

### _Then continue installation (quick or manual) as `gsr-podman`._

## Dependencies
- Podman
- zstd
- skill

## Manual install
### Create symlink for the gsr directory
```
ln -s /path/to/gsr ~/.config/containers/systemd/gsr/
```

### Build the image
```
podman build -t gsr /path/to/gsr/
```

### Reload SystemD
```
systemctl --user daemon-reload
```

### Start / Stop / Restart
```
systemctl --user start gsr
systemctl --user stop gsr
systemctl --user restart gsr
```

### Logs
```
journalctl --user -u gsr -f
```

### Exec
```
podman exec -it CONTAINERNAME COMMAND
-->

# Poke around inside container
podman exec -it gsr bash

# We enabled rcon, so this is how you can access the MC-Console
podman exec -it gsr rcon-cli
```
