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

- `shared/identities.json` is the source of truth: it records the exact name,
  deterministic offline UUID, optional Mojang UUID and permitted identities.
- `shared/whitelist.json` is generated from it and used by all environments.
  Neither file is committed to Git.

The old environment-local `whitelist.json` files are intentionally gone. The
placeholder `defaults/whitelist.example.json` is empty and is only used for a
brand-new installation.

### Whitelist command

After running bootstrap once, use:

```bash
mc-whitelist list
mc-whitelist add premium PlayerName
mc-whitelist add offline PlayerName
mc-whitelist remove PlayerName [premium|offline|all]
mc-whitelist audit
```

`add premium` gets the Java account UUID from Mojang and also enables the
matching deterministic offline UUID. This is required because the current
environments use `online-mode=false`; a premium owner can therefore enter with
the offline UUID before EasyAuth classifies the account. `add offline` enables
only the deterministic offline UUID. The command updates `identities.json`,
regenerates the master and applies it immediately to the one running
environment; without a running environment it is applied on the next start.

The same name can deliberately have both a premium and an offline UUID in the
master file. `mc-whitelist audit` verifies that the generated whitelist still
matches its private identity source. Direct whitelist changes in the game or
through RCON are intentionally not imported, because they would bypass UUID
classification.

“Private” here means server-local and outside the repository. The bind-mounted
file is readable by the rootless Minecraft process, but contains no passwords
or account database; those remain only in the profile volume.

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
