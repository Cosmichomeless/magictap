# How MagicTap works

## Pipeline

```
Magic Mouse ──► MultitouchSupport (private) ──► contact callback
                                                      │  (private thread)
                                                      ▼
                                          main queue: [TouchPoint] + timestamp
                                                      │
                                                      ▼
                                       TapDetector.process(...)  ──► TapAction?
                                                      │
                                                      ▼
                                       ClickPoster.post → CGEvent → HID event tap
```

| Piece | File | Responsibility |
|---|---|---|
| `MultitouchAPI` | `Sources/MagicTap/Multitouch.swift` | Loads the private framework with `dlopen`/`dlsym`; fixed-offset reader for the touch records |
| `MouseMonitor` | `Sources/MagicTap/MouseMonitor.swift` | Picks the Magic Mouse among devices, registers the callback, rescans on wake and every 5 s |
| `TapDetector` | `Sources/MagicTapCore/TapDetector.swift` | Pure state machine: frames in, tap action out. No AppKit, no hardware |
| `ClickPoster` | `Sources/MagicTap/ClickPoster.swift` | Posts left/right mouse down+up; Accessibility trust check |
| `AppDelegate` | `Sources/MagicTap/AppDelegate.swift` | Menu bar UI, wiring, physical-click monitor |
| `Settings` | `Sources/MagicTap/Settings.swift` | `UserDefaults` preferences → `TapConfig` |
| Settings window | `Sources/MagicTap/UI/` | SwiftUI window (gestures, live view, setup); writes `UserDefaults` and posts `.magicTapSettingsChanged` |

The recognition logic lives in its own target (`MagicTapCore`) precisely so it
can be tested without a mouse: tests feed synthetic frames and assert the result.

## Identifying the Magic Mouse

`MTDeviceCreateList()` returns every multitouch surface: built-in trackpad,
Magic Trackpad, Magic Mouse. MagicTap keeps a device only if it is **not
built-in** and its sensor surface is **taller than wide**.

Measured on one machine (macOS 27, Magic Mouse USB-C):

| Device | familyID | `MTDeviceGetSensorSurfaceDimensions` | built-in |
|---|---|---|---|
| MacBook trackpad | 109 | 12480 × 7680 | yes |
| Magic Mouse | 112 | 5152 × 9056 | no |

The aspect-ratio rule is used instead of hard-coding `familyID == 112` so other
Magic Mouse generations keep working. A Magic Trackpad is landscape and is skipped.

## The touch record (private API)

The contact callback has the shape:

```c
void callback(MTDeviceRef device, MTTouch *touches, int count, double timestamp, int frame);
```

Each `MTTouch` record is 96 bytes. MagicTap reads only three fields at fixed
offsets rather than mirroring the whole undocumented struct:

| Offset | Type | Field |
|---|---|---|
| 20 | `Int32` | state (3 = making contact, 4 = touching; others are hover/linger/leave) |
| 32 | `Float` | normalized X (0…1) |
| 36 | `Float` | normalized Y (0…1) |

> These offsets come from community reverse-engineering of the framework and
> should be re-verified on new macOS releases. Run `swift run MagicTap --debug`
> and touch the mouse: the printed coordinates must change smoothly in 0…1.

## Tap recognition rules

One *session* starts when the first finger touches and ends on the frame with
no fingers. The session yields a tap only if:

- duration is within `minTapDuration` (20 ms) … `maxTapDuration` (200 ms);
- accumulated finger path ≤ `maxFingerTravel` (0.04 normalized units). Motion
  is only measured between frames with the *same* finger count, because adding
  or removing a finger moves the centroid without any real movement;
- the cursor moved ≤ `maxCursorTravel` (4 pt) between start and end;
- no physical button event was observed during the session (the global
  monitor calls `noteButtonEvent()`; events caused by MagicTap itself are ignored
  for 150 ms);
- the maximum finger count was 1 (left click) or 2 (right click).

## Double tap

A left-click tap records its end time and cursor position. If the next
one-finger session starts within `doubleTapWindow` (0.5 s) and within
`doubleTapRadius` (8 pt) of it, the session is marked `followsDoubleTap`; when it
ends as a valid tap the detector returns `.doubleClick` instead of `.leftClick`
and forgets the previous tap, so a third tap starts a new pair. `ClickPoster`
posts down/up with `mouseEventClickState` = 2. The first tap has already been
sent as a normal click, exactly like a physical double click. A second touch that
is held instead of lifted still becomes a drag.

## Tap and drag

A left-click tap records its end time. If a new single-finger session starts
within `dragWindow` (0.6 s) it is marked `followsTap`. When that session passes
`maxTapDuration` with the finger still (path ≤ `maxFingerTravel`) the detector
returns `.dragStart` and enters the dragging state; the cursor may move freely
now, because the mouse itself does the dragging. The button goes down at
`dragOrigin` (the cursor position when the touch began, not where it is after
the 0.2 s hold). While dragging, every frame posts `leftMouseDragged`; the
resting-finger filter is disabled so a long drag is not cut. The empty frame
yields `.dragEnd` (button up). `AppDelegate` also releases the button if the app
quits, MagicTap is disabled, or no frames arrive for 1 s (device vanished), so
the button can never stay stuck.

Hold-to-drag skips the tap: a single finger that stays still (path ≤ 0.04) with
the cursor still (≤ 4 pt) for `holdToDragAfter` (0.25 s) also returns
`.dragStart`. The delay must stay below `restingAfter` (0.30 s), otherwise the
grip filter would drop the finger first. Moving the mouse during the wait
discards the session, so resting a finger while repositioning does not drag.

## Why a synthetic click does not loop

`ClickPoster.post` sets `ignoreButtonEventsUntil` before posting. The global
button monitor skips events inside that window, so MagicTap never mistakes its
own click for a physical one.

## Tuning

Edit the defaults in `TapConfig` (`Sources/MagicTapCore/TapDetector.swift`):

| Symptom | Adjust |
|---|---|
| Taps are missed | Raise `maxTapDuration` / `maxFingerTravel` |
| Clicks fire while you just hold or move the mouse | Lower `maxTapDuration`, `maxCursorTravel` or `maxFingerTravel` |
| Single-finger taps misfire a lot | Turn off *Tap → left click* and keep the two-finger right click |

Use `--debug` to see durations and finger positions of your own taps.

## Troubleshooting

**Menu says "No Magic Mouse found".** Check the mouse is connected over
Bluetooth or USB-C. The list refreshes every 5 s and on wake.

**Taps are detected in `--debug` but nothing clicks.** Accessibility permission
is missing. Menu → *Grant Accessibility permission…*. After rebuilding with the
ad-hoc signature you may need to remove and re-add MagicTap in that list.

**Double clicks.** Your physical click and a tap overlapped. The detector cancels
taps during physical presses; if it still happens, lower `maxTapDuration`.

**"Launch at login" shows an error.** It only works from the bundled `.app`
(`scripts/build-app.sh`), not from `swift run`.

**Stopped working after a macOS update.** The private API likely changed. Run
`swift run MagicTap --debug` and open an issue with the macOS version and the output.

## Two-finger swipe and pinch

While exactly two fingers are down, `Session` remembers their centroid and
separation from the frame the second one landed.

- **Swipe.** A centroid move of `swipeDistance` (0.12) toward +y (the tip; sensor
  y grows toward it) with `|dx| <= dy` returns `.missionControl`; toward -y returns
  `.missionControlClose`, which sends Escape only if we opened Mission Control.
  One-shot per contact. If the direction feels reversed, flip the sign in
  `swipeGesture`.
- **Pinch.** A separation change of `pinchStartDistance` (0.05) with a nearly
  still centroid locks the contact as a pinch: `.magnify(amount, .began)`, then
  `.magnify(delta * pinchGain, .changed)` every frame, and `.ended` when a finger
  lifts. The resting-finger filter is off while pinching. `ClickPoster` posts a
  CGEvent of type 29 with the undocumented fields 110 = 8 (magnify),
  113 = magnification, 132 = phase, which apps receive as `NSEvent.magnify`
  (Chrome shows it as smooth page zoom). Keyboard shortcuts (⌘+/⌘−) were tried
  first but are stepwise and depend on the keyboard layout.

## One-finger swipe (back / forward)

A single finger that moves sideways by `navigationStartDistance` (0.05) with
`|dy| <= |dx| / 2` starts `.navigate(dx, .began)`, then `.navigate(delta, .changed)`
every frame and `.ended` when it lifts. `ClickPoster` turns each phase into a
horizontal scroll event with scroll phases (gain `navigationGain`, 1500 px per
sensor unit), which browsers show as their back / forward arrow and act on if the
gesture carries on. The native one-finger gesture is not used; it does not fire on
every setup. Keyboard shortcuts (⌘←/⌘→) were rejected because they jump at once.

## Three-finger hold

A quick three-finger tap is unreliable on this surface: real attempts last
0.2-0.4 s and the third finger often lands at the edge. So the gesture is a hold.
`TapDetector` keeps a separate tracker of **all** contacts (edges included,
`threeFingerEdgeMargin` 0), evaluated before the resting-finger filter. It fires
`.threeFingerTap` once when three contacts that landed within `threeFingerLanding`
(0.25 s) have all been down for `threeFingerHold` (0.5 s), then waits until the
fingers lift. The action comes from `Settings.threeFingerAction`: Show Desktop
(default), middle click, Mission Control or nothing.

Show Desktop calls `CoreDockSendNotification("com.apple.showdesktop.awake", 0)`
(private API, loaded with `dlopen`/`dlsym` from ApplicationServices), which is a
toggle; F11 is sent if the symbol is missing.

**Known cost.** Gripping the mouse by the sides with one more finger resting can
count as three fingers. In a 75 s recording that happened 5 times at 0.5 s, once at
0.9 s and never with an edge margin of 0.15. If it bothers you, raise
`threeFingerHold` or `threeFingerEdgeMargin`, or set the action to *Do nothing*.
