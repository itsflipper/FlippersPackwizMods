# GSR - Personalized Fabric Server

### INCLUDES
- Modpack managed via Packwiz (see `index.toml` for Mod-info)
- MC-Server:
  - Podman Quadlet using [itzg/minecraft-server](https://hub.docker.com/r/itzg/minecraft-server) as base image
  - Fetches the modpack automatically
  - `whitelist.json` baked in via the Containerfile (because we're lazy). Might add auto world `COPY` later too
  - Bootstrap script for both fresh installs and updates

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
