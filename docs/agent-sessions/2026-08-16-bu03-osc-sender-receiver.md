# 2026-08-16-bu03-osc-sender-receiver

## Goal
Add an OSC sender to the BU03 desktop visualizer so UWB tag positions can be streamed
to a Raspberry Pi VR headset, plus create the Pi-side Processing receiver sketch.

## Branch
`agent/bu03-osc-sender-receiver`

## Files Changed
- `bu03_visualizer/bu03_visualizer.pde` (modified)
  - oscP5 + netP5 imports, OSC config block (`OSC_TARGET_IP`, `OSC_TARGET_PORT`, `OSC_ENABLED`, `OSC_LOCAL_PORT`)
  - `OscP5` + `NetAddress` init in `setup()`
  - `sendPos()` helper sending `/pos` with `(int tagId, float x_mm, float y_mm)` per processed fix
  - OSC status line in HUD
- `bu03_vr_receiver/bu03_vr_receiver.pde` (new)
  - Pi-side receiver: listens on port 8000, 2D top-down debug view (grid, anchors, tag dots + trails, status HUD)
  - Anchor positions mirrored from sender; `FULLSCREEN` config flag
  - Stereo split rendering reserved for a follow-up step

## Commands Executed
- `git checkout -b agent/bu03-osc-sender-receiver`
- Compile verification: both sketches preprocessed with Processing 4.5.2's real
  `PdePreprocessor` and compiled with the bundled JDK against core/serial/oscP5 jars:
  `javac -cp core-4.5.2.jar:serial.jar:jssc.jar:oscP5.jar` — COMPILE OK

## Notes
- Sender target: `OSC_TARGET_IP` is a placeholder (`192.168.1.100`); edit to the Pi's IP.
- Protocol: `/pos` message, args `int tagId, float x, float y` (mm).
- Run on Pi: Processing 4 + oscP5 library (Contribution Manager).
- Not committed.
