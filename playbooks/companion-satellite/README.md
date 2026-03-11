# Companion Satellite

Configures a Debian-based host as a dedicated Companion Satellite. It's primarily used with Raspberry Pi targets, but should work on any Debian-based system (arm64 or x86_64). Node.js is installed from the official tarball and the satellite build is downloaded directly from Bitfocus. The latest stable (arch-specific) version is resolved automatically via the Bitfocus API at run time.

## Run

Provision all satellites:

```bash
ansible-playbook companion-satellite/companion-satellite.yml
```

Provision only `hapideck3` for example:

```bash
ansible-playbook companion-satellite/companion-satellite.yml --limit hapideck3
```

## What it deploys

- **System dependencies**: libusb, libudev, cmake, libfontconfig1
- **Node.js**: Pinned version installed to `/opt/node` from official tarball (arch-detected)
- **Companion Satellite**: Latest stable build from the [Bitfocus API](https://api.bitfocus.io), extracted to `/opt/companion-satellite`
- **udev rules**: Stream Deck USB device permissions (`50-satellite.rules`)
- **systemd service**: `satellite.service` running as the `satellite` user
- **Boot config**: `/boot/satellite-config` with `COMPANION_IP` pointing to myserver

The playbook reboots the host at the end to ensure udev rules take effect for connected USB devices and the service starts cleanly.

## Updating

Re-run the playbook to pick up the latest stable satellite build automatically. The playbook queries the Bitfocus API for the current stable release and skips the download if the installed version already matches. To update Node.js, edit the `node_version` variable in the playbook.

To pin a specific version, pass `satellite_version` and `satellite_url`:

```bash
ansible-playbook companion-satellite/companion-satellite.yml \
  -e satellite_version=v2.6.0 \
  -e satellite_url=https://s4.bitfocus.io/builds/companion-satellite/companion-satellite-arm64-559-eb78b78.tar.gz
```

