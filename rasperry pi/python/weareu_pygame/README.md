# WeAreU Pygame Visualizer

Small multi-file Pygame project for Raspberry Pi OS.

## Files

- `main.py` - entrypoint
- `config.py` - constants and tuning values
- `utils.py` - coordinate and text helpers
- `models.py` - player and game object classes
- `osc_receiver.py` - OSC UDP listener
- `visualizer.py` - main game loop and rendering

## Install

```bash
sudo apt update
sudo apt install python3-pygame python3-pip
pip3 install python-osc
```

Or with pip only:

```bash
pip3 install -r requirements.txt
```

## Run

```bash
python3 main.py
```

## OSC inputs

- `/p1/pos x y`
- `/p2/pos x y`
- `/coin/pos x y`
- `/game/stats state time_left p1_score p2_score`

UDP port: `12000`

## Notes

- Made for normal Raspberry Pi OS with desktop.
- ESC exits the program.
- The current view is mirrored onto the left and right half of the window.
