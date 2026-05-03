# mnalmahmud-overlay

Muhtasham's personal overlay of Gentoo GNU/Linux ebuilds.

This overlay may contain packages that are not yet in the official Portage tree,
newer versions of existing packages, or experimental ebuilds. Quality is not
guaranteed. Use at your own risk.

Issues and pull requests are welcome.

## Adding the overlay

### Using eselect-repository (recommended)

```bash
# Install eselect-repository if not already present
emerge --ask app-eselect/eselect-repository

# Add the overlay
eselect repository add mnalmahmud-overlay git https://github.com/mnalmahmud/mnalmahmud-overlay.git

# Sync the overlay
emerge --sync mnalmahmud-overlay
```

### Using layman

```bash
# Install layman if not already present
emerge --ask app-portage/layman

# Add the overlay
layman -o https://raw.githubusercontent.com/mnalmahmud/mnalmahmud-overlay/main/repositories.xml -f -a mnalmahmud-overlay

# Sync the overlay
layman -s mnalmahmud-overlay
```

## Packages

| Package | Description |
|---------|-------------|
| *(more packages coming soon)* | |

## Disclaimer

These ebuilds are provided as-is with no warranty. They may not conform to
official Gentoo QA standards. Always review ebuilds before installing packages
from unofficial overlays.
