# WeAre.U

> **"Where are you?"** – Eine VR-Installation über räumliche Dissoziation mittels UWB-Tracking.

## Konzept
Die Evolution von *WeAre*. Spieler tragen VR-Headsets (Raspberry Pi) und UWB-Tags. Sie sehen sich selbst aus der Vogelperspektive als abstrakte Punkte. Der physische Körper wird zur digitalen Koordinate.

## Technik

### UWB Anchors
- **Microcontroller:** 4x Ai-Thinker UWB Technologie BU03 DW3000 Plan Kit Positionsgenauigkeit 10cm
- **Powerbank:** ??

### Player Headsets
- **RaspberryPi:** 2x RaspberryPi ??
  - *Processing* für die Visualisierung
- **VR Screen:** 2x ??
- **Microcontroller:** 2x Ai-Thinker UWB Technologie BU03 DW3000 Plan Kit Positionsgenauigkeit 10cm
- **Powerbank:** 2x ??

### Weitere Hardware
- **Koordinaten-Rechner:** 1x ESP32 oder Pi Pico oder so, um UWB Distanztdaten in Koordinaten umzuwandeln
- **Game-Engine:** 1x ESP32 oder Pi Pico oder so, um die Game-States zu steuern und Daten per OSC an die Spieler zu schicken

## Software
- **Processing**:
