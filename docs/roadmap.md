# WeAre.U — Roadmap & Resume Notes

> Stand: 2026-10-10 · Branch: `main` · Sender: **Node.js/TypeScript** (`sender/`)
>
> Diese Datei ist der Einstiegspunkt nach einer Pause. Lies sie, dann weisst du
> wieder, wo du warst und was als Nächstes kommt.

---

## 1. Was ist das Projekt?

VR-Installation „WeAre.U“: 2 Spieler tragen VR-Headsets (Raspberry Pi 3) + UWB-Tags
und sehen sich aus der Vogelperspektive als farbige Punkte in einer digitalen Welt.
Der physische Körper wird zur digitalen Koordinate.

**Architektur (server-authoritative):**

- **`sender/`** (Node.js + TypeScript + Vite, läuft auf dem MacBook) = die
  **GameEngine**: liest UWB-Distanzen per Serial (`serialport`), berechnet
  Positionen (Trilateration + Filter), enthält die komplette Spiellogik, schickt
  alles per OSC an die Pis. Zusätzlich eine **Web-App** im Browser (Operator-UI:
  Retina-Canvas, Touch-Setup, Virtual Play, Stereo-Headset-Testansicht).
- **`receiver/`** (Python/Pygame, läuft auf den 2 Raspberry Pi 3) = **dummer
  Renderer**: empfängt OSC, zeichnet das Spiel (Split-Screen-Stereo pro Auge).
  Keine Spiellogik. Vollständig autark (keine Sender-Imports).
- **OSC-Protokoll v2:** siehe `docs/osc-protocol.md`.

> **Warum alles auf dem MacBook rechnen?** Eine Quelle der Wahrheit → beide Headsets
> sehen immer dieselbe Welt, kein Desync, und Game-Logik-Änderungen brauchen kein
> Redeploy auf die Pis. OSC über LAN ist schnell genug (UDP, ~1–5 ms).
>
> **Warum bleiben die Pi-Receiver Pygame?** Der Pi 3 hat nur 1 GB RAM. Pygame läuft
> direkt auf SDL2/KMS (~35 MB RAM, 1 s Start, stabile 60 FPS); ein Browser/Chromium
> würde ~400 MB belegen und 20 s+ booten. Die Stereo-Ansicht lässt sich aber im
> Sender-Web-UI mit `H` / `?view=vr` auf Laptop/Handy testen.

---

## 2. Dateistruktur (`sender/`)

```
sender/
├── package.json            # Scripts: dev, build, start, sim, test, typecheck
├── tsconfig.json           # Client/Shared
├── tsconfig.server.json    # Node-Server (NodeNext -> dist/)
├── vite.config.ts          # Frontend-Build + Dev-Proxy (/ws -> :3000)
├── index.html
├── config.json             # Anchor-Layout, Startzonen, Modus (gitignored)
├── src/shared/             # Protokoll-Konstanten + WebSocket-Typen (Single Source of Truth)
├── src/server/             # Node-Backend
│   ├── main.ts             # CLI (--headless/--sim/--ip/--target-port/--web-port/--fps)
│   ├── app.ts              # Orchestrator (Tracker, Engine, OSC, Serial, Snapshot)
│   ├── serial.ts           # serialport (115200, usbmodem, Auto-Reconnect) + CmdM:4-Parser
│   ├── tracker.ts          # Trilateration (2x2-Det), Speed-Clamp 4200 mm/s, EMA 0.30
│   ├── engine.ts           # State-Machine WAIT/READY/PLAYING/GAMEOVER, Timer, OOB
│   ├── entities.ts         # EntityManager
│   ├── modes/base.ts       # GameMode-Interface
│   ├── modes/coinHunt.ts   # Mode 1: Coin Hunt
│   ├── osc.ts              # OSC-UDP-Client (Port 8000)
│   ├── setup.ts            # Kalibrierung, applyLayout (Kreisschnitt), config.json
│   ├── virtualTags.ts      # Virtueller Spielmodus (WASD/Pfeile)
│   └── wsServer.ts         # HTTP + WebSocket (statisch + Broadcast 30–60 Hz)
├── src/client/             # Web-Frontend (Vite)
│   ├── main.ts             # WS-Client, Render-Loop, Shortcuts, Setup-Drag
│   ├── canvas.ts           # Retina-Canvas + Stereo-Headset-Ansicht
│   ├── hud.ts              # Header/Footer/Warnungen (DOM)
│   ├── setupOverlay.ts     # Touch-Setup-Panel + Hit-Test
│   └── virtualInput.ts     # Tastatur + Touch-D-Pads
└── test/                   # vitest (parser, tracker, engine/OOB, coinHunt, osc)
```

### Die zwei Kern-Ideen

1. **Engine vs. Modes trennen.** Die Engine besitzt die geteilte State-Machine
   (`WAIT → READY → PLAYING → GAMEOVER`), Startzonen, Countdown, Runden-Timer und
   Out-of-Bounds. Ein Mode implementiert nur den Runden-Inhalt über das
   `GameMode`-Interface (`src/server/modes/base.ts`):

   ```ts
   abstract class GameMode {
     readonly id: string;
     readonly displayName: string;
     onModeEnter(): void {}
     onRoundEnd(): void {}
     abstract onRoundStart(): void;
     abstract update(dt: number): void;
     scores(): [number, number] { return [0, 0]; }
     hudLines(): string[] { return []; }
     resultText(): [string, string] | null { return null; }
     playerLives(_p: number): number { return -1; }
     playerEffects(_p: number): string[] { return []; }
     playerInvuln(_p: number): number { return 0; }
     onPlayerOut(player: number): void { /* default: Runde endet, anderer gewinnt */ }
   }
   ```

2. **Generisches Entity-Protokoll.** Modes spawnen Entities (`coin`, `enemy`,
   `powerup`, `zone`, `obstacle`) über `entities.spawn(type, x, y, radius, color)`.
   Die Engine synct sie per `/ent/upsert` + `/ent/pos` + `/ent/remove`. Der Receiver
   rendert sie generisch aus `type` + Farbe (`ENTITY_SHAPES` in `receiver.py`).
   **Neue Modes brauchen keine Receiver-Änderung.**

---

## 3. Status aller Phasen

| Phase | Ziel | Status |
|---|---|---|
| 0 | Shell-Refactor | ✅ done |
| 1 | Virtueller Spielmodus (Debug ohne Hardware) | ✅ done |
| 2 | OSC v2: generisches Entity-Protokoll + Receiver-Renderer | ✅ done |
| 3 | Mode-Registry (`M`-Taste, `config.json`-Persistenz) | ✅ done |
| 4 | Mode 1 – Coin Hunt (Münzen, Hazards, Lives, Powerups) | ✅ done (getunt) |
| 4b | **Node.js/TypeScript-Umbau + Web-UI + Stereo-Testansicht** | ✅ done |
| **5** | **Mode 2 – Co-op Levels (Zielfelder + bewegliche Hindernisse)** | ⬅️ **NÄCHSTER SCHRITT** |
| 6 | Polish (Sound, Balance, Field-Profiles, Attract-Screen) | ⏳ offen |

---

## 4. Phase 5 — Mode 2 (Co-op Levels) · DER NÄCHSTE SCHRITT

### 4.1 Ziel

Kooperativ: beide Spieler müssen **gleichzeitig** auf ihren farbigen Zielfeldern
stehen, um ins nächste Level zu kommen. Zwischen den Levels bewegen sich Hindernisse.

### 4.2 Entscheidungen (bereits abgestimmt)

- **Hindernis-Berührung → Level zurücksetzen** für beide (Spieler laufen physisch
  zurück zu den Startzonen, Countdown, gleiches Level erneut).
- **Zonen-Hold:** beide müssen **gleichzeitig** 1.5 s in ihren Zonen stehen.
- **Kein Timer** (kein Zeitdruck pro Level).

### 4.3 Umsetzung

1. **Neue Datei `sender/src/server/modes/coop.ts`** — Mode in `engine.ts`
   registrieren: `this.modes = [new CoinHunt(this), new Coop(this)];`.

2. **Kleine Engine-Erweiterung (`engine.ts`):**
   - `GameMode.roundTimeS()` hinzufügen (Default `return GameEngine.GAME_TIME_S;`).
   - `update()` nutzt `roundTimeS()`: bei `> 0` normaler Timer; bei `< 0`
     `timeLeft = -1` (Signal „kein Timer“ an den Receiver) und **kein** Auto-Ende.
   - Mode 2 überschreibt `roundTimeS()` mit `return -1;`.
   - Receiver/Web-HUD zeichnet bei `time_left < 0` keinen Countdown.

3. **Kleiner Receiver-Fix (`receiver.py`):**
   - `draw_game_hud()` zeichnet den Countdown nur wenn `time_left >= 0`.

4. **Mode-Logik (nutzt Engine-States):**
   - `WAIT/READY`: Startzonen (Engine).
   - `PLAYING`: Zielfelder erscheinen; beide Spieler hin, 1.5 s halten → Level fertig.
   - Level fertig → `currentLevel++` (bzw. Run komplett beim letzten Level) →
     `requestEnd()` → `GAMEOVER` mit `resultText()` → zurück zu `WAIT` → nächstes Level.
   - Hindernis-Touch → `requestEnd()` mit `resultText` = „GETROFFEN!“ / „Nochmal!“,
     **ohne** Level zu erhöhen (gleiches Level wird wiederholt).
   - `onRoundStart()` setzt das *aktuelle* Level auf; nach komplettem Run → Reset auf Level 1.

5. **Level-Daten (normalisiert [0..1]):**
   - Jedes Level = P1-Zone (nx, ny), P2-Zone (nx, ny), Liste von Hindernissen.
   - Hindernis = `{ax, ay, bx, by, speed}` (Patrouille hin/her entlang der Linie).
   - Positionen werden beim Setup mit `fieldBounds()` in mm umgerechnet →
     funktioniert auf 3×7 m **und** 7×7 m.
   - Ziel: 4 Start-Levels als Daten-Array.

6. **Entities:**
   - Zielfeld → `zone` (Ring, Spielerfarbe `C_P1`/`C_P2`, `ZONE_RADIUS_MM = 500`).
   - Hindernis → `obstacle` (Rechteck, `OBS_RADIUS_MM`), Bewegung über `/ent/pos`.

7. **Hooks:**
   - `hudLines()` → `"LEVEL 1/4"`.
   - `resultText()` → `"LEVEL 2 GESCHAFFT!"` / `"ALLE LEVELS GESCHAFFT!"` / `"GETROFFEN!"`.

### 4.4 Konzept-Skizze (Pseudocode)

```ts
class Coop extends GameMode {
  readonly id = "coop";
  readonly displayName = "Co-op Levels";
  // ZONE_RADIUS_MM=500, ZONE_HOLD_S=1.5, OBS_RADIUS_MM=300, OBS_TOUCH_RADIUS_MM=450

  currentLevel = 0; runComplete = false; hold = 0;
  resultT: string | null = null; resultS: string | null = null;
  z1!: Entity; z2!: Entity; obstacles: Obstacle[] = [];

  override roundTimeS() { return -1; }            // kein Timer
  override onModeEnter() { this.currentLevel = 0; this.runComplete = false; }
  override onRoundStart() {
    if (this.runComplete) { this.currentLevel = 0; this.runComplete = false; }
    this.resultT = null; this.setupLevel(this.currentLevel);
  }
  override update(dt: number) { this.updateObstacles(dt); this.checkObstacleHit(); this.checkZones(dt); }
  override scores(): [number, number] { return [0, 0]; }
  override hudLines() { return [`LEVEL ${this.currentLevel + 1}/${LEVELS.length}`]; }
  override resultText() { return this.resultT ? [this.resultT, this.resultS ?? ""] : null; }
}
```

---

## 5. Phase 6 — Polish (offen, Ideen)

- Audio/Haptik-Cues (Münze, Treffer, Level-Erfolg).
- Balance von Mode 1 (Hazard-Speed, Powerup-Raten, Lives).
- „Field-Profiles“ im Setup-Modus: mehrere Venue-Layouts speichern (3×7 m, 7×7 m, …).
- Attract/Idle-Screen für die Installation (wenn niemand spielt).
- Optional: OSC-Heartbeat / Reconnect-Robustheit.

---

## 6. Wie bauen & testen

### Sender (Node.js/TypeScript)

```bash
cd sender
npm install
npm run typecheck          # tsc, beide Configs
npm test                   # vitest (24 Tests)
npm run build              # Vite-Client + tsc-Server -> dist/
npm run sim                # virtuelle Spieler (WASD = P1, Pfeile = P2), Web-UI :3000
npm start -- --headless    # reiner Daemon, kein Web-UI
```

### Receiver prüfen

```bash
python3 -m py_compile receiver/receiver.py
```

### Smoke-Test Receiver (ohne Hardware, SDL dummy + Fake-OSC)

```bash
# receiver mit Dummy-Video starten, dann OSC-Pakete schicken:
SDL_VIDEODRIVER=dummy BU03_FLIP_180=0 python3 receiver/receiver.py
# in anderem Terminal: pythonosc SimpleUDPClient auf 127.0.0.1:8000
```

### Operator-Shortcuts (Web-UI)

- `V` = Virtual Play, `R` = Reset, `SPACE` = Rundenstart, `M` = Mode wechseln,
  `TAB` = Setup-Modus, `H` = Stereo-Headset-Ansicht (`?view=vr`).

---

## 7. Wichtige Werte zum Nachjustieren (Mode 1)

Alle in `sender/src/server/modes/coinHunt.ts`:

| Konstante | Wert | Bedeutung |
| --- | --- | --- |
| `COLLECT_RADIUS_MM` | 300 | Münz-Pickup-Distanz |
| `ENEMY_SPAWN_COINS_1 / 2` | 3 / 6 | Hazard 1 / 2 spawnen nach N Münzen (beide zusammen) |
| `ENEMY_SPEED_MM_S` | 600 | Hazard-Geschwindigkeit (diagonal, prallt ab) |
| `ENEMY_CATCH_RADIUS_MM` | 350 | Treffer-Distanz |
| `START_LIVES` | 3 | Leben pro Spieler |
| `POWERUP_INTERVAL_S` | 8 | Abstand zwischen Powerups |
| `MAGNET_PULL_MM_S` | 700 | Magnet: Coin wird zum Spieler gezogen |
| `MAGNET_S / INVIS_S / FREEZE_S` | 5 / 5 / 4 | Effekt-Dauer |

---

## 8. Git-Hinweise

- Aktiver Branch: `main` (Node-Stack ist gemergt und gepusht).
- Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`.
- Session-Log nach Abschluss: `docs/agent-sessions/YYYY-MM-DD-<task>.md`.
