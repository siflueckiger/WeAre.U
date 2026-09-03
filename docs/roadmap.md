# WeAre.U — Roadmap & Resume Notes

> Stand: 2026-09-03 · Branch: `agent/game-modes-core` · last commit `508b000`
>
> Diese Datei ist der Einstiegspunkt nach einer Pause. Lies sie, dann weisst du
> wieder, wo du warst und was als Nächstes kommt.

---

## 1. Was ist das Projekt?

VR-Installation „WeAre.U“: 2 Spieler tragen VR-Headsets (Raspberry Pi) + UWB-Tags
und sehen sich aus der Vogelperspektive als farbige Punkte in einer digitalen Welt.
Der physische Körper wird zur digitalen Koordinate.

**Architektur (server-authoritative):**

- **`sender/`** (Processing, läuft auf dem MacBook) = die **GameEngine**:
  liest UWB-Distanzen per Serial, berechnet Positionen (Trilateration + Filter),
  enthält die komplette Spiellogik und schickt alles per OSC an die Pis.
- **`receiver/`** (Python/Pygame, läuft auf den 2 Raspberry Pis) = **dummer Renderer**:
  empfängt OSC, zeichnet das Spiel (Split-Screen-Stereo pro Auge). Keine Spiellogik.
- **OSC-Protokoll v2:** siehe `docs/osc-protocol.md`.

> **Warum alles auf dem MacBook rechnen?** Eine Quelle der Wahrheit → beide Headsets
> sehen immer dieselbe Welt, kein Desync, und Game-Logik-Änderungen brauchen kein
> Redeploy auf die Pis. OSC über LAN ist schnell genug (UDP, ~1–5 ms).

---

## 2. Dateistruktur (`sender/`)

Processing-Tabs (Reihenfolge: `sender.pde` zuerst, dann alphabetisch; Klassen/Globals
sind tab-übergreifend nutzbar).

| Datei | Inhalt |
| --- | --- |
| `sender.pde` | Engine-Shell: Serial/UWB, Trilateration, Filter, Transform, HUD, Key-Dispatch |
| `Setup.pde` | Setup-Modus (Anchor-Kalibrierung, Startzonen) — TAB-Taste |
| `Core_GameMode.pde` | `GameMode`-Interface, Mode-Registry, Engine-State-Machine |
| `Core_Entities.pde` | Entity-System (`Entity`, spawn/remove/clear, `fieldBounds`, `inZone`) |
| `Core_Osc.pde` | OSC-Send-Funktionen (Entities, Stats, OOB, Mode, Result, Hit, HUD) |
| `Mode_CoinHunt.pde` | Mode 1: Coin Hunt (Münzen, Gegner, Lives, Powerups) |
| `VirtualTags.pde` | Virtueller Spielmodus (WASD/Pfeile, `V`-Toggle) — Debug ohne Hardware |
| `receiver/receiver.py` | Pygame-Receiver (generischer Entity-Renderer) |

### Die zwei Kern-Ideen

1. **Engine vs. Modes trennen.** Die Engine besitzt die geteilte State-Machine
   (`WAIT → READY → PLAYING → GAMEOVER`), Startzonen, Countdown, Runden-Timer und
   Out-of-Bounds. Ein Mode implementiert nur den Runden-Inhalt über das `GameMode`-Interface:

   ```java
   abstract class GameMode {
     String id, displayName;
     void onModeEnter() {}
     abstract void onRoundStart();
     abstract void update(float dt);
     abstract int[] scores();
     abstract void drawWorld();
     float roundTimeS() { return GAME_TIME_S; }   // < 0 = kein Timer (geplant)
     String[] hudLines() { return new String[0]; }   // /hud
     String[] resultText() { return null; }          // /game/result (GAMEOVER)
     void keyPressed(char k) {}
     void onPlayerOut(int player) { /* default: Runde endet, anderer gewinnt */ }
   }
   ```

2. **Generisches Entity-Protokoll.** Modes spawnen Entities (`coin`, `enemy`,
   `powerup`, `zone`, `obstacle`) über `spawnEntity(type, x, y, radius, color)`.
   Die Engine synct sie per `/ent/upsert` + `/ent/pos` + `/ent/remove`. Der Receiver
   rendert sie generisch aus `type` + Farbe (`ENTITY_SHAPES` in `receiver.py`).
   **Neue Modes brauchen keine Receiver-Änderung.**

---

## 3. Status aller Phasen

| Phase | Ziel | Status |
|---|---|---|
| 0 | Shell-Refactor (Tabs, kein Verhaltenswechsel) | ✅ done |
| 1 | Virtueller Spielmodus (Debug ohne Hardware) | ✅ done |
| 2 | OSC v2: generisches Entity-Protokoll + Receiver-Renderer | ✅ done |
| 3 | Mode-Registry (`M`-Taste, `config.json` Persistenz) | ✅ done |
| 4 | Mode 1 – Coin Hunt (Münzen, Gegner, Lives, Powerups) | ✅ done (getunt) |
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

1. **Neue Datei `sender/Mode_Coop.pde`** — Mode registrieren in `Core_GameMode.pde`:
   `GameMode[] modes = { new ModeCoinHunt(), new ModeCoop() };`

2. **Kleine Engine-Erweiterung (`Core_GameMode.pde`):**
   - `GameMode.roundTimeS()` hinzufügen (Default `return GAME_TIME_S;`).
   - `updateGame()` nutzt `roundTimeS()`: bei `> 0` normaler Timer; bei `< 0`
     `timeLeft = -1` (Signal „kein Timer“ an den Receiver) und **kein** Auto-Ende.
   - Mode 2 überschreibt `roundTimeS()` mit `return -1;`.

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
   - Zielfeld → `zone` (Ring, Spielerfarbe `C_T0`/`C_T1`, `ZONE_RADIUS_MM = 500`).
   - Hindernis → `obstacle` (Rechteck, `OBS_RADIUS_MM`), Bewegung über `/ent/pos`.

7. **Hooks:**
   - `hudLines()` → `"LEVEL 1/4"`.
   - `resultText()` → `"LEVEL 2 GESCHAFFT!"` / `"ALLE LEVELS GESCHAFFT!"` /
     `"GETROFFEN!"`.

### 4.4 Konzept-Skizze (Pseudocode)

```java
class ModeCoop extends GameMode {
  float ZONE_RADIUS_MM = 500, ZONE_HOLD_S = 1.5, OBS_RADIUS_MM = 300, OBS_TOUCH_RADIUS_MM = 450;

  int currentLevel = 0;
  boolean runComplete = false;
  float hold = 0;
  String resultT = null, resultS = null;
  Entity z1, z2;
  ArrayList<Obstacle> obstacles = new ArrayList<Obstacle>();

  float roundTimeS() { return -1; }                 // kein Timer

  void onModeEnter() { currentLevel = 0; runComplete = false; }

  void onRoundStart() {
    if (runComplete) { currentLevel = 0; runComplete = false; }
    resultT = null; resultS = null;
    setupLevel(currentLevel);
  }

  void update(float dt) {
    updateObstacles(dt);
    checkObstacleHit();
    checkZones(dt);   // shared 1.5s hold -> completeLevel()
  }

  void completeLevel() {
    if (currentLevel + 1 >= levels.length) { resultT="GESCHAFFT!"; resultS="ALLE LEVELS GESCHAFFT!"; runComplete=true; }
    else { resultT = "LEVEL " + (currentLevel+1) + " GESCHAFFT!"; resultS = "Weiter!"; currentLevel++; }
    requestEnd();
  }

  void hitObstacle() { resultT = "GETROFFEN!"; resultS = "Nochmal!"; requestEnd(); }

  int[] scores() { return new int[] { 0, 0 }; }
  String[] hudLines() { return new String[] { "LEVEL " + (currentLevel+1) + "/" + levels.length }; }
  String[] resultText() { return resultT == null ? null : new String[] { resultT, resultS }; }
}
```

---

## 5. Phase 6 — Polish (offen, Ideen)

- Audio/Haptik-Cues (Münze, Treffer, Level-Erfolg).
- Balance von Mode 1 (Enemy-Speed, Powerup-Raten, Lives).
- „Field-Profiles“ im Setup-Modus: mehrere Venue-Layouts speichern (3×7 m, 7×7 m, …).
- Attract/Idle-Screen für die Installation (wenn niemand spielt).
- Optional: OSC-Heartbeat / Reconnect-Robustheit.

---

## 6. Wie bauen & testen

### Sender kompilieren (Mac, Processing 4.5.2)

```bash
"/Applications/Processing.app/Contents/MacOS/processing" cli \
  --sketch=/Users/simonfluckiger/my-code-projects/WeAre.U/sender \
  --output=/tmp/sender-build --build
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

### Virtueller Spielmodus (Debug ohne UWB)

- Sketch starten → `V` drücken → **WASD = P1**, **Pfeiltasten = P2**.
- `M` = Mode wechseln, `SPACE` = Runde starten, `TAB` = Setup-Modus,
  `1/2` = Filter, `4` = EMA-Alpha.

---

## 7. Wichtige Werte zum Nachjustieren (Mode 1)

Alle in `Mode_CoinHunt.pde`:

| Konstante | Wert | Bedeutung |
| --- | --- | --- |
| `COLLECT_RADIUS_MM` | 300 | Münz-Pickup-Distanz |
| `ENEMY_AFTER_COINS` | 5 | Gegner spawnen nach N Münzen (beide zusammen) |
| `ENEMY_SPEED_MM_S` | 400 | Gegner-Geschwindigkeit |
| `ENEMY_CATCH_RADIUS_MM` | 350 | Fang-Distanz |
| `START_LIVES` | 3 | Leben pro Spieler |
| `POWERUP_INTERVAL_S` | 8 | Abstand zwischen Powerups |
| `MAGNET_PULL_MM_S` | 700 | Magnet: Coin wird zum Spieler gezogen |
| `MAGNET_S / INVIS_S / FREEZE_S` | 5 / 5 / 4 | Effekt-Dauer |

---

## 8. Git-Hinweise

- Branch: `agent/game-modes-core` (Arbeit noch nicht auf `main` gemergt).
- Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`.
- Session-Log nach Abschluss: `docs/agent-sessions/YYYY-MM-DD-<task>.md`.
