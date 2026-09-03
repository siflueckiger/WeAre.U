# 2026-09-03 – Agent-Session (Game-Modes Core + Virtual Play)

## Goal

Phase 0 + Phase 1 des Multi-Game-Mode-Plans: Sender in eine Engine-Shell und
modulare Tabs aufteilen (GameMode-Framework, ohne Verhaltensänderung) und einen
virtuellen Spielmodus für Debugging ohne UWB-Hardware ergänzen.

## Branch

- `agent/game-modes-core`

## Files Changed

- `sender/Core_GameMode.pde` (new)
  - `GameMode`-Interface (onRoundStart/update/scores/drawWorld/sendOscEntities),
    Mode-Registry, Engine-State-Machine WAIT/READY/PLAYING/GAMEOVER,
    `requestEnd()`/`debugStartRound()`
- `sender/Core_Entities.pde` (new)
  - `fieldBounds()` + `inZone()` – Modes dürfen keine Feldfelder hardcoden
    (Feldgröße variiert je Venue)
- `sender/Core_Osc.pde` (new)
  - OSC-Send-Funktionen zentralisiert (sendPos/sendGameOsc/sendStartZones/sendAnchors)
- `sender/Mode_CoinHunt.pde` (new)
  - Coin-Gameplay aus sender.pde extrahiert, unverändertes Verhalten
- `sender/VirtualTags.pde` (new)
  - Virtuelle Spieler: WASD = P1, Pfeiltasten = P2, 1500 mm/s, Feld-Clamping
  - Speist dieselbe TagData-Pipeline wie Serial-Frames; OSC sendet normal weiter
  - Auto-Engage nach 5 s ohne Serial-Port, V-Toggle, Auto-Off bei Serial-Connect
- `sender/sender.pde` (modified)
  - Engine-Shell: Serial/UWB/Trilateration/Filter/Rendering/HUD + Key-Dispatch
    (TAB, V, 1/2/4, SPACE, Mode-Keys)
- `sender/Setup.pde` (modified)
  - `keyReleased()` ruft jetzt `vKeyUp()` für den virtuellen Modus auf
- `README.md` (modified): Repo-Struktur um neue Tabs ergänzt

## Commands Executed

- `git checkout -b agent/game-modes-core`
- `processing cli --sketch=sender --output=<tmp> --build` – kompiliert ohne Fehler
- `git commit -m "refactor: add game-mode framework, core tabs and virtual play mode"`

## Notes

- OSC-Protokoll ist unverändert (v1) – Receiver wurde nicht angefasst
- Phase 2 (OSC v2, generisches Entity-Protokoll) folgt nach User-Tests
- Processing-Tab-Reihenfolge: sender.pde zuerst, dann alphabetisch –
  Klassen/Globals sind tab-übergreifend referenzierbar
