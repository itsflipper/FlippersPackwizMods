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
- `gsr` is the short, grouped server command interface
- `mc-whitelist` maintains one private whitelist for every environment
- `gsr-backup` keeps one verified full-volume backup per environment
- Worlds, player data and runtime configuration remain separate per environment

## Environments

| Environment | Minecraft | Service | Container | Volume | World |
|---|---:|---|---|---|---|
| Vanilla | 26.3 | `gsr.service` | `gsr` | `gayshitdata` | `world-26.3` |
| Skyblock | 26.2 | `skyblock.service` | `skyblock` | `skyblockdata` | `skyblock` |

Both environments use port `25565`; only one may run at a time.

## Server commands

After bootstrap, the grouped command is the normal entry point:

```bash
gsr help
gsr environment list
gsr environment start vanilla
gsr environment stop vanilla
gsr environment status vanilla
gsr whitelist list
gsr backup list
```

The existing `switchenv`, `mc-whitelist`, and `gsr-backup` commands remain as
compatible direct forms. New server management commands should be added below
the matching `gsr environment`, `gsr whitelist`, or `gsr backup` group.

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
gsr whitelist list
gsr whitelist add premium PlayerName
gsr whitelist add offline PlayerName
gsr whitelist remove PlayerName [premium|offline|all]
gsr whitelist apply
gsr whitelist audit
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
gsr backup list
gsr backup verify vanilla
gsr backup create skyblock
gsr backup restore vanilla restored-vanilla
gsr backup restore-server vanilla
```

`create` is only for a stopped environment. The automatic hooks handle running
environments. `restore` verifies the archive and imports it only into a newly
created, separately named volume; it refuses to touch the live volume or any
existing volume. Point an environment at that new volume only after inspecting
it.

`restore-server` is the explicit server-local rollback command. It asks for a
confirmation, protects its source temporarily, creates a fresh backup of the
currently live volume, then replaces the live volume and starts the environment
again. The fresh server backup becomes the rollback point. Only one full backup
is retained at rest; the duplicate source exists only while the restore runs.
The saved `shared/` directory remains reference material and is not copied back
automatically.

### Manual copies to another computer

Run `scripts/bin/gsr-backup-pull` from a checked-out copy of this repository on
the computer that should keep its own copies. Its first command creates a
private local configuration and asks which environments and how many complete
backups that computer should retain:

```bash
scripts/bin/gsr-backup-pull setup
scripts/bin/gsr-backup-pull list
scripts/bin/gsr-backup-pull pull vanilla
scripts/bin/gsr-backup-pull verify vanilla current
```

`setup` stores connection data in `~/.config/gsr-backup-pull/config.json` with
mode 600. Each computer can select different environments and a different
retention count; the default is two total snapshots: `current` and `previous`.
There is no timer and no automatic transfer. A pull asks interactively for the
normal SSH password and the server's sudo password, then keeps the terminal
open while it shows transfer progress and an estimate. The local rotation only
happens after checksum, zstd, tar, and manifest validation succeed. A failed
transfer removes its temporary files and leaves earlier complete snapshots
unchanged.

To later change the connection, selected environments, local destination, or
retention without editing JSON, use `scripts/bin/gsr-backup-pull configure`.
It verifies the selected environments with the server but does not move or
delete existing local backups; a reduced retention is applied only after the
next successful pull.

A complete local backup can export just its world directory to any chosen
directory without assuming a launcher or Minecraft instance layout:

```bash
scripts/bin/gsr-backup-pull export-world vanilla current /path/to/export
```

For example, this produces `/path/to/export/world-26.3/`; the user can then
copy that world folder into the saves location of any suitable launcher. New
backups record the world directory in their manifest. Older backups fall back
to `server.properties` inside the archive.

To restore a verified local snapshot back to the selected server environment:

```bash
scripts/bin/gsr-backup-pull restore-server vanilla previous
```

This command requires an explicit `RESTORE-<environment>` confirmation. It
streams the local snapshot directly to a private server staging directory,
validates it there, and then performs the same protected live-volume restore
as `gsr backup restore-server`. Interrupted uploads are removed from the
staging directory; they never become a restore source.

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
