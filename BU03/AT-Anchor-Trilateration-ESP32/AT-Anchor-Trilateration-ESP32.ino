#include <Arduino.h>
#include <math.h>

static const int MAX_ANCHORS = 8;
static const int MAX_TAGS = 2;
static const int MEDIAN_WINDOW = 5;

static const float DIST_MIN_M = 0.05f;
static const float DIST_MAX_M = 30.0f;
static const float SPIKE_CLAMP_M = 0.80f;
static const float EMA_ALPHA = 0.25f;

// -----------------------------
// Serial / UART config
// -----------------------------
static const uint32_t USB_BAUD = 115200;
static const uint32_t BU03_BAUD = 115200;

// Tag 1 -> UART2 (GPIO 16/17)
// Tag 2 -> UART1 (GPIO 25/26)
// BU03 PA2(TX) -> ESP32 RX, BU03 PA3(RX) -> ESP32 TX
static const int TAG1_RX_PIN = 16;
static const int TAG1_TX_PIN = 17;
static const int TAG2_RX_PIN = 25;
static const int TAG2_TX_PIN = 26;

HardwareSerial tagUart[MAX_TAGS] = { HardwareSerial(2), HardwareSerial(1) };

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

// Per-tag, per-anchor filter state
static float filterHistory[MAX_TAGS][MAX_ANCHORS][MEDIAN_WINDOW];
static int filterCount[MAX_TAGS][MAX_ANCHORS];
static int filterWriteIdx[MAX_TAGS][MAX_ANCHORS];
static float filterEma[MAX_TAGS][MAX_ANCHORS];
static bool filterEmaValid[MAX_TAGS][MAX_ANCHORS];

float medianInPlace(float *values, int n) {
  for (int i = 1; i < n; i++) {
    float key = values[i];
    int j = i - 1;
    while (j >= 0 && values[j] > key) {
      values[j + 1] = values[j];
      j--;
    }
    values[j + 1] = key;
  }

  if ((n & 1) == 1) {
    return values[n / 2];
  }
  return 0.5f * (values[n / 2 - 1] + values[n / 2]);
}

bool smoothDistance(int tagIdx, int anchorIdx, float rawDistance, float &smoothedDistance) {
  if (tagIdx < 0 || tagIdx >= MAX_TAGS || anchorIdx < 0 || anchorIdx >= MAX_ANCHORS) {
    return false;
  }

  if (!(rawDistance >= DIST_MIN_M && rawDistance <= DIST_MAX_M)) {
    filterCount[tagIdx][anchorIdx] = 0;
    filterWriteIdx[tagIdx][anchorIdx] = 0;
    filterEmaValid[tagIdx][anchorIdx] = false;
    return false;
  }

  float sample = rawDistance;
  if (filterEmaValid[tagIdx][anchorIdx]) {
    float delta = sample - filterEma[tagIdx][anchorIdx];
    if (delta > SPIKE_CLAMP_M) {
      sample = filterEma[tagIdx][anchorIdx] + SPIKE_CLAMP_M;
    } else if (delta < -SPIKE_CLAMP_M) {
      sample = filterEma[tagIdx][anchorIdx] - SPIKE_CLAMP_M;
    }
  }

  int wi = filterWriteIdx[tagIdx][anchorIdx];
  filterHistory[tagIdx][anchorIdx][wi] = sample;
  filterWriteIdx[tagIdx][anchorIdx] = (wi + 1) % MEDIAN_WINDOW;
  if (filterCount[tagIdx][anchorIdx] < MEDIAN_WINDOW) {
    filterCount[tagIdx][anchorIdx]++;
  }

  float tmp[MEDIAN_WINDOW];
  int n = filterCount[tagIdx][anchorIdx];
  for (int i = 0; i < n; i++) {
    tmp[i] = filterHistory[tagIdx][anchorIdx][i];
  }
  float med = medianInPlace(tmp, n);

  if (!filterEmaValid[tagIdx][anchorIdx]) {
    filterEma[tagIdx][anchorIdx] = med;
    filterEmaValid[tagIdx][anchorIdx] = true;
  } else {
    filterEma[tagIdx][anchorIdx] += EMA_ALPHA * (med - filterEma[tagIdx][anchorIdx]);
  }

  smoothedDistance = filterEma[tagIdx][anchorIdx];
  return true;
}

// -----------------------------
// Frame parser
// -----------------------------
static const int FRAME_LEN = 35;

bool decodeDistances(const uint8_t *frame, int len, float *distances) {
  for (int i = 0; i < MAX_ANCHORS; i++) {
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
  for (int i = 0; i < MAX_ANCHORS; i++) {
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

// -----------------------------
// Process one decoded frame for a given tag
// -----------------------------
void processFrame(int tagIdx, uint8_t *frame) {
  float dRaw[MAX_ANCHORS];
  bool ok = decodeDistances(frame, FRAME_LEN, dRaw);
  if (!ok) return;

  float d[MAX_ANCHORS];
  for (int i = 0; i < MAX_ANCHORS; i++) {
    d[i] = 0.0f;
    float out = 0.0f;
    if (smoothDistance(tagIdx, i, dRaw[i], out)) {
      d[i] = out;
    }
  }

  float x = 0.0f, y = 0.0f;
  int used = 0;
  bool posOk = trilaterate2D(d, x, y, used);

  Serial.print(tagIdx);
  Serial.print(",");
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
  Serial.print(d[3], 3);
  Serial.print(",");
  Serial.print(dRaw[0], 3);
  Serial.print(",");
  Serial.print(dRaw[1], 3);
  Serial.print(",");
  Serial.print(dRaw[2], 3);
  Serial.print(",");
  Serial.println(dRaw[3], 3);
}

void setup() {
  Serial.begin(USB_BAUD);
  tagUart[0].begin(BU03_BAUD, SERIAL_8N1, TAG1_RX_PIN, TAG1_TX_PIN);
  tagUart[1].begin(BU03_BAUD, SERIAL_8N1, TAG2_RX_PIN, TAG2_TX_PIN);

  memset(filterCount, 0, sizeof(filterCount));
  memset(filterWriteIdx, 0, sizeof(filterWriteIdx));
  memset(filterEma, 0, sizeof(filterEma));
  memset(filterEmaValid, 0, sizeof(filterEmaValid));

  Serial.println("tag,x,y,anchors_used,d0,d1,d2,d3,raw0,raw1,raw2,raw3");
}

void loop() {
  static uint8_t frame[MAX_TAGS][FRAME_LEN];
  static int idx[MAX_TAGS] = {0, 0};
  static bool inFrame[MAX_TAGS] = {false, false};

  for (int t = 0; t < MAX_TAGS; t++) {
    while (tagUart[t].available()) {
      uint8_t b = (uint8_t)tagUart[t].read();

      if (!inFrame[t]) {
        if (b == 0xAA) {
          inFrame[t] = true;
          idx[t] = 0;
          frame[t][idx[t]++] = b;
        }
        continue;
      }

      if (idx[t] < FRAME_LEN) {
        frame[t][idx[t]++] = b;
      }

      if (idx[t] >= FRAME_LEN) {
        processFrame(t, frame[t]);
        inFrame[t] = false;
        idx[t] = 0;
      }
    }
  }
}
