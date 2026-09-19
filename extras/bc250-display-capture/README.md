# BC-250 Display Capture

Decky Quick Access plugin for collecting display diagnostics across a KDE Desktop
Mode to SteamOS Game Mode/gamescope session switch.

## What it captures

- Kernel journal from the current boot (`journalctl -k -b -f`)
- DRM connector state and available modes
- VRR/DSC/HDR/bpc/colorspace properties from `drm_info`
- `modetest` connector and property snapshots
- GPU clock and utilization
- Snapshots at start, every five seconds, and stop

The collector runs as a temporary systemd service, so it is not tied to the
Decky UI process or the KDE session. It continues while KDE closes and
gamescope starts.

## Usage

1. Install from the SteamOS desktop:

   ```bash
   ./install.sh
   ```

2. Open the plugin from Decky's Quick Access Menu.
3. Press **Start collection** before reproducing the display problem.
4. Switch sessions and test 4K120/VRR/DSC in gamescope.
5. Return to the plugin and press **Stop and package**.

Archives are written to:

```text
~/bc250-display-captures/YYYYMMDD-HHMMSS.tar.gz
```

The plugin only reads diagnostic state and does not change display settings,
EDID, kernel parameters, or GPU configuration.

The committed `dist/index.js` is the shipped frontend — no build is needed to
install. To rebuild it from `src/` (requires node + pnpm), run
`./install.sh --build`.
