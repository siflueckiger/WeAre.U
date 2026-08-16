#include <Arduino.h>

// -----------------------------
// Serial config
/*

rame #170 | header=AA 25 1
  Rohdaten je Slot (ungefiltert):
    S0: 1400 mm | 1.400 m | bytes=78 5 0 0
    S1: 3160 mm | 3.160 m | bytes=58 C 0 0
    S2: 5300 mm | 5.300 m | bytes=B4 14 0 0
    S3: 4790 mm | 4.790 m | bytes=B6 12 0 0
    S4: 0 mm | 0.000 m | bytes=0 0 0 0
    S5: 0 mm | 0.000 m | bytes=0 0 0 0
    S6: 0 mm | 0.000 m | bytes=0 0 0 0
    S7: 0 mm | 0.000 m | bytes=0 0 0 0

Frame #171 | header=AA 25 1
  Rohdaten je Slot (ungefiltert):
    S0: 1360 mm | 1.360 m | bytes=50 5 0 0
    S1: 3110 mm | 3.110 m | bytes=26 C 0 0
    S2: 5230 mm | 5.230 m | bytes=6E 14 0 0
    S3: 4840 mm | 4.840 m | bytes=E8 12 0 0
    S4: 0 mm | 0.000 m | bytes=0 0 0 0
    S5: 0 mm | 0.000 m | bytes=0 0 0 0
    S6: 0 mm | 0.000 m | bytes=0 0 0 0
    S7: 0 mm | 0.000 m | bytes=0 0 0 0
*/
// -----------------------------
static const uint32_t USB_BAUD  = 115200;
static const uint32_t BU03_BAUD = 115200;

// BU03 PA2(TX) -> ESP32 RX2 (GPIO16)
// BU03 PA3(RX) -> ESP32 TX2 (GPIO17)
static const int BU03_RX_PIN = 16;
static const int BU03_TX_PIN = 17;

HardwareSerial bu03Uart(2);

static const int FRAME_LEN = 35;
static uint8_t frameBuf[FRAME_LEN];
static int frameIdx = 0;
static bool inFrame = false;
static uint32_t frameCount = 0;

void printFrameDecode(const uint8_t *buf, int len) {
  frameCount++;
  Serial.print("Frame #");
  Serial.print(frameCount);
  Serial.print(" | header=");
  Serial.print(buf[0], HEX);
  Serial.print(" ");
  Serial.print(buf[1], HEX);
  Serial.print(" ");
  Serial.print(buf[2], HEX);
  Serial.println();

  Serial.println("  Rohdaten je Slot (ungefiltert):");
  for (int i = 0; i < 8; i++) {
    int off = 3 + i * 4;
    if (off + 1 >= len) break;

    uint16_t rawMm = (uint16_t)buf[off] | ((uint16_t)buf[off + 1] << 8);
    Serial.print("    S");
    Serial.print(i);
    Serial.print(": ");
    Serial.print(rawMm);
    Serial.print(" mm | ");
    Serial.print(rawMm / 1000.0f, 3);
    Serial.print(" m | bytes=");
    Serial.print(buf[off], HEX);
    Serial.print(" ");
    Serial.print(buf[off + 1], HEX);
    Serial.print(" ");
    Serial.print(buf[off + 2], HEX);
    Serial.print(" ");
    Serial.println(buf[off + 3], HEX);
  }
  Serial.println();
}

void setup() {
  Serial.begin(USB_BAUD);
  bu03Uart.begin(BU03_BAUD, SERIAL_8N1, BU03_RX_PIN, BU03_TX_PIN);
  delay(200);

  Serial.println("=== BU03 PassThrough ESP32 ===");
  Serial.print("RX pin: "); Serial.println(BU03_RX_PIN);
  Serial.print("TX pin: "); Serial.println(BU03_TX_PIN);
  Serial.print("Baud:   "); Serial.println(BU03_BAUD);
  Serial.println("Readable decode mode active (AA + 35-byte frame)");
}

void loop() {
  // BU03 -> decoded frame output
  while (bu03Uart.available()) {
    uint8_t b = (uint8_t)bu03Uart.read();

    if (!inFrame) {
      if (b == 0xAA) {
        inFrame = true;
        frameIdx = 0;
        frameBuf[frameIdx++] = b;
      }
      continue;
    }

    if (frameIdx < FRAME_LEN) {
      frameBuf[frameIdx++] = b;
    }

    if (frameIdx >= FRAME_LEN) {
      printFrameDecode(frameBuf, FRAME_LEN);
      inFrame = false;
      frameIdx = 0;
    }
  }

  // USB serial monitor -> BU03 (for AT commands)
  while (Serial.available()) {
    bu03Uart.write((uint8_t)Serial.read());
  }
}
