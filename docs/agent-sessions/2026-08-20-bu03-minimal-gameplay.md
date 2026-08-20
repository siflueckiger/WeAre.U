# 2026-08-20 – BU03 Minimal Gameplay (Sender-Logik + Receiver-Visualisierung)

## Goal
Minimales Gameplay für die WeAre.U VR-Installation: Game-Logik liegt komplett im Processing-Sender (`bu03_visualize_and_send`), der Pygame-Receiver (`bu03_vr_receiver_pygame`) visualisiert nur. OSC-Protokoll aus `rasperry pi/python/weareu_pygame/` übernommen.

## Branch
`agent/bu03-minimal-gameplay`

## OSC-Protokoll (Port 8000)
| Address | Args |
| --- | --- |
| `/p1/pos` | x, y (mm) |
| `/p2/pos` | x, y (mm) |
| `/coin/pos` | x, y (mm) |
| `/game/stats` | state, time_left, p1_score, p2_score |

GameStates: `0=WAIT` (Startzonen), `1=PLAYING`, `2=GAMEOVER`, `3=READY` (Countdown, `time_left` = Countdown-Sekunden).

## Gameplay-Ablauf (Sender)
- WAIT: beide Player müssen in ihre Startzone (Radius 500 mm) → READY (3s Countdown). Verlässt einer die Zone → Abbruch zurück zu WAIT.
- LEERTASTE: Debug-Start direkt in die Runde (überspringt Zonen-Check).
- PLAYING: Timer 180s runterzählen; Münze einsammeln bei < `COLLECT_RADIUS_MM` (500) → Score++ + Respawn.
- Coin-Spawn: Bounding-Box mit 500 mm Rand, min. 800 mm Abstand zu jedem Player, Fairness `|d1-d2| <= 1200 mm` (100 Retries, sonst Fallback).
- GAMEOVER: 10s Gewinneranzeige → automatisch zurück zu WAIT.

## Files Changed
- `bu03_visualize_and_send/bu03_visualize_and_send.pde` (modified)
  - Game-State-Machine, Coin-Spawn/Collect-Logik, Startzonen
  - OSC: `/pos` → `/p1/pos` + `/p2/pos` (pro Frame), `/coin/pos` + `/game/stats` (alle 100 ms, sofort bei State-Wechsel)
  - Preview: Startzonen, Coin, Game-Zeile im HUD
- `bu03_vr_receiver_pygame/bu03_vr_receiver.py` (modified)
  - Handler für die 4 neuen Addresses (ersetzt `/pos`)
  - State-Rendering: WAIT (Startzonen + „Warte auf Spieler..."), READY (Countdown), PLAYING (Coin + HUD: Timer mm:ss, Scores links/rechts), GAMEOVER (Gewinner + Endstand)
  - Game-HUD in beiden Augen, Debug-HUD weiterhin nur links
  - Labels T0/T1 → P1/P2

## Commands Executed
- `git add -A && git commit -m "refactor: rename visualizer and receiver folders" && git push` (auf main, vor dem Branch)
- `python3 -m py_compile bu03_vr_receiver_pygame/bu03_vr_receiver.py`
- Smoke-Test: `SDL_VIDEODRIVER=dummy BU03_FLIP_180=0 python3 bu03_vr_receiver.py` + Fake-OSC-Sender (alle 4 States durchlaufen) – OK, keine Fehler

## Notes
- **Anpassen nötig:** `P1_START`/`P2_START` (Platzhalter 1200/2400 bzw. 5400/700) müssen zur realen Spieler-Aufstellung passen – in Sender UND Receiver ändern (`MUST MATCH`).
- `COLLECT_RADIUS_MM` im Sender zentral änderbar.
- Alter Processing-Receiver (`bu03_vr_receiver_processing`) versteht das neue Protokoll nicht mehr (sendet nur noch `/p1/pos` etc.) – wurde nicht angepasst.
- Processing-Sketch nicht headless kompilierbar (kein `processing-java` installiert) – Test im Processing-Editor nötig.
