# 2026-08-20 – BU03 Setup-Modus (Anchor-Kalibrierung + Startzonen)

## Goal
Interaktiver Setup-Modus im Sender-Sketch: physisch gemessene Anchor-Distanzen eintippen → Auto-Layout der Anchor-Koordinaten, Startzonen per Live-Tag-Capture oder Maus-Drag markieren, Persistenz in `data/config.json`, Sync der Startzonen per OSC an den Pi-Receiver.

## Branch
`agent/bu03-setup-mode`

## Workflow
1. TAB → SETUP-Modus (Game-Logik pausiert, kein Game-OSC an die Pis)
2. 6 Distanzen eintippen: Pfeiltasten (selektieren/editieren, SHIFT = 1 mm) oder **direkt Ziffern eintippen** (Backspace löschen, Enter bestätigen); Labels als `A0-A1` … `A2-A3`, Panel auf Deutsch
3. `L` → Auto-Layout: A0=(0,0), A1 auf +X-Achse, A2/A3 per Kreisschnitt (positive Y-Seite); D23 als Plausibilitäts-Check (Warnschwelle 200 mm)
4. Feintuning: Anchors + Startzonen per Maus-Drag (Distanzlabels live); selektierte Distanzlinie + beteiligte Anchors werden gelb hervorgehoben
5. `Z`/`X` → aktuelle Tag-Position als P1-/P2-Startzone übernehmen
6. `V` → `data/config.json` speichern; beim Sketch-Start wird automatisch geladen
7. `R` → Standard-Layout 3x7m zurücksetzen

## Standard-Layout (Defaults ohne config.json)
- 7 m breit (X: 0–7000), 3 m tief (Y: 0–3000)
- A0=(0,3000) oben links, A1=(0,0) unten links, A2=(7000,0) unten rechts, A3=(7000,3000) oben rechts
- P1_START=(3000,1500), P2_START=(4000,1500) – mittig, 1 m auseinander

## OSC-Protokoll (neu)
| Address | Args | Bemerkung |
| --- | --- | --- |
| `/start/p1` | x, y (mm) | Startzone P1, an Receiver bei Config-Änderung/Start/Mode-Wechsel |
| `/start/p2` | x, y (mm) | Startzone P2 |
| `/anchors` | 8 floats (AX0–3, AY0–3) | Anchor-Geometrie, an Receiver bei Start/Mode-Wechsel/Layout/Anchor-Drag |

## Files Changed
- `bu03_visualize_and_send/bu03_visualize_and_send.pde` (modified)
  - `MODE_GAME`/`MODE_SETUP` + `appMode`, TAB-Umschaltung in `keyPressed()`
  - `loadConfig()`/`saveConfig()` (JSON in `data/config.json`), `computeD()`, `sendStartZones()`, `sendAnchors()`
  - AX/AY/P1_START/P2_START sind Runtime-Werte (Config überschreibt Defaults)
  - `draw()`: Game-Logik/OSC nur im GAME-Modus; Setup über `setupDraw()`
  - Wechsel SETUP→GAME resettet GameState auf WAIT
  - Defaults auf Standard-Layout 3x7m geändert
- `bu03_visualize_and_send/Setup.pde` (new)
  - Distanz-Panel (deutsch, Labels `A0-A1`…), Distanzlinien + mm-Labels zwischen den 6 Anchor-Paaren
  - `applyLayout()` (Auto-Layout mit Dreiecksungleichungs-Check), `captureZone()`, `standardLayout()`
  - Maus-Drag für Anchors/Zonen (`mousePressed`/`mouseDragged`/`mouseReleased`)
  - Selektierte Distanz: gelbe Linie/Label + gelbe Anchor-Umrandung (`drawAnchorHighlight()`)
  - Direkte Zahleneingabe (Ziffern-Puffer, Backspace/Enter/ESC)
- `bu03_vr_receiver_pygame/bu03_vr_receiver.py` (modified)
  - Handler für `/start/p1`, `/start/p2`, `/anchors`; `P1_START`/`P2_START` mutable Listen
  - Defaults auf 3x7m-Standard; `START_ZONE_RADIUS_MM` auf 250 (matcht Sender)

## Commands Executed
- Merge `agent/bu03-minimal-gameplay` → `main` (552c8bc), Branch remote+local gelöscht
- Layout-Mathe in Python verifiziert (alle 6 Distanzen exakt rekonstruiert, Noise-Test 0.5% → D23-Err 37.6 mm)
- `python3 -m py_compile bu03_vr_receiver_pygame/bu03_vr_receiver.py`
- Smoke-Test: `SDL_VIDEODRIVER=dummy` + Fake-OSC-Sender inkl. `/start/p1`/`/start/p2`/`/anchors` – alle States fehlerfrei

## Notes
- Processing-Sketch nicht headless kompilierbar – Test im Processing-Editor nötig (TAB, Pfeile, Ziffern, L, R, Z/X, V, Drag).
- `data/config.json` wird beim ersten `V` angelegt; ohne Datei gelten die 3x7m-Defaults.
- Bereits gespeicherte config.json überschreibt die Defaults – `R` im Setup-Modus oder Datei löschen zum Zurücksetzen.
- Spiegellage des Auto-Layouts (alle Anchors auf +Y-Seite) bei Bedarf per Maus-Drag korrigieren.
- Map-Ausrichtung in VR (Nordung) wäre ein möglicher Follow-up (Koordinatenrotation).
