#include <Arduino.h>

static const uint32_t USB_BAUD = 115200;
static const uint32_t BU03_BAUD = 115200;

// ESP32 UART2 pins for BU03 distance UART (PA2/PA3 side on BU03)
// BU03 TX -> ESP32 RX2
// BU03 RX -> ESP32 TX2
static const int BU03_RX_PIN = 16;
static const int BU03_TX_PIN = 17;

HardwareSerial bu03Uart(2);

static uint32_t rxByteCount = 0;
static uint32_t skippedUntilHeader = 0;
static unsigned long lastRxMs = 0;
static unsigned long lastStatusMs = 0;

bool decodeUwbDistances(uint8_t *data, int dataLen, float *distances) {
  // Initialize all distances to -1 (equivalent to None)
  for (int i = 0; i < 8; i++) {
    distances[i] = -1.0f;
  }

  if (dataLen < 35) {
    return false;
  }

  // BU03 firmware variants may use different 2nd/3rd header bytes.
  // We only require the frame marker 0xAA and minimum frame length.
  if (data[0] != 0xAA) {
    return false;
  }

  // Extract distance data (skip header, process 4-byte chunks)
  for (int i = 0; i < 8; i++) {
    int byteOffset = 3 + (i * 4);
    if (byteOffset + 3 < dataLen) {
      uint32_t distanceRaw = ((uint32_t)data[byteOffset]) |
                             ((uint32_t)data[byteOffset + 1] << 8) |
                             ((uint32_t)data[byteOffset + 2] << 16) |
                             ((uint32_t)data[byteOffset + 3] << 24);

      if (distanceRaw > 0) {
        distances[i] = distanceRaw / 1000.0f;
      }
    }
  }

  return true;
}

void printDistances(float *distances, bool validData) {
  if (!validData) {
    Serial.println("Invalid data received");
    return;
  }

  for (int i = 0; i <= 3; i++) {
    Serial.print("BS");
    Serial.print(i);
    Serial.print(": ");
    if (distances[i] > 0) {
      Serial.print(distances[i], 3);
      Serial.println("m");
    } else {
      Serial.println("Not visible");
    }
  }
  Serial.println("------------------------------");
}

void setup() {
  Serial.begin(USB_BAUD);
  bu03Uart.begin(BU03_BAUD, SERIAL_8N1, BU03_RX_PIN, BU03_TX_PIN);

  delay(200);
  Serial.println("BU03 ReadDistance ESP32 start");
  Serial.print("UART2 RX pin: ");
  Serial.println(BU03_RX_PIN);
  Serial.print("UART2 TX pin: ");
  Serial.println(BU03_TX_PIN);
  Serial.println("Waiting for UART data...");
}

void loop() {
  static uint8_t buffer[256];
  static int bufferIndex = 0;
  static bool messageStarted = false;

  while (bu03Uart.available()) {
    uint8_t incomingByte = (uint8_t)bu03Uart.read();
    rxByteCount++;
    lastRxMs = millis();

    if (!messageStarted && incomingByte == 0xAA) {
      messageStarted = true;
      bufferIndex = 0;
      buffer[bufferIndex++] = incomingByte;
    } else if (!messageStarted) {
      skippedUntilHeader++;
    } else if (messageStarted) {
      buffer[bufferIndex++] = incomingByte;

      if (bufferIndex >= 35) {
        Serial.print("Header bytes: 0x");
        Serial.print(buffer[0], HEX);
        Serial.print(" 0x");
        Serial.print(buffer[1], HEX);
        Serial.print(" 0x");
        Serial.println(buffer[2], HEX);

        Serial.print("Raw data: b'");
        for (int i = 0; i < bufferIndex; i++) {
          if (buffer[i] >= 32 && buffer[i] <= 126) {
            Serial.print((char)buffer[i]);
          } else {
            Serial.print("\\x");
            if (buffer[i] < 16) {
              Serial.print("0");
            }
            Serial.print(buffer[i], HEX);
          }
        }
        Serial.println("'");

        float distances[8];
        bool validData = decodeUwbDistances(buffer, bufferIndex, distances);
        printDistances(distances, validData);

        messageStarted = false;
        bufferIndex = 0;
      }

      // Prevent buffer overflow.
      if (bufferIndex >= 256) {
        messageStarted = false;
        bufferIndex = 0;
      }
    }
  }

  // Emit periodic status so we can diagnose wiring/port problems quickly.
  if (millis() - lastStatusMs > 1000) {
    lastStatusMs = millis();
    Serial.print("[status] rxBytes=");
    Serial.print(rxByteCount);
    Serial.print(", skippedUntil0xAA=");
    Serial.print(skippedUntilHeader);
    Serial.print(", msSinceLastRx=");
    if (lastRxMs == 0) {
      Serial.println("never");
    } else {
      Serial.println(millis() - lastRxMs);
    }
  }
}
