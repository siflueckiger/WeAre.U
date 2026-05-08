#include <Arduino.h>
#include <math.h>

// -----------------------------
// Serial / UART config
// -----------------------------
static const uint32_t USB_BAUD = 115200;
static const uint32_t BU03_BAUD = 115200;

// ESP32 UART2 pins
// BU03 PA2(TX, distance UART) -> ESP32 RX2
// BU03 PA3(RX, distance UART) -> ESP32 TX2
static const int BU03_RX_PIN = 16;
static const int BU03_TX_PIN = 17;

HardwareSerial bu03Uart(2);

// -----------------------------
// Anchor setup (meters)
// Edit these to your measured room coordinates.
// Use NAN for unused anchors.
// -----------------------------
static const float anchorPos[8][2] = {
    {2.0f, 0.8f}, // Anchor 0 : X,Y
    {0.0f, 2.7f}, // Anchor 1
    {6.5f, 2.83f}, // Anchor 2
    {6.7f, 0.15f}, // Anchor 3
    {NAN, NAN},   // Anchor 4 (unused)
    {NAN, NAN},   // Anchor 5 (unused)
    {NAN, NAN},   // Anchor 6 (unused)
    {NAN, NAN}    // Anchor 7 (unused)
};

// Per-anchor distance offset calibration (meters)
static float distanceOffset[8] = {
    0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f
};

// -----------------------------
// Frame parser
// -----------------------------
static const int FRAME_LEN = 35;

bool decodeDistances(const uint8_t *frame, int len, float *distances) {
  for (int i = 0; i < 8; i++) {
    distances[i] = 0.0f;
  }

  if (len < FRAME_LEN) {
    return false;
  }

  if (frame[0] != 0xAA) {
    return false;
  }

  // BU03 data format in tutorial: 8 entries, each 4 bytes apart,
  // distance is little-endian 16-bit in first 2 bytes of each entry.
  for (int i = 0; i < 8; i++) {
    int off = 3 + i * 4;
    if (off + 1 >= len) {
      continue;
    }

    uint16_t rawMm = (uint16_t)frame[off] | ((uint16_t)frame[off + 1] << 8);
    if (rawMm > 0) {
      distances[i] = (rawMm / 1000.0f) + distanceOffset[i];
      if (distances[i] < 0.0f) {
        distances[i] = 0.0f;
      }
    }
  }

  return true;
}

// -----------------------------
// 2D Trilateration (least squares)
// -----------------------------
bool trilaterate2D(const float *distances, float &x, float &y, int &usedAnchors) {
  int validIdx[8];
  usedAnchors = 0;

  for (int i = 0; i < 8; i++) {
    bool hasAnchor = !isnan(anchorPos[i][0]) && !isnan(anchorPos[i][1]);
    if (hasAnchor && distances[i] > 0.0f) {
      validIdx[usedAnchors++] = i;
    }
  }

  if (usedAnchors < 3) {
    return false;
  }

  // Use first valid anchor as reference.
  int i0 = validIdx[0];
  float x1 = anchorPos[i0][0];
  float y1 = anchorPos[i0][1];
  float r1 = distances[i0];

  // Build normal equations for least squares in 2D:
  // A * [x y]^T = b
  // then solve (A^T A) p = A^T b.
  float ata00 = 0.0f, ata01 = 0.0f, ata11 = 0.0f;
  float atb0 = 0.0f, atb1 = 0.0f;
  int eqCount = 0;

  for (int k = 1; k < usedAnchors; k++) {
    int i = validIdx[k];
    float xi = anchorPos[i][0];
    float yi = anchorPos[i][1];
    float ri = distances[i];

    float a = 2.0f * (xi - x1);
    float b = 2.0f * (yi - y1);
    float c = (r1 * r1 - ri * ri) - (x1 * x1 - xi * xi) - (y1 * y1 - yi * yi);

    ata00 += a * a;
    ata01 += a * b;
    ata11 += b * b;
    atb0 += a * c;
    atb1 += b * c;
    eqCount++;
  }

  if (eqCount < 2) {
    return false;
  }

  float det = ata00 * ata11 - ata01 * ata01;
  if (fabsf(det) < 1e-6f) {
    return false;
  }

  x = (atb0 * ata11 - atb1 * ata01) / det;
  y = (ata00 * atb1 - ata01 * atb0) / det;
  return true;
}

void setup() {
  Serial.begin(USB_BAUD);
  bu03Uart.begin(BU03_BAUD, SERIAL_8N1, BU03_RX_PIN, BU03_TX_PIN);

  Serial.println("x,y,anchors_used,d0,d1,d2,d3");
}

void loop() {
  static uint8_t frame[FRAME_LEN];
  static int idx = 0;
  static bool inFrame = false;

  while (bu03Uart.available()) {
    uint8_t b = (uint8_t)bu03Uart.read();

    if (!inFrame) {
      if (b == 0xAA) {
        inFrame = true;
        idx = 0;
        frame[idx++] = b;
      }
      continue;
    }

    if (idx < FRAME_LEN) {
      frame[idx++] = b;
    }

    if (idx >= FRAME_LEN) {
      float d[8];
      bool ok = decodeDistances(frame, FRAME_LEN, d);

      if (ok) {
        float x = 0.0f, y = 0.0f;
        int used = 0;
        bool posOk = trilaterate2D(d, x, y, used);

        if (posOk) {
          Serial.print(x, 3);
          Serial.print(",");
          Serial.print(y, 3);
        } else {
          Serial.print("nan,nan");
        }

        Serial.print(",");
        Serial.print(used);
        Serial.print(",");
        Serial.print(d[0], 3);
        Serial.print(",");
        Serial.print(d[1], 3);
        Serial.print(",");
        Serial.print(d[2], 3);
        Serial.print(",");
        Serial.println(d[3], 3);
      }

      inFrame = false;
      idx = 0;
    }
  }
}
