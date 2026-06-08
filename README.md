## Quick install
``` bash
curl -fsSL https://raw.githubusercontent.com/itsflipper/FlippersPackwizMods/refs/heads/podman/gsr/b
ootstrap.sh -o /tmp/bootstrap.sh && bash /tmp/bootstrap.sh
```

## Dependencies
- Podman

Create symlink for the gsr.container
```
ln -s /path/to/gsr.container ~/.config/containers/systemd/gsr.container
```

Build the image
```
podman build -t gsr /path/to/gsr/
```
