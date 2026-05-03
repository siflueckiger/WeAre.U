#include <Arduino.h>

// USB serial for monitor/logging
static const uint32_t USB_BAUD = 115200;

// UART to BU03 AT interface
static const uint32_t BU03_BAUD = 115200;

// BU03 config from tutorial:
// AT+SETCFG=<id>,<mode>,<channel>,<rate>
// id: 0..7
// mode: 0=tag, 1=base station (anchor)
// channel: 0 or 1 (all boards must match)
// rate: 0 or 1 (all boards must match)
static const uint8_t BU03_ID = 3;      // Anchor 0 (change for Anchor 1..7)
static const uint8_t BU03_MODE = 1;    // 1=anchor/base station
static const uint8_t BU03_CHANNEL = 1; // tutorial recommendation
static const uint8_t BU03_RATE = 1;    // tutorial recommendation

// ESP32 UART2 pins (often labeled RX2/TX2)
// BU03 TX1 -> ESP32 RX2
// BU03 RX1 -> ESP32 TX2
static const int BU03_RX_PIN = 16;
static const int BU03_TX_PIN = 17;

HardwareSerial bu03Uart(2); // UART2

String readBu03Response(uint32_t waitMs) {
  String response;
  uint32_t start = millis();

  while (millis() - start < waitMs) {
    while (bu03Uart.available() > 0) {
      int c = bu03Uart.read();
      if (c >= 0) {
        response += (char)c;
      }
    }
    delay(2);
  }

  return response;
}

void sendAT(const char *cmd, uint32_t responseWaitMs) {
  Serial.print("\n> ");
  Serial.println(cmd);

  bu03Uart.print(cmd);
  bu03Uart.print("\r\n");

  String response = readBu03Response(responseWaitMs);
  if (response.length() > 0) {
    Serial.println(response);
  } else {
    Serial.println("(no response)");
  }
}

void setup() {
  Serial.begin(USB_BAUD);
  delay(200);

  bu03Uart.begin(BU03_BAUD, SERIAL_8N1, BU03_RX_PIN, BU03_TX_PIN);
  delay(100);

  Serial.println("AT anchor config start (ESP32)...");

  char setCfgCmd[32];
  snprintf(
      setCfgCmd,
      sizeof(setCfgCmd),
      "AT+SETCFG=%u,%u,%u,%u",
      BU03_ID,
      BU03_MODE,
      BU03_CHANNEL,
      BU03_RATE);

  Serial.print("Applying config: ");
  Serial.println(setCfgCmd);

  sendAT(setCfgCmd, 1000);
  delay(3000);
  sendAT("AT+SAVE", 3000);
  sendAT("AT+GETCFG", 200);

  Serial.println("\nDone.");
}

void loop() {
  // Optional interactive bridge:
  // Type an AT command in Serial Monitor and send with newline.
  if (Serial.available() > 0) {
    String line = Serial.readStringUntil('\n');
    line.trim();
    if (line.length() > 0) {
      sendAT(line.c_str(), 500);
    }
  }

  while (bu03Uart.available() > 0) {
    Serial.write((char)bu03Uart.read());
  }
}
