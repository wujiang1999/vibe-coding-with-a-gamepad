# Design notes

How this tool is put together, and why each decision was made.

## Goal

Drive macOS entirely from a gamepad — keyboard keys, pointer, clicks, scrolling — so a coding agent can be operated from a couch, a standing desk, or anywhere a mouse is inconvenient. It has to be one small binary, start at login, and never leave a modifier stuck.

## Why GameController + CGEvent

Three layers were on the table:

| Approach | Verdict |
|---|---|
| Virtual HID device (`IOHIDUserDevice`) | Most "native" events, but needs entitlements/root, driver-like plumbing, and a second failure surface. Overkill. |
| Third-party mappers (Karabiner, ControllerMate, Steam Input) | Karabiner has no gamepad support; the others are Steam-scoped, unmaintained, or closed. None expose analog sticks well. |
| **GameController (input) + CGEvent (output)** | Zero dependencies, first-party APIs, one file. Requires only Accessibility permission. **Chosen.** |

The trade-off is that synthetic events are marked as such: secure input fields ignore them (correctly), and a few apps filter them. That is acceptable for a personal control surface.

## Input layer

`GCController` exposes every physical control through `physicalInputProfile.elements` — a dictionary of `GCControllerButtonInput` (buttons and triggers) and `GCControllerDirectionPad` (sticks and D-pad).

- **Poll at 120 Hz** on the main run loop instead of using per-element value-changed handlers. One code path for every element, deterministic edges, and the same tick drives pointer motion.
- **Edge detection by hand**: keep the previous pressed state per element, emit only on change. The first tick after connect only *primes* the table, so a button already held at launch does not fire.
- **Triggers are buttons.** `GCControllerButtonInput.value >= 0.5` counts as pressed; no analog travel is used.
- **Stick-displacement pseudo-buttons are ignored.** Profiles also expose `Left Thumbstick Up/Down/Left/Right` with a threshold as low as 0.13; mapping those would fire constantly. The sticks are read as axes instead.

## Output layer

`CGEvent` posts into the HID event tap:

| Output | API |
|---|---|
| Keys | `CGEvent(keyboardEventSource:virtualKey:keyDown:)` with accumulated `CGEventFlags` |
| Pointer | `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)` at an absolute position |
| Drag | same call with `.leftMouseDragged` while the physical left button is held |
| Clicks | `.leftMouseDown`/`.leftMouseUp`, `.rightMouseDown`/`.rightMouseUp`, `.otherMouse*` |
| Scroll | `CGEvent(scrollWheelEvent2Source:units:.pixel,wheelCount:2,…)` |

Two details matter:

- **Absolute positioning, not deltas.** `CGEvent` mouse moves take a screen coordinate, so the tool keeps no delta state and cannot accumulate drift. It reads the live cursor position each tick (`CGEvent(source: nil)?.location`), adds this frame's displacement, and clamps to the union of all active displays (`CGGetActiveDisplayList` + `CGDisplayBounds`).
- **Modifier flags are tracked, not posted.** A modifier element on the pad adds its `CGEventFlags` to a running mask and every subsequent key event carries it. This is what makes "hold X, tap A" produce `Option+Enter`. The mask is cleared on release, disconnect, and shutdown.
- **A modifier's own flag is removed before its key-up is posted.** The `flags` field on a posted event *is* the modifier state the receiver sees, so a key-up that still carries its own flag reads as "still held". The receiver then sees no state change on the next press of the same button and ignores it — the classic "second press does nothing until another key is pressed" symptom. Verified with a listening `NSTextView`/`NSView` probe (`experiments/flags-probe.swift`): the buggy order yields `flagsChanged option=true` for both down and up, the fixed order alternates `true`/`false`.

## Pointer feel

Naive `value * speed` feels either sluggish or uncontrollable. The curve is:

```
t   = (|v| - deadzone) / (1 - deadzone)      // rescale past the deadzone to [0, 1]
dir = sign(v) * t                            // per axis
m   = min(1, hypot(dir.x, dir.y))            // clamp diagonals
v'  = maxSpeed * m^exponent                  // speed curve
Δ   = unit(dir) * v' * dt                    // per-frame displacement
```

- **Deadzone rescaling** removes the dead band instead of just zeroing it, so motion starts smoothly rather than jumping.
- **Magnitude-based curve**, not per-axis, so diagonals do not accelerate twice.
- **`dt` from `CFAbsoluteTimeGetCurrent()`**, clamped by `maxStep`: after a stall (debugger, sleep, compaction) the pointer moves one bounded step instead of teleporting across the screen.
- **Sign conventions**: gamepad Y is positive-up, CG screen Y is positive-down — the Y delta is negated. Scroll follows the same rule (`wheel1` positive = content up).

Measured on the reference device: 1219 px/s and 1317 px/s on sustained full-deflection pushes against the original 1400 px/s ceiling, with the other axis unchanged and clean clamping at the screen edges. The ceiling was later raised to 1600 px/s after tuning.

## Mapping model

`bindings.json` is authoritative: a missing key means unbound, `null` means deliberately unbound. Defaults live in the source only to bootstrap a new file.

Actions are strings so the file stays flat and diff-friendly:

- `"escape"`, `"f12"`, `"up"` → keyboard codes from the built-in table
- `"mouse:left"` / `mouse:right` / `mouse:middle` → mouse buttons

One element maps to one action. Key combinations (Cmd+C) are not supported yet — that needs a list-valued schema, which is deliberately deferred.

Tuning lives separately in `pointer.json` so the common adjustment (feel) does not require touching bindings or rebuilding.

Both files reload on `SIGHUP`: release everything held, re-read, rebuild the table, resume. No process restart, no permission re-grant.

## Coordinate systems

The two macOS coordinate spaces differ and mixing them is a classic bug:

- `NSEvent.mouseLocation` / `NSScreen.frame` — origin bottom-left.
- `CGEvent.location` / `CGDisplayBounds` — origin top-left of the main display, Y down.

This tool stays entirely inside the CG space.

## Process lifecycle and safety

- `NSApplication` in `.accessory` mode: no Dock icon, no window, run loop for timers and notifications.
- `SIGINT`/`SIGTERM` → release all held keys and mouse buttons, then exit. `SIGHUP` → reload config.
- Controller disconnect → release all, clear the edge table.
- Startup posts a key-up for every bound key to clear state left by a previous crash.
- `KeepAlive` + `ThrottleInterval 5` under launchd: death is recovered in five seconds.

## Permissions (TCC)

Posting events requires Accessibility. The grant is tied to the *process identity*:

- Running from a terminal → grant the terminal.
- Running under launchd → grant the binary itself.
- With an **ad-hoc** signature the designated requirement is just `cdhash H"…"`, so every rebuild produces a new identity and the grant is invalidated.
- With a **stable signing identity** the requirement becomes `identifier "button-keys" and certificate leaf = H"…"` — the cdhash is no longer part of it, so the grant survives rebuilds. `build.sh` signs with `SIGN_IDENTITY` (default `ButtonKeys Local`) when that identity exists, and falls back to ad-hoc with a warning otherwise.

Runtime configuration still lives in JSON + `SIGHUP`, because rebuilding is slower than editing a file and because not every environment has a signing identity. A Developer ID certificate (paid) is the variant that also works for distribution and survives machine changes; a local self-signed certificate is tied to this keychain.

## Verification

- Every state transition is logged (press/release, stick engage/center, config reload), so behavior can be asserted from the log rather than by eye.
- Pointer motion was verified by sampling `CGEvent.location` at 100 ms and checking monotonic single-axis segments, speed against the configured ceiling, axis isolation, and edge clamping.
- Scroll has no observable telemetry; it is verified visually.

## Known limits / roadmap

- One element → one key; no combinations, no macros.
- No per-app profiles.
- Scroll direction and speed are global.
- Y-axis/axis inversion is a global constant rather than a config flag.
- GameController visibility quirk: a freshly started process can miss an already-connected pad until it reconnects (`GCController.controllers()` was empty in probes while the long-running daemon kept receiving events). Discovered in practice; the daemon tolerates it by attaching on connect notifications.
