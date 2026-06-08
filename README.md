## Quick install
``` bash
curl -fsSL https://raw.githubusercontent.com/itsflipper/FlippersPackwizMods/refs/heads/main/gsr/bootstrap.sh -o /tmp/bootstrap.sh && bash /tmp/bootstrap.sh
```

## Start / Stop / Restart
```
systemctl --user start gsr
systemctl --user stop gsr
systemctl --user restart gsr
```

## Logs
```
journalctl --user -u gsr -f
```

## Exec
```
podman exec -it CONTAINERNAME COMMAND
-->
podman exec -it gsr bash         # Fish around inside container
podman exec -it gsr rcon-cli     # Minecraft commands
```

## Dependencies
- Podman
- skill

Create symlink for the gsr.container
```
ln -s /path/to/gsr.container ~/.config/containers/systemd/gsr.container
```

Build the image
```
podman build -t gsr /path/to/gsr/
```
