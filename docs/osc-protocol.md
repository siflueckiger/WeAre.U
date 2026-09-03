# OSC-Protokoll: Sender → Receiver

- **Port:** 8000 (UDP)
- **Richtung:** `sender/` (Processing) sendet, `receiver/` (Pygame, VR-Headsets) empfängt
- **Einheiten:** alle Koordinaten in mm, X/Y im Spielfeld-Koordinatensystem (Anchors definieren es)

## Adressen

| Address | Args | Frequenz | Beschreibung |
| --- | --- | --- | --- |
| `/p1/pos` | x, y (mm) | pro Frame | Position Spieler 1 (Tag `0x0000`) |
| `/p2/pos` | x, y (mm) | pro Frame | Position Spieler 2 (Tag `0x0001`) |
| `/ent/upsert` | id, type, x, y, radius, r, g, b | bei Spawn/Änderung | Entity anlegen/aktualisieren |
| `/ent/pos` | id, x, y (mm) | 100 ms (10 Hz) | Entity-Position (bewegte Entities) |
| `/ent/remove` | id | bei Despawn | Entity entfernen |
| `/game/stats` | state, time_left, p1_score, p2_score, winner | 100 ms + sofort bei State-Wechsel | Game-Status; `winner` = -1 (aus Scores ableiten), 1 oder 2 (erzwungen) |
| `/game/oob` | player (0=P1, 1=P2), seconds_left, active (0/1) | 100 ms | Out-of-bounds-Warnung + Countdown |
| `/game/mode` | mode_id, display_name (Strings) | bei Start/Mode-Wechsel | aktiver Modus |
| `/game/result` | title, subtitle (Strings) | während GAMEOVER | Ergebnis-Anzeige (ersetzt hartkodierten Gewinnertext) |
| `/hud` | line1, line2, … (Strings) | 100 ms (nur PLAYING) | modusspezifischer HUD-Text |
| `/start/p1` | x, y (mm) | bei Config-Änderung/Start/Mode-Wechsel | Startzone P1 |
| `/start/p2` | x, y (mm) | bei Config-Änderung/Start/Mode-Wechsel | Startzone P2 |
| `/anchors` | AX0–AX3, AY0–AY3 (8 floats) | bei Start/Mode-Wechsel/Layout-Änderung | Anchor-Geometrie |

## Entity-Typen (`/ent/upsert`, arg `type`)

Receiver rendert Entities generisch aus `type` + Farbe (RGB kommt vom Sender).
Neue Typen brauchen nur eine zusätzliche Shape in `receiver.py` → `ENTITY_SHAPES`.

| type | Shape | Beispiel |
| --- | --- | --- |
| `coin` | Kreis (gefüllt) | Münze |
| `enemy` | Quadrat | Gegner |
| `powerup` | Ring | Powerup |
| `zone` | Ring (Umriss) | Zielfeld |
| `obstacle` | Rechteck | Hindernis |

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
- PLAYING: Timer läuft ab (`GAME_TIME_S`, aktuell 30), Coin einsammeln bei < `COLLECT_RADIUS_MM` (300) → Score++ + Respawn.
- Coin-Spawn: 500 mm Feldrand, min. 800 mm Abstand zu Spielern, Fairness `|d1-d2| <= 1200 mm`.
- GAMEOVER: 10 s Anzeige → automatisch zurück zu WAIT.

## Out-of-Bounds (`/game/oob`)

- Engine-seitig, gilt in allen Modes: Spieler ausserhalb `fieldBounds()` + `OOB_MARGIN_MM` (400) → Countdown ab `OOB_TIMEOUT_S` (5 s) läuft, bei Rückkehr Reset.
- Countdown = 0 → Runde endet, der andere Spieler gewinnt (Hook `GameMode.onPlayerOut`, von Mode 1 später für Lebens-Verlust überschrieben).
- Warnung erscheint auf Sender und Receiver: `GO BACK NOW OR LOSE A LIFE` + Sekunden.
- Kein Positions-Fix → kein Countdown (Tracking-Verlust wird nie bestraft).

## Setup-Modus (Sender, TAB-Taste)

- Anchor-Distanzen eingeben → Auto-Layout; Startzonen per Tag-Capture (Z/X) oder Maus-Drag.
- `V` speichert `data/config.json`, `R` setzt Standard-Layout 3x7 m zurück.
- Änderungen werden live per `/anchors`, `/start/p1`, `/start/p2` an die Receiver gesynct.
- Standard-Layout: A0=(0,3000), A1=(0,0), A2=(7000,0), A3=(7000,3000); P1_START=(3000,1500), P2_START=(4000,1500).
