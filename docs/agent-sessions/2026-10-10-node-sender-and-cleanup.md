# 2026-10-10 – Agent-Session (Node-Sender, Web-UI & Cleanup)

## Goal

Den Sender von Processing/Python auf einen modernen **Node.js / TypeScript +
Vite Web-App**-Stack (`sender/`) umbauen, den Receiver autark machen und die
veralteten Sender-Implementierungen entfernen. Zusätzlich eine Stereo-Headset-
Testansicht im Web-UI.

## Branch

- `agent/node-sender` – nach `main` gemergt (`merge: node sender with web UI and
  stereo headset view`) und gepusht. Danach alle `agent/*`-Branches lokal + remote
  gelöscht.

## Files Changed

- `sender/` (neu, Node.js/TypeScript)
  - `src/server/serial.ts` – `serialport` (115200 Baud, `usbmodem`, Auto-Reconnect),
    Streaming-Parser für binäre BU03-`CmdM:4`-Pakete (Header, Längen-Byte Offset 6
    `== 91`, Frame 101 B, `tagid` UInt16LE@11, `mask` UInt8@16, 8x Kalman UInt32LE@50)
  - `src/server/tracker.ts` – 4-Anker-Trilateration (2x2-Determinante wie
    `sender.pde:377`), Speed-Clamp (4200 mm/s), EMA (α = 0.30), 60-Punkte-Trail
  - `src/server/engine.ts` – State-Machine WAIT/READY/PLAYING/GAMEOVER, zentrales
    Cleanup bei `setState(WAIT)`, OOB (400 mm Toleranz, 5 s Countdown)
  - `src/server/modes/coinHunt.ts` – Coin Hunt (fairer Coin-Spawn, progressive
    abprallende Hazards bei 3/6 Coins, Powerups MAGNET/INVIS/FREEZE/DOUBLE/LIFE);
    `onPlayerOut` = −1 Leben statt sofortigem Rundenende
  - `src/server/entities.ts`, `modes/base.ts`, `setup.ts`, `virtualTags.ts`
  - `src/server/osc.ts` – eigener UDP-OSC-Client (Port 8000), exakt protokoll-konform
  - `src/server/wsServer.ts` – HTTP + WebSocket, Broadcast 30–60 Hz, Setup-Befehle
  - `src/server/app.ts`, `main.ts` – Orchestrator + CLI
    (`--headless`, `--sim`, `--ip`, `--target-port`, `--port-hint`, `--web-port`, `--fps`)
  - `src/client/` – `canvas.ts` (Retina + Stereo), `hud.ts`, `setupOverlay.ts`
    (Touch/Mobile), `virtualInput.ts`, `main.ts`
  - `src/shared/protocol.ts`, `src/shared/types.ts` – Protokoll + WS-Typen
  - `test/` – vitest: Parser, Tracker, Engine/OOB, CoinHunt, OSC-Encoding (24 Tests)
- `receiver/receiver.py` (modified)
  - `from shared import protocol`-Block entfernt → vollständig autark
  - Fallback-Startzonen auf Standard 3x7m gesetzt (`P1 [3000,1500]`, `P2 [4000,1500]`)
  - veraltete `sender.pde`-Kommentare aktualisiert
- Gelöscht: `sender/*.pde` (Processing), `sender_py/` (Python), `shared/protocol.py`
- `README.md`, `.gitignore`, `docs/roadmap.md`, `docs/osc-protocol.md` aktualisiert

## Commands Executed

- `git checkout -b agent/node-sender`
- `npm install`, `npm run typecheck`, `npm run build`, `npm test` (24 passed)
- OSC-Smoke-Test: `node dist/server/main.js --sim --headless --ip 127.0.0.1`
  gegen einen `python-osc`-Listener → alle Adressen korrekt empfangen
- `git mv sender_node sender`; `git rm -r sender sender_py shared`
- `git merge --no-ff agent/node-sender`; `git push origin main`
- `git branch -d` + `git push origin --delete` für alle `agent/*`

## Notes

- **Receiver bleibt Pygame:** Raspberry Pi 3 (1 GB RAM) → ~35 MB RAM, 1 s Start,
  stabile 60 FPS. Ein Browser/Chromium wäre mit ~400 MB und 20 s+ Boot ungeeignet.
- **Stereo-Headset-Testansicht:** `H` oder `?view=vr` im Web-UI, bildet den
  Split-Screen/`EYE_OFFSET_MM = 150`-Parallaxe des Receivers nach.
- Protokoll (`docs/osc-protocol.md`) ist unverändert; Receiver braucht keine
  funktionalen Änderungen.
- `sender/config.json` (Layout/Startzonen/Modus) ist gitignored.
