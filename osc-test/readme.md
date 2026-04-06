## 📡 OSC-Protokoll-Spezifikation

Die Kommunikation erfolgt über das **oscP5** Framework. Alle Daten werden in einem einzigen Paket gebündelt, um sicherzustellen, dass die Darstellung auf dem Raspberry Pi absolut synchron zum Spielverlauf bleibt.

### Netzwerk-Konfiguration
* **Protokoll:** UDP
* **Port (Empfänger):** `12001`
* **Adresse:** `/game/sync`

### Daten-Struktur (Payload)
Die Nachricht besteht aus 10 Argumenten in einer fest definierten Reihenfolge:

| Index | Typ     | Variable    | Beschreibung                      |
| :---- | :------ | :---------- | :-------------------------------- |
| **0** | `int`   | `state`     | 0: Menu, 1: Play, 2: GameOver     |
| **1** | `float` | `p1x`       | X-Position Spieler 1 (Blau)       |
| **2** | `float` | `p1y`       | Y-Position Spieler 1 (Blau)       |
| **3** | `float` | `p2x`       | X-Position Spieler 2 (Rot)        |
| **4** | `float` | `p2y`       | Y-Position Spieler 2 (Rot)        |
| **5** | `float` | `coinX`     | X-Position Münze (Gelbes Quadrat) |
| **6** | `float` | `coinY`     | Y-Position Münze (Gelbes Quadrat) |
| **7** | `int`   | `timeLeft`  | Countdown in Sekunden             |
| **8** | `int`   | `scoreP1`   | Punkte Blau                       |
| **9** | `int`   | `scoreP2`   | Punkte Rot                        |

### 1. Voraussetzungen
* **Processing 4.x** auf beiden Geräten installiert.
* **Library:** Installiere über den Contribution Manager (Sketch -> Library einbinden): `oscP5` von Andreas Schlegel.
* Beide Geräte müssen sich im **selben Netzwerk** befinden.

### 2. Konfiguration des Senders
1. Öffne den Sender-Sketch auf deinem Hauptrechner.
2. Suche die Zeile im `setup()`: 
   `receiverAddress = new NetAddress("127.0.0.1", 12001);`
3. Ersetze `"127.0.0.1"` durch die IP-Adresse deines Raspberry Pi (z. B. `"192.168.1.50"`).
