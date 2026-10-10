# WeAre.U

> **"Where are you?"** – Eine VR-Installation über räumliche Dissoziation mittels UWB-Tracking.

## Konzept
Die Evolution von *WeAre*. Spieler tragen VR-Headsets (Raspberry Pi) und UWB-Tags. Sie sehen sich selbst aus der Vogelperspektive als abstrakte Punkte. Der physische Körper wird zur digitalen Koordinate.

## Hardware-Details

| Objekt          | Anzahl | Hardware                                       | Aufgabe                                                                                                         | Empfängt Daten von | Sendet Daten an |
| :-------------- | :----: | :--------------------------------------------- | :-------------------------------------------------------------------------------------------------------------- | :----------------- | :-------------- |
| **Tag**         | 2      | Ai-Thinker UWB Technology BU03 DW3000 Plan Kit | Pro Spieler ein Tag auf dem VR Headset                                                                          | -                  | -               |
| **Anchor**      | 4      | Ai-Thinker UWB Technology BU03 DW3000 Plan Kit | Positioniert um das Spielfeld herum, definieren die Anchor das Koordinatensystem und messen Distanzen zu Tags   | -                  | Processor       |
| **Processor**   | 1      | [MICROCONTROLLER]                              | Verarbeitet die Distanzen zwischen Anchors-Tags und berechnet Koordinaten der Spieler                           | Anchors            | GameEngine      |
| **GameEngine**  | 1      | [MICROCONTROLLER]                              | Steuert das ganze Spiel mit allen GameStates und Spiellogiken                                                   | Processor          | VR-Brille       |
| **VR-Brille**   | 2      | RaspberryPi [VERSION] mit [BILDSCHIRM]         | Pro Spieler werden Koordinaten empfangen und das Spiel wird visualisiert                                        | GameEngine         | -               |
| **Headset**     | 2      | _Tag und VR-Brille_                            | -                                                                                                               | -                  | -               |

### Anchor
- **Microcontroller:** 4x Ai-Thinker UWB Technologie BU03 DW3000 Plan Kit Positionsgenauigkeit 10cm
- **Powerbank:** ??

### Headsets
- **RaspberryPi:** 2x RaspberryPi ??
  - *Processing* für die Visualisierung
  - Raspberry Pi with Desktop Raspian is easyier for the Visualisation stuff, no need for X11 etc.
- **VR Screen:** 2x ??
- **Microcontroller:** 2x Ai-Thinker UWB Technologie BU03 DW3000 Plan Kit Positionsgenauigkeit 10cm
- **Powerbank:** 2x ??

### Processor
- **Koordinaten-Rechner:** 1x ESP32 oder Pi Pico oder so, um UWB Distanztdaten in Koordinaten umzuwandeln

### GameEngine
- **GameEngine:** 1x ESP32 oder Pi Pico oder so, um die Game-States zu steuern und Daten per OSC an die Spieler zu schicken

## Software

### Architektur (aktueller Stand)
- **Sender** (`sender/`, Node.js + TypeScript + Vite): läuft auf einem MacBook/Mini-PC, das per USB am Anchor hängt. Liest Tag-Distanzen aus, berechnet Koordinaten, enthält die komplette Game-Logik (GameStates, Coin Hunt, Scores) und schickt alles per OSC an die Receiver. Dazu eine moderne **Web-App** im Browser: scharfes Retina-Canvas, kabellose Touch-Kalibrierung auf iPad/Handy, Virtual-Play ohne Hardware und ein **Stereo-Headset-Testmodus**.
- **Receiver** (`receiver/receiver.py`, Python/Pygame): läuft autark auf den beiden **Raspberry Pi 3** in den VR-Headsets. Empfängt OSC auf Port 8000 und rendert den Stereo-Split-Screen. Bewusst schlank (kein Browser), da der Pi 3 nur 1 GB RAM hat.
- **OSC-Protokoll:** siehe `docs/osc-protocol.md`.

### Sender starten (`sender/`)
```bash
cd sender
npm install
npm start                       # Produktion, Web-UI auf http://<sender-ip>:3000, OSC -> 192.168.1.106:8000
npm run sim                     # ohne Hardware: virtuelle Spieler (WASD / Pfeiltasten)
npm start -- --ip 192.168.1.106 --target-port 8000   # Receiver-IP setzen
npm start -- --headless         # reiner Daemon ohne Web-UI
npm run dev                     # Entwicklung (Vite 5173 + Server 3000)
cd ..
```
Im Browser (`http://<sender-ip>:3000`):
- **TAB** Setup-/Kalibriermodus (Anker-Distanzen, Auto-Layout, Zonen per Touch ziehen, Speichern in `config.json`)
- **V** Virtual Play, **R** Reset, **SPACE** Rundenstart, **M** Modus, **H** oder `?view=vr` Stereo-Headset-Ansicht (zum Testen auf Smartphone/Laptop)

### Receiver starten (`receiver/`, auf jedem Raspberry Pi 3)
```bash
pip install -r receiver/requirements.txt
python receiver/receiver.py
```
Der Receiver ist vollständig autark (keine Imports aus dem Sender).

### Repo-Struktur
```
WeAre.U/
├── README.md              ← diese Datei
├── PROJECT-LOG.md         ← Projekt-Historie
├── sender/                ← Node.js/TypeScript-Sender + Web-App
│   ├── src/server/        ← Serial/UWB, Trilateration, Engine, Coin Hunt, OSC, WebSocket
│   ├── src/client/        ← Canvas-Renderer (Retina + Stereo), HUD, Setup, Virtual Input
│   ├── src/shared/        ← Protokoll-Konstanten und Typen
│   └── test/              ← vitest-Tests (Parser, Tracker, Engine/OOB, Hazards, OSC)
├── receiver/              ← Pygame-Receiver für die Pi-3-VR-Headsets
│   ├── receiver.py
│   └── requirements.txt
└── docs/
    ├── hardware/          ← BU03-Dokumentation (AT-Commands, PDFs)
    ├── osc-protocol.md    ← OSC-Protokoll zwischen Sender und Receiver
    └── agent-sessions/    ← Session-Logs der Agent-Sitzungen
```


