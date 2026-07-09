#include <Arduino.h>

// -----------------------------
// Serial config
// -----------------------------
static const uint32_t USB_BAUD  = 115200;
static const uint32_t BU03_BAUD = 115200;

// BU03 PA2(TX) -> ESP32 RX2 (GPIO16)
// BU03 PA3(RX) -> ESP32 TX2 (GPIO17)
static const int BU03_RX_PIN = 16;
static const int BU03_TX_PIN = 17;

HardwareSerial bu03Uart(2);

// -----------------------------
// Raw passthrough + optional frame decode
// All bytes are forwarded immediately.
// Binary frames (0xAA) are additionally decoded.
// -----------------------------
static const int FRAME_LEN = 35;
static uint8_t  frameBuf[FRAME_LEN];
static int      frameIdx   = 0;
static bool     inFrame    = false;

static uint32_t frameCount = 0;
static uint32_t byteCount  = 0;

void printFrameDecode(const uint8_t *buf, int len) {
  frameCount++;
  Serial.print("\n--- Frame #");
  Serial.print(frameCount);
  Serial.print(" (");
  Serial.print(len);
  Serial.println(" bytes) ---");

  // Hex dump, 8 bytes per row
  for (int i = 0; i < len; i++) {
    if (i % 8 == 0) {
      Serial.print("  ");
      char addr[6];
      sprintf(addr, "[%02d] ", i);
      Serial.print(addr);
    }
    char hex[4];
    sprintf(hex, "%02X ", buf[i]);
    Serial.print(hex);
    if ((i + 1) % 8 == 0 || i == len - 1) {
      Serial.println();
    }
  }

  // Decoded distance slots
  Serial.println("  Distances (16-bit LE mm -> m):");
  for (int i = 0; i < 8; i++) {
    int off = 3 + i * 4;
    if (off + 1 >= len) break;
    uint16_t rawMm = (uint16_t)buf[off] | ((uint16_t)buf[off + 1] << 8);
    Serial.print("    Slot ");
    Serial.print(i);
    Serial.print(": ");
    if (rawMm > 0) {
      Serial.print(rawMm);
      Serial.print(" mm = ");
      Serial.print(rawMm / 1000.0f, 3);
      Serial.print(" m  | raw bytes: ");
      char b[18];
      sprintf(b, "%02X %02X %02X %02X", buf[off], buf[off+1], buf[off+2], buf[off+3]);
      Serial.println(b);
    } else {
      Serial.println("(inactive)");
    }
  }
}

void setup() {
  Serial.begin(USB_BAUD);
  bu03Uart.begin(BU03_BAUD, SERIAL_8N1, BU03_RX_PIN, BU03_TX_PIN);
  delay(200);

  Serial.println("=== BU03 PassThrough ESP32 ===");
  Serial.print("RX pin: "); Serial.println(BU03_RX_PIN);
  Serial.print("TX pin: "); Serial.println(BU03_TX_PIN);
  Serial.print("Baud:   "); Serial.println(BU03_BAUD);
  Serial.println("Waiting for frames (header=0xAA)...");
}

void loop() {
  while (bu03Uart.available()) {
    uint8_t b = (uint8_t)bu03Uart.read();
    byteCount++;

    // --- 1) Raw passthrough: alle Bytes sofort weiterleiten ---
    // Druckbare ASCII-Zeichen direkt ausgeben, Binär als \xHH
    if (b >= 0x20 && b <= 0x7E) {
      Serial.write(b);
    } else if (b == '\n' || b == '\r') {
      Serial.write(b);
    } else {
      // Binär-Byte als \xHH markieren, damit man 0xAA-Frames sieht
      char hex[6];
      sprintf(hex, "\\x%02X", b);
      Serial.print(hex);
    }

    // --- 2) Parallel: 0xAA-Frames erkennen und dekodieren ---
    if (!inFrame) {
      if (b == 0xAA) {
        inFrame  = true;
        frameIdx = 0;
        frameBuf[frameIdx++] = b;
      }
    } else {
      if (frameIdx < FRAME_LEN) {
        frameBuf[frameIdx++] = b;
      }
      if (frameIdx >= FRAME_LEN) {
        printFrameDecode(frameBuf, FRAME_LEN);
        inFrame  = false;
        frameIdx = 0;
      }
    }
  }

  // Status alle 5 Sekunden wenn keine Daten kommen
  static unsigned long lastStatus = 0;
  if (millis() - lastStatus > 5000) {
    lastStatus = millis();
    Serial.print("\n[status] bytes=");
    Serial.print(byteCount);
    Serial.print(" frames=");
    Serial.println(frameCount);
  }
}
