# 2026-08-20 – Repo-Cleanup (veraltete Prototypen & Build-Artefakte)

## Goal
Repo von veralteten Prototypen, Build-Artefakten und Editor-Junk bereinigen (nur Deletions, keine Code-Änderungen).

## Branch
`agent/repo-cleanup`

## Files Changed
- `rasperry pi/` (komplett gelöscht, 61 Dateien) – alter April-Prototyp (Processing-Sender, GameVisualizer inkl. kompiliertem `linux-aarch64` Build ~9.6 MB, alte Pygame-Version). OSC-Protokoll wurde daraus in die aktuellen `bu03_*`-Sketches übernommen.
- `bu03_vr_receiver_processing/bu03_vr_receiver_processing.pde` (gelöscht) – veralteter Processing-Receiver, versteht das neue Game-Protokoll nicht mehr (siehe Session `2026-08-20-bu03-minimal-gameplay.md`).
- `BU03/UWB_2D_Visualizer_Processing/*.autosave` (3 Dateien gelöscht) – Processing-Editor-Autosaves.
- `BU03/AT-Tag-Config.c` (MicroPython-Skript) + `BU03/AT-Tag-Config.ino` (D1-mini-Variante) gelöscht – abgelöst durch `BU03/AT-Tag-Config-ESP32/`.
- `WeAre3.0.canvas` + `WeAre3.0-1.1/1.2/1.3.canvas` gelöscht – alte Obsidian-Canvas-Versionen.
- `DIY 2D and 3D Spatial Tracking with Ultra-Wideband _ Arduino & Pico Guide - Tutorial Australia.html` gelöscht – heruntergeladene Tutorial-Seite (424 KB) im Repo-Root.
- Lokal (untracked, nicht committet): `.DS_Store`-Dateien und `__pycache__/`-Ordner entfernt.

## Commands Executed
- `git checkout -b agent/repo-cleanup`
- `git rm -r "rasperry pi" bu03_vr_receiver_processing ...`
- `git commit -m "chore: remove deprecated prototypes and build artifacts"` (61 files changed, 9936 deletions)

## Notes
- Kein Push – nur lokaler Commit auf `agent/repo-cleanup`.
- `BU03/references/` (PDFs) bleibt unangetastet und ist via `.gitignore` ohnehin untracked.
