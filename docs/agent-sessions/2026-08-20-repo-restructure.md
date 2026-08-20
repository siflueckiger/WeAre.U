# 2026-08-20 – Repo-Restrukturierung (sender/receiver/docs)

## Goal
Repo sauber strukturieren: Rollenbasierte Ordnernamen statt Implementierungsnamen, Doku zentralisieren, OSC-Protokoll als Referenz-Dokument extrahieren. Vorher wurden zusätzlich vom User gelöschte, ungenutzte BU03-Sketches übernommen.

## Branch
`agent/repo-cleanup`

## Files Changed
- Gelöscht (User-Deletions, committet): 6 alte BU03-ESP32-Sketches (`AT-Anchor-*`, `AT-CmdM4-*`, `AT-Tag-Config-ESP32`), alter `UWB_2D_Visualizer_Processing.pde`
- Umbenannt (`git mv`):
  - `bu03_visualize_and_send/` → `sender/` (Haupt-Datei → `sender.pde`; `Setup.pde` bleibt Tab)
  - `bu03_vr_receiver_pygame/` → `receiver/` (`bu03_vr_receiver.py` → `receiver.py`)
  - `BU03/BU03-AT-Commands.md` → `docs/hardware/bu03-at-commands.md`
  - `BU03/references/` → `docs/hardware/references/` (PDFs aus Git-Tracking entfernt, bleiben lokal – `.gitignore` angepasst)
- `README.md` (modified): Abschnitt Software ersetzt durch aktuelle Architektur (Sender/Receiver) + Repo-Struktur
- `docs/osc-protocol.md` (new): OSC-Adressen, GameStates, Spielregeln, Setup-Sync – aus Session-Notes extrahiert
- Code-Kommentare in `sender.pde`/`receiver.py`: Referenzen auf alte Dateinamen aktualisiert
- `docs/agent-sessions/2026-08-20-repo-cleanup.md` (aus vorheriger Session)

## Commands Executed
- `git commit -m "chore: remove unused BU03 sketches"`
- `git mv`-Renames, `git rm --cached` für PDFs
- `python3 -m py_compile receiver/receiver.py` (Smoke-Test OK)
- `git commit -m "refactor: restructure repo into sender/receiver/docs"`

## Notes
- Kein Push – Commits lokal auf `agent/repo-cleanup`.
- Processing-Konvention: Ordnername = Haupt-`.pde`-Name (`sender/sender.pde`) – beim Umbenennen im Editor beachten.
- `docs/hardware/references/` (PDFs) ist gitignored und untracked.
- Session-Notes und `PROJECT-LOG.md` behalten alte Namen (Historie, bewusst nicht umgeschrieben).
