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
- **Sender** (`sender/`, Processing): läuft auf einem MacBook, das per USB am Anchor hängt. Liest Tag-Distanzen aus, berechnet Koordinaten, enthält die komplette Game-Logik (GameStates, Coin, Scores) und schickt alles per OSC an die Receiver.
- **Receiver** (`receiver/`, Python/Pygame): läuft auf den Raspberry-Pi-VR-Headsets. Empfängt OSC auf Port 8000 und visualisiert das Spiel (Split-Screen-Stereo für beide Augen).
- **OSC-Protokoll:** siehe `docs/osc-protocol.md`.

### Repo-Struktur
```
WeAre.U/
├── README.md              ← diese Datei
├── PROJECT-LOG.md         ← Projekt-Historie
├── sender/                ← Processing-Sketch (Engine-Shell + Game-Modes + OSC-Sender)
│   ├── sender.pde         ← Engine: Serial/UWB, Trilateration, Filter, Rendering, HUD
│   ├── Setup.pde          ← Setup-Modus (Anchor-Kalibrierung, Startzonen)
│   ├── Core_GameMode.pde  ← GameMode-Interface + Engine-State-Machine (WAIT/READY/PLAYING/GAMEOVER)
│   ├── Core_Entities.pde  ← gemeinsame Helper (fieldBounds, inZone)
│   ├── Core_Osc.pde       ← OSC-Send-Funktionen
│   ├── Mode_CoinHunt.pde  ← Mode 1: Coin Hunt
│   └── VirtualTags.pde    ← virtueller Spielmodus (WASD/Arrow-Keys, Debug ohne Hardware)
├── receiver/              ← Pygame-Receiver für VR-Headsets
│   ├── receiver.py
│   └── requirements.txt
└── docs/
    ├── hardware/          ← BU03-Dokumentation (AT-Commands, PDFs)
    ├── osc-protocol.md    ← OSC-Protokoll zwischen Sender und Receiver
    └── agent-sessions/    ← Session-Logs der Agent-Sitzungen
```

