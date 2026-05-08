#include <Arduino.h>

// USB serial for monitor/logging
static const uint32_t USB_BAUD = 115200;

// UART to AT module
static const uint32_t TAG_BAUD = 115200;

// BU03 config from tutorial:
// AT+SETCFG=<id>,<mode>,<channel>,<rate>
// id: 0..7
// mode: 0=tag, 1=base station
// channel: 0 or 1 (all boards must match)
// rate: 0 or 1 (all boards must match)
static const uint8_t BU03_ID = 0;
static const uint8_t BU03_MODE = 0;    // 0=tag
static const uint8_t BU03_CHANNEL = 1; // tutorial recommendation
static const uint8_t BU03_RATE = 1;    // tutorial recommendation

// UART2 pins (often labeled RX2/TX2 on ESP32 boards).
// If your silkscreen labels differ, keep wiring to the pins used below.
static const int TAG_RX_PIN = 16;
static const int TAG_TX_PIN = 17;

HardwareSerial tagUart(2); // UART2

String readTagResponse(uint32_t waitMs) {
  String response;
  uint32_t start = millis();

  while (millis() - start < waitMs) {
    while (tagUart.available() > 0) {
      int c = tagUart.read();
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

  tagUart.print(cmd);
  tagUart.print("\r\n");

  String response = readTagResponse(responseWaitMs);
  if (response.length() > 0) {
    Serial.println(response);
  } else {
    Serial.println("(no response)");
  }
}

void setup() {
  Serial.begin(USB_BAUD);
  delay(200);

  // UART2 setup with explicit pins
  tagUart.begin(TAG_BAUD, SERIAL_8N1, TAG_RX_PIN, TAG_TX_PIN);
  delay(100);

  Serial.println("AT tag config start (ESP32)...");

  // Same flow as provided tutorial script, with configurable values above.
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
  sendAT("AT+GETCFG", 100);

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

  // Print unsolicited data from module.
  while (tagUart.available() > 0) {
    Serial.write((char)tagUart.read());
  }
}
