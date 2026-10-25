# Vibe Coding with a Gamepad

A tiny macOS daemon that turns a gamepad into a keyboard **and** a mouse, so you can drive an AI coding agent — or anything else on your Mac — from the couch.

One Swift file, no dependencies, no network, no telemetry.

```
gamepad ──► GameController ──► binding table ──► CGEvent ──► macOS
            (120 Hz poll)       bindings.json     keys / mouse / scroll
```

## Features

- **All 17 physical buttons** addressable through one table; unbound entries are explicit `null`.
- **Left stick → pointer.** Absolute cursor positioning with a deadzone and a power acceleration curve, so it is slow when nudged and fast when pushed.
- **Right stick → scrolling.** Both axes (vertical and horizontal), pixel units — trackpad-grade feel.
- **Triggers as mouse buttons.** LT = left click (hold + move = drag), RT = right click.
- **Hot-reload.** Edit `bindings.json` or `pointer.json`, send `SIGHUP`, no rebuild and no permission loss.
- **Launchd-ready.** Starts at login, restarts within 5 s if it dies.
- **Fail-safe.** Releases every held key and mouse button on disconnect, `SIGINT`, `SIGTERM`, or config reload — modifiers never stick.

Default mapping:

| Gamepad | Output |
|---|---|
| A | Enter |
| B | Delete ⌫ |
| X | Left Option ⌥ |
| Y | Esc |
| LT / RT | Mouse left / right button |
| Left stick | Pointer movement |
| Right stick | Scroll (vertical + horizontal) |
| D-pad, LB/RB, L3/R3, Menu, Options, Home | unbound |

## Requirements

- macOS (developed on macOS 26.6, Apple Silicon)
- Xcode Command Line Tools (`swiftc`)
- A gamepad exposed through Apple's GameController framework (Xbox-profile / XInput pads work; verified with a BEITONG A1N3)
- Accessibility permission for the process that posts events

## Build and run

```bash
# One-time: create a self-signed code-signing certificate named "ButtonKeys Local"
# (Keychain Access → Certificate Assistant → Create a Certificate → Code Signing),
# or pass your own with SIGN_IDENTITY=... ./build.sh
./build.sh
./button-keys            # run in the foreground, Ctrl+C to quit
./button-keys --verbose  # also log unbound buttons, useful while tuning
./button-keys --selftest # fire one Option+Enter through the real code path
./button-keys --version  # print the build version
./button-keys --tap "Button B"   # fire a single binding
```

First run asks for Accessibility: **System Settings → Privacy & Security → Accessibility**, enable the terminal (foreground) or the binary (launchd). Without it, events are silently dropped.

## Configuration

Both files live next to the binary and are reloaded on `SIGHUP`:

```bash
kill -HUP $(pgrep -f 'button-keys/button-keys')
```

### `bindings.json`

Element name → action. `null` means unbound.

```json
{
  "Button A": "enter",
  "Button Y": "escape",
  "Button X": "option",
  "Left Trigger": "mouse:left",
  "Right Trigger": "mouse:right",
  "Left Shoulder": null
}
```

- Action is a key name from the built-in `keyCodes` table (`enter`, `escape`, `a`…`z`, `f1`…`f12`, `up`/`down`/`left`/`right`, `option`, `command`, `shift`, `control`, …).
- Actions starting with `mouse:` are mouse buttons: `mouse:left`, `mouse:right`, `mouse:middle`.
- Modifier keys register their `CGEventFlags`, so holding `option` on the pad makes subsequent presses `Option+whatever`.

### `pointer.json`

```json
{
  "deadzone": 0.15,
  "exponent": 1.7,
  "maxSpeed": 1600,
  "scrollDeadzone": 0.18,
  "scrollExponent": 1.5,
  "maxScroll": 1400,
  "maxStep": 0.05
}
```

| Key | Meaning |
|---|---|
| `deadzone` / `scrollDeadzone` | Ignore stick drift below this magnitude |
| `exponent` / `scrollExponent` | Acceleration curve; larger = slower start |
| `maxSpeed` | Pointer speed at full deflection, points/second |
| `maxScroll` | Scroll speed at full deflection, pixels/second |
| `maxStep` | Per-frame time clamp, prevents teleporting after a stall |

Delete the file and it is regenerated with these defaults.

## Run as a login item (launchd)

Create `~/Library/LaunchAgents/com.example.gamepad-keys.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.example.gamepad-keys</string>
    <key>ProgramArguments</key>
    <array><string>/absolute/path/to/button-keys</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>5</integer>
    <key>StandardOutPath</key><string>/tmp/gamepad-keys.log</string>
    <key>StandardErrorPath</key><string>/tmp/gamepad-keys.log</string>
</dict>
</plist>
```

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.gamepad-keys.plist
launchctl print gui/$(id -u)/com.example.gamepad-keys
launchctl kickstart -k gui/$(id -u)/com.example.gamepad-keys   # restart
```

Under launchd the **binary itself** needs Accessibility permission, not the terminal.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Log says missing Accessibility after a rebuild | With an ad-hoc signature the TCC grant is pinned to the binary's cdhash, so every rebuild invalidates it. Sign with a stable identity instead (`build.sh` does this automatically when `ButtonKeys Local` exists); the grant then survives rebuilds. Otherwise re-add the binary in the Accessibility list and `launchctl kickstart -k`. |
| Buttons do nothing, no log lines | Element names differ for your pad. Run with `--verbose` and compare against `controller.physicalInputProfile.elements`. |
| Pointer drifts on its own | Raise `deadzone` in `pointer.json`; cheap sticks rest above 0.1. |
| A modifier is stuck | Send `SIGTERM` — the signal handler releases every held element. |
| Events work in a terminal but not from launchd | Different TCC identity; grant the binary, not the terminal. |

## Design notes

See [`docs/DESIGN.md`](docs/DESIGN.md) for the reasoning behind the input polling model, the CGEvent output layer, the pointer curve, the coordinate-system traps, and the permission model.

## Privacy

Everything is local. No network access, no analytics, no identifiers. Button mappings and tuning stay in two JSON files next to the binary.

## License

MIT — see [LICENSE](LICENSE).

中文说明见 [README.zh-CN.md](README.zh-CN.md)。
