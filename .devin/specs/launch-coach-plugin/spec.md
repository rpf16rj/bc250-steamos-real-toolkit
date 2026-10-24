# Spec: BC-250 Launch Coach — per-game Proton options dialog (Decky plugin)

Date: 2026-10-24
Slug: launch-coach-plugin

## Goal

Decky plugin that asks — once per game — which Proton/BC-250 launch options
the user wants, then applies them natively via Steam's own launch-options
field so they persist without the plugin.

## Flow

- `SteamClient.GameSessions.RegisterForAppLifetimeNotifications` fires on
  every game start. If the appid has no stored config → show a modal dialog
  with checkboxes (the same option list as bc250-fsr4-launch-options) +
  buttons: **Save & Restart**, **Save**, **Don't ask for this game**.
- On save: write launch options via `SteamClient.Apps.SetAppLaunchOptions`
  (preserving any pre-existing user options that aren't our managed
  prefixes), persist `{appid: state}` in the plugin settings dir, then
  optionally restart the game (TerminateApp + RunGame, best-effort with
  toast fallback telling the user to relaunch manually).
- Subsequent launches: appid is configured → plugin stays silent.
- Reconfigure anytime: QAM panel lists the last-launched game ("Configure
  current game") and all configured apps with Edit/Reset. Editing an app
  reopens the same checkbox dialog.

## Files

`extras/bc250-launch-coach/` — same layout as the existing plugin:

- `plugin.json` — name "BC-250 Launch Coach", api_version 1
- `main.py` — decky.Plugin backend: JSON store under DECKY_PLUGIN_SETTINGS_DIR
  (`~/.config/bc250-launch-coach` fallback), methods: `get_state`,
  `get_app`, `save_app`, `dismiss_app`, `remove_app`
- `dist/index.js` — raw bundle like the existing plugin:
  `internalAPIConnection.connect(2, name)` → `api.call` for backend,
  `api.toaster`; UI via `window.DFL` (showModal, ModalRoot, ToggleField,
  PanelSection, ButtonItem, staticClasses) and `window.SP_JSX`/`SP_REACT`;
  `window.SteamClient` for launch events + launch options; `window.appStore`
  for display names.
- `install.sh` — same pattern (decky check + copy to ~/homebrew/plugins +
  restart plugin_loader)

## Managed option presets

Same set as the FSR4 plugin: RADV_DIRECTMESH, PROTON_USE_OPTISCALER variants
(helixsr, helixsr-ffx, freefg, freefg-helixsr, fsr411f, signed, fsr411b,
fsr411rc9, fsr411rc10), BC250_FSR4_DEBUG, PROTON_FSR4_UPGRADE=0,
PROTON_OPTISCALER_NAME=dxgi.dll, BC250_FSR4_IGNORE_ANTICHEAT=1,
plain `optiscaler` variant, and the two BC250_OPTISCALER_EXTRA DLSS-spoof
presets (exclusive group). OptiScaler-variant checkboxes are mutually
exclusive.

## Risks / decisions

- Cannot inject env into an already-spawning process → dialog appears on
  first launch and "Save & Restart" relaunches the game so options take
  effect immediately. `RunGame(appid, "", -1, 100)` is best-effort; fallback
  instructs manual relaunch.
- `window.DFL`/`SteamClient` are runtime globals exposed to plugins; a Steam
  client update could rename internals — all accesses are guarded (`?.`) and
  degrade to a toast telling the user to set options manually.
- Only game launches (bRunning transitions) trigger the dialog; non-Steam
  apps still work since launch options apply to them too.
- Persists nothing outside the plugin settings dir; SetAppLaunchOptions is
  the native Steam field (user-visible in Properties → Launch Options).

## Test plan (user, real hardware)

1. install.sh → restart Decky → open a game → checkbox dialog appears once.
2. Select e.g. `helixsr` + `RADV_DIRECTMESH=1` → Save & Restart → verify
   Properties→Launch Options shows the merged string.
3. Relaunch → no dialog. QAM panel → Edit → reconfigure works.
4. "Don't ask" → relaunch → silent forever.
