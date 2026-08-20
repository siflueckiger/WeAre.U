# OSC-Protokoll: Sender → Receiver

- **Port:** 8000 (UDP)
- **Richtung:** `sender/` (Processing) sendet, `receiver/` (Pygame, VR-Headsets) empfängt
- **Einheiten:** alle Koordinaten in mm, X/Y im Spielfeld-Koordinatensystem (Anchors definieren es)

## Adressen

| Address | Args | Frequenz | Beschreibung |
| --- | --- | --- | --- |
| `/p1/pos` | x, y (mm) | pro Frame | Position Spieler 1 (Tag `0x0000`) |
| `/p2/pos` | x, y (mm) | pro Frame | Position Spieler 2 (Tag `0x0001`) |
| `/coin/pos` | x, y (mm) | 100 ms + sofort bei State-Wechsel | Münz-Position |
| `/game/stats` | state, time_left, p1_score, p2_score | 100 ms + sofort bei State-Wechsel | Game-Status |
| `/start/p1` | x, y (mm) | bei Config-Änderung/Start/Mode-Wechsel | Startzone P1 |
| `/start/p2` | x, y (mm) | bei Config-Änderung/Start/Mode-Wechsel | Startzone P2 |
| `/anchors` | AX0–AX3, AY0–AY3 (8 floats) | bei Start/Mode-Wechsel/Layout-Änderung | Anchor-Geometrie |

## GameStates (`/game/stats`, arg 1)

| Wert | Name | Bedeutung | `time_left` |
| --- | --- | --- | --- |
| 0 | `WAIT` | Spieler müssen in ihre Startzonen (Radius 250 mm) | – |
| 3 | `READY` | Countdown vor Rundenstart | Countdown-Sekunden |
| 1 | `PLAYING` | Runde läuft | Restzeit in Sekunden |
| 2 | `GAMEOVER` | Gewinneranzeige, Auto-Restart | – |

## Regeln (Sender-seitig)

- **Konstanten müssen in Sender und Receiver übereinstimmen:** GameStates, `START_ZONE_RADIUS_MM`, Startzonen-Defaults (`MUST MATCH`).
- WAIT → beide Spieler in Startzone → READY (3 s Countdown); verlässt einer die Zone → zurück zu WAIT.
- PLAYING: Timer läuft ab (`GAME_TIME_S`, aktuell 30), Coin einsammeln bei < `COLLECT_RADIUS_MM` (500) → Score++ + Respawn.
- Coin-Spawn: 500 mm Feldrand, min. 800 mm Abstand zu Spielern, Fairness `|d1-d2| <= 1200 mm`.
- GAMEOVER: 10 s Anzeige → automatisch zurück zu WAIT.

## Setup-Modus (Sender, TAB-Taste)

- Anchor-Distanzen eingeben → Auto-Layout; Startzonen per Tag-Capture (Z/X) oder Maus-Drag.
- `V` speichert `data/config.json`, `R` setzt Standard-Layout 3x7 m zurück.
- Änderungen werden live per `/anchors`, `/start/p1`, `/start/p2` an die Receiver gesynct.
- Standard-Layout: A0=(0,3000), A1=(0,0), A2=(7000,0), A3=(7000,3000); P1_START=(3000,1500), P2_START=(4000,1500).
