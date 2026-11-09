# WeAre.U Sender – Setup-Guide

Der **Sender** (`sender/`) ist die Zentrale des Systems: Er liest die UWB-Distanzen
der BU03-Anchors per USB ein, berechnet daraus die Spieler-Koordinaten
(Trilateration + Filter), enthält die komplette Game-Logik (GameStates, Coin Hunt,
Scores) und schickt alles per **OSC** an die Receiver in den VR-Headsets. Zusätzlich
stellt er eine **Web-Operator-UI** im Browser bereit.

> Kurzfassung für Ungeduldige:
> ```bash
> cd sender
> npm install
> npm run sim        # erster Test ohne Hardware
> npm run dev        # Entwicklung mit Web-UI auf http://localhost:5173
> npm run build && npm start   # Produktionsbetrieb auf http://<sender-ip>:3000
> ```

---

## 1. Voraussetzungen

| Komponente | Anforderung |
| :--- | :--- |
| **Node.js** | `>= 20` (siehe `engines` in `package.json`) |
| **npm** | mit Node.js installiert |
| **UWB-Hardware** | optional – 1–4 BU03-Anchors per USB verbunden (für den Echtbetrieb) |
| **Receiver** | erreichbar im Netzwerk, OSC/UDP auf Port `8000` (Standard-IP `192.168.1.106`) |

Hardware-Details und die Rolle der Anchors stehen im Root-`README.md`.

---

## 2. Installation

```bash
cd sender
npm install
```

Das legt `node_modules/` an und installiert `serialport`, `ws`, `vite`, `tsx`,
`vitest` usw.

---

## 3. Start-Modi

| Befehl | Zweck | Build nötig? |
| :--- | :--- | :---: |
| `npm run sim` | **Ohne Hardware** – virtuelle Spieler (WASD / Pfeiltasten). Ideal für den ersten Test. | nein |
| `npm run dev` | **Entwicklung** – Vite-Dev-Server (`:5173`) + Sender-Server (`:3000`), Hot Reload. | nein |
| `npm run build` | Kompiliert Client (`vite build` → `dist/client`) und Server (`tsc` → `dist/server`). | – |
| `npm start` | **Produktion** – startet das kompilierte `dist/server/main.js`, Web-UI auf `:3000`. | **ja** |
| `npm run headless` | **Daemon-Betrieb** ohne Web-UI, startet `dist/server/main.js`. | **ja** |

> ⚠️ `npm start` und `npm run headless` führen `dist/server/main.js` aus. Nach einem
> frischen Clone oder nach Code-Änderungen zuerst `npm run build` ausführen.
> `npm run sim` und `npm run dev` laufen über `tsx` und brauchen keinen Build.

---

## 4. CLI-Optionen

Alle Optionen werden an den Sender durchgereicht (bei npm mit `--` davor):

```text
--headless          Daemon-Betrieb, keine Web-UI
--sim               virtuelle Spieler (WASD / Pfeiltasten)
--ip <addr>         OSC-Ziel-IP der Receiver       (Standard: 192.168.1.106)
--target-port <n>   OSC-Ziel-Port der Receiver     (Standard: 8000)
--port-hint <s>     Teilstring des seriellen Ports (Standard: usbmodem)
--web-port <n>      Port der Web-UI                (Standard: 3000)
--fps <n>           Engine-Tickrate in Hz           (Standard: 60)
-h, --help          Hilfe anzeigen
```

### Beispiele

```bash
# Receiver-IP und -Port setzen
npm start -- --ip 192.168.1.106 --target-port 8000

# Daemon ohne Web-UI, anderer serieller Port
npm run headless -- --port-hint cu.usbmodem14201

# Simulation mit abweichendem Web-Port und 30 Hz
npm run sim -- --web-port 3030 --fps 30
```

---

## 5. Web-UI bedienen

Nach dem Start ist die Operator-UI erreichbar unter:

```text
http://<sender-ip>:3000
```

| Taste | Funktion |
| :--- | :--- |
| **TAB** | Setup-/Kalibriermodus (Anchor-Distanzen, Auto-Layout, Zonen per Touch ziehen, Speichern in `config.json`) |
| **V** | Virtual Play (virtuelle Spieler) |
| **R** | Reset |
| **SPACE** | Rundenstart |
| **M** | Spielmodus wechseln |
| **H** bzw. `?view=vr` | Stereo-Headset-Ansicht (zum Testen auf Smartphone/Laptop) |

Die Kalibrierung ist auf **Touch** ausgelegt und funktioniert damit auch auf iPad/Handy.

---

## 6. Serieller Port / Hardware

- Der Sender erkennt automatisch den **ersten** Port, dessen Pfad den Teilstring
  `usbmodem` enthält (macOS-Standard), und öffnet ihn mit **115200 Baud**.
- Wird der Port nicht gefunden, hilft ein Blick auf die verfügbaren Geräte:

  ```bash
  ls /dev/cu.*        # macOS
  ls /dev/ttyUSB*     # Linux
  ```

- Anschließend den passenden Teilstring setzen:

  ```bash
  npm start -- --port-hint <teilstring>
  ```

- Der Sender verbindet sich bei Verlust automatisch neu (**Auto-Reconnect**).

Typische Meldung, wenn nichts gefunden wird:

```text
no port matching "usbmodem"
```

→ Kabel prüfen, anderen `--port-hint` verwenden.

---

## 7. Kalibrierung (`config.json`)

- Die Datei `sender/config.json` speichert das Spielfeld-Layout und wird **über den
  TAB-Setup-Modus** erzeugt bzw. aktualisiert.
- Sie ist **gitignored** und existiert in einem frischen Clone **nicht** – der Sender
  fällt dann auf Standardwerte zurück, bis einmalig kalibriert wurde.
- Enthaltene Felder:

  | Feld | Bedeutung |
  | :--- | :--- |
  | `AX`, `AY` | X-/Y-Koordinaten der 4 Anchors (mm) |
  | `D` | Distanzen zwischen den Anchors (mm) |
  | `P1_START`, `P2_START` | Startzonen der beiden Spieler (mm) |
  | `MODE` | Aktiver Spielmodus (z. B. `coinHunt`) |

---

## 8. Tests & Checks

```bash
npm test           # vitest (Parser, Tracker, Engine/OOB, Coin Hunt, OSC)
npm run test:watch # vitest im Watch-Modus
npm run typecheck  # TypeScript-Prüfung (Client + Server)
npm run build      # Produktions-Build
```

---

## 9. Troubleshooting

| Problem | Ursache / Lösung |
| :--- | :--- |
| `no port matching "usbmodem"` | Falscher/kein serieller Port. `--port-hint` anpassen, Kabel prüfen. |
| `npm start` startet nicht / `Cannot find module dist/server/main.js` | Build fehlt → zuerst `npm run build`. |
| Headsets zeigen nichts an | Receiver läuft nicht, falsche IP/Port, oder Firewall blockt UDP/8000. Mit `--ip`/`--target-port` prüfen. |
| Web-UI nicht erreichbar | Anderer Port belegt → `--web-port` setzen; ggf. `http://<sender-ip>:<port>` statt `localhost` verwenden. |
| Keine Spieler sichtbar | Ohne Hardware `--sim` bzw. **V** in der UI aktivieren. |
| Kalibrierung fehlt nach Clone | `config.json` ist gitignored → einmalig TAB-Setup durchführen. |

---

## 10. Receiver starten (Gegenstelle)

Der passende Receiver läuft auf den Raspberry Pi 3 Headsets und ist im Root-`README.md`
beschrieben:

```bash
pip install -r receiver/requirements.txt
python receiver/receiver.py
```

Das OSC-Protokoll zwischen Sender und Receiver ist in `docs/osc-protocol.md` dokumentiert.
