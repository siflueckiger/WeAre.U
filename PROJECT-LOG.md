# WeAre.U Projektlog

## 20.08.2026

### Was wir heute gemacht haben

- Repo aufgeräumt und neu strukturiert (`sender/` + `receiver/` + `docs/`)
- Prototyp Headset bauen
- Prototyp Game-Logik (Coin-Sammeln, Scores, GameStates)
- `sender.pde` hat einen Setup-Mode (TAB), um die Distanzen der Anchors zu erfassen und die Startpositionen der Player festzulegen
- Anfangen mit 3D Druck Stuff

### Next

- ???

## 20.08.2026 – Agent-Session (Minimal Gameplay)

### Goal

Minimales Gameplay für die VR-Installation: Game-Logik liegt komplett im Processing-Sender, der Pygame-Receiver visualisiert nur.

### Branches

- `agent/bu03-minimal-gameplay` – gemergt nach `main`

### Files Changed

- `sender/sender.pde` (modified)
  - Game-State-Machine (WAIT/READY/PLAYING/GAMEOVER), Coin-Spawn/-Collect-Logik, Startzonen
  - OSC: `/p1/pos` + `/p2/pos` (pro Frame), `/coin/pos` + `/game/stats` (alle 100 ms, sofort bei State-Wechsel)
- `receiver/receiver.py` (modified)
  - Handler für die neuen Addresses, State-Rendering, Game-HUD in beiden Augen, Labels T0/T1 → P1/P2

### Notes

- `P1_START`/`P2_START` müssen in Sender und Receiver übereinstimmen (`MUST MATCH`)
- Alter Processing-Receiver (`bu03_vr_receiver_processing`) wurde nicht angepasst (protokoll-inkompatibel)

## 20.08.2026 – Agent-Session (Setup-Modus)

### Goal

Interaktiver Setup-Modus im Sender: Anchor-Distanzen eingeben → Auto-Layout, Startzonen per Tag-Capture oder Maus-Drag, Persistenz in `data/config.json`, Sync per OSC an den Receiver.

### Branches

- `agent/bu03-setup-mode` – gemergt nach `main`

### Files Changed

- `sender/sender.pde` (modified)
  - `MODE_GAME`/`MODE_SETUP` + TAB-Umschaltung, `loadConfig()`/`saveConfig()`
  - Neue OSC-Adressen: `/start/p1`, `/start/p2`, `/anchors` (Sync an Receiver)
- `sender/Setup.pde` (new)
  - Distanz-Panel (6 Anchor-Distanzen), Auto-Layout per Kreisschnitt, Maus-Drag für Anchors/Zonen

### Notes

- Bedienung: Pfeiltasten/Ziffern für Distanzen, `L` Auto-Layout, `Z`/`X` Startzonen-Capture, `V` speichern, `R` Standard-Layout 3x7m
- `data/config.json` überschreibt die Defaults; Test im Processing-Editor nötig

## 20.08.2026 – Agent-Session (Repo-Cleanup & Restrukturierung)

### Goal

Repo bereinigen und sauber strukturieren: veraltete Prototypen und Build-Artefakte löschen, Code-Ordner rollenbasiert benennen, OSC-Protokoll zentral dokumentieren.

### Branches

- `agent/repo-cleanup` – Deletions + Renames, gemergt nach `main` und gepusht

### Files Changed

- Gelöscht: `rasperry pi/` (alter April-Prototyp), `bu03_vr_receiver_processing/`, alte BU03-ESP32-Sketches + `.autosave`-Dateien, `WeAre3.0*.canvas`, Tutorial-HTML, kompilierte JARs (~9.6 MB)
- Umbenannt: `bu03_visualize_and_send/` → `sender/`, `bu03_vr_receiver_pygame/` → `receiver/`, BU03-Doku → `docs/hardware/`
- `docs/osc-protocol.md` (new), `README.md` (modified)

### Notes

- Neue Struktur: `sender/` + `receiver/` + `docs/` (hardware, osc-protocol.md, agent-sessions)
- Processing-Konvention: Ordnername = Haupt-`.pde`-Name

## 16.08.2026 – Session

**it works!**
Zwei Tags gleichzeitig über einen Anchor auszulesen funktioniert.

### Was wir heute gemacht haben

- Processing-Sketch, der die Tags visualisiert, direkt an einem MacBook per USB-C; daran ist A0 angeschlossen, liest Daten aus, visualisiert und sendet sie per OSC an den Raspberry Pi
- Auf dem Pi: VR-Sketch mit Visualisierung funktioniert

### Next

- Was wird wo berechnet? Wahrscheinlich von BU03 auf dem MacBook: MacBook berechnet bzw. zeigt das Spiel und schickt OSC-Infos an die Pis
- VR-Headsets bauen
- Powerbanks recherchieren (für BU03 und für Headsets) – ACHTUNG: low power mode

## 16.08.2026 – Agent-Session (Code-Arbeit)

### Goal

Pygame-Variante des BU03-VR-Receivers für den Raspberry Pi (VR-Brille 800x480), mit Split-Screen-Stereo-Ansicht und 180°-Flip für das kopfstehend montierte Display.

### Branches

- `agent/bu03-pygame-receiver` – initiale Pygame-Portierung
- `agent/bu03-pygame-splitscreen` – Split-Screen für VR-Brille 800x480
- `agent/bu03-pygame-flip` – 180°-Rotation (Display kopfstehend)
- Alles gemergt nach `main` und gepusht

### Files Changed

- `bu03_vr_receiver_pygame/bu03_vr_receiver.py` (new)
  - OSC-Receiver auf Port 8000 (python-osc), `/pos` mit `(tagId, x, y)` in mm
  - Grid (500 mm), Anchors A0–A3, Tag-Dots mit Trails, Status-HUD
  - Split-Screen: linke/rechte Augen-Hälfte je 400x480, `EYE_OFFSET_MM = 150` Parallaxe
  - `FLIP_180` (Default an, Override: `BU03_FLIP_180=0`) für kopfstehendes Display
- `bu03_vr_receiver_pygame/requirements.txt` (new): `python-osc`, `pygame`

### Commands Executed

- `git checkout -b agent/bu03-pygame-receiver` / `-splitscreen` / `-flip`
- Smoke-Tests: `SDL_VIDEODRIVER=dummy` + Fake-OSC-Sender (`/pos` Pakete an 127.0.0.1:8000) – OK

### Notes

- Pi: PEP 668 → Installation in venv (`python3 -m venv .venv`)
- Start via SSH ohne Desktop: `SDL_VIDEODRIVER=KMSDRM python3 bu03_vr_receiver.py`
- Alternative zum Software-Flip: `display_rotate=2` in `/boot/firmware/config.txt`

## 10.07.2026

- Next: Superduper-KI-Plan auschecken

## 09.07.2026

- Herausgefunden, dass über den USB-Port TTL AT-Commands von der Arduino IDE an BU03 gehen
- Sollte gehen, unsere Idee

### Probleme

- Aktuell kommt nichts vom ESP am PC an – weder von T noch von A
- Wissen nicht, was wir auslesen müssen
- Wissen nicht, ob wir Distanzen von A1–A4 zu T1/T2 mit einem ESP differenzieren können

### Next

- Daten auslesen von Anchor oder Tag via ESP
  - Bsp.: T1 zu A1 2.4 m, T2 zu A2 3.1 m, …
- Fragen: Firmware aktuell? Finden wir bessere Dokus?

### Links

- https://aithinker-static.oss-cn-shenzhen.aliyuncs.com/docs/_media_old/BU03_BU04_AT_command_en_v1.0.6.pdf
- https://docs.ai-thinker.com/en/uwb_1/index.html
