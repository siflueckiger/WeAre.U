# Session Log: Python Sender Port

## Goal
Port the Processing sender (`sender/`) to Python for a unified stack with the
Pygame receiver, plus real threading (serial never blocked by rendering) and a
future-proof headless mode.

## Branch
`agent/python-sender`

## New Layout
- `shared/protocol.py` — single source of truth for GameStates, anchor defaults,
  start zones, colors and OSC addresses. `receiver/receiver.py` now imports it
  (with a standalone fallback for the Pis).
- `sender_py/` — the Python sender:
  - `tracker.py` — Trilateration + speed clamp + EMA (1:1 port of `sender.pde`).
  - `serial_reader.py` — background thread, `CmdM:4` binary frame parser.
  - `osc_client.py` — python-osc output (protocol v2).
  - `entities.py`, `engine.py` — entity system + game state machine.
  - `modes/base.py`, `modes/coin_hunt.py` — Coin Hunt incl. bouncing hazards.
  - `virtual_tags.py` — WASD/arrow simulation.
  - `gui.py`, `setup_mode.py` — Pygame operator UI + TAB calibration.
  - `main.py` — loop, key dispatch, `--headless` / `--sim` CLI.
  - `requirements.txt` — pygame, python-osc, pyserial.

## Notes
- The Processing sketch in `sender/` is left untouched as a fallback/reference.
- Verified: all modules compile, headless `--sim` runs WAIT -> READY -> PLAYING,
  GUI renders without exceptions, coin/hazard logic validated, receiver still
  starts with the shared protocol import.
