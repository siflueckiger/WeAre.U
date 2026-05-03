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
- **Processing**:
