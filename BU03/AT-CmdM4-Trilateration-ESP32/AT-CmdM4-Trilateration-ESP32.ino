#include <Arduino.h>
#include <math.h>

// -----------------------------
// Config
// -----------------------------
static const uint32_t USB_BAUD  = 115200;
static const uint32_t BU03_BAUD = 115200;

// BU03 PA2(TX) -> ESP32 RX2 (GPIO16)
// BU03 PA3(RX) -> ESP32 TX2 (GPIO17)
static const int BU03_RX_PIN = 16;
static const int BU03_TX_PIN = 17;

HardwareSerial bu03Uart(2);

// -----------------------------
// Anchor positions (meters)
// Edit to your room coordinates.
// -----------------------------
static const int MAX_ANCHORS = 8;
static const int MAX_TAGS    = 8;

static const float anchorPos[MAX_ANCHORS][2] = {
    {2.0f, 0.8f},   // Anchor 0
    {0.0f, 2.7f},   // Anchor 1
    {6.5f, 2.83f},  // Anchor 2
    {6.7f, 0.15f},  // Anchor 3
    {NAN, NAN},     // Anchor 4 (unused)
    {NAN, NAN},     // Anchor 5 (unused)
    {NAN, NAN},     // Anchor 6 (unused)
    {NAN, NAN},     // Anchor 7 (unused)
};

// Per-anchor distance offset calibration (meters)
static float distanceOffset[MAX_ANCHORS] = {
    0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f
};

// -----------------------------
// Distance filter (median + EMA)
// -----------------------------
static const int   MEDIAN_WINDOW = 5;
static const float DIST_MIN_M    = 0.05f;
static const float DIST_MAX_M    = 30.0f;
static const float SPIKE_CLAMP_M = 0.80f;
static const float EMA_ALPHA     = 0.25f;

static float filterHistory[MAX_TAGS][MAX_ANCHORS][MEDIAN_WINDOW];
static int   filterCount[MAX_TAGS][MAX_ANCHORS];
static int   filterWriteIdx[MAX_TAGS][MAX_ANCHORS];
static float filterEma[MAX_TAGS][MAX_ANCHORS];
static bool  filterEmaValid[MAX_TAGS][MAX_ANCHORS];

float medianInPlace(float *v, int n) {
  for (int i = 1; i < n; i++) {
    float key = v[i];
    int j = i - 1;
    while (j >= 0 && v[j] > key) { v[j+1] = v[j]; j--; }
    v[j+1] = key;
  }
  return (n & 1) ? v[n/2] : 0.5f * (v[n/2-1] + v[n/2]);
}

bool smoothDistance(int tagIdx, int anchorIdx, float raw, float &out) {
  if (tagIdx < 0 || tagIdx >= MAX_TAGS || anchorIdx < 0 || anchorIdx >= MAX_ANCHORS)
    return false;
  if (!(raw >= DIST_MIN_M && raw <= DIST_MAX_M)) {
    filterCount[tagIdx][anchorIdx]    = 0;
    filterWriteIdx[tagIdx][anchorIdx] = 0;
    filterEmaValid[tagIdx][anchorIdx] = false;
    return false;
  }

  float sample = raw;
  if (filterEmaValid[tagIdx][anchorIdx]) {
    float delta = sample - filterEma[tagIdx][anchorIdx];
    if      (delta >  SPIKE_CLAMP_M) sample = filterEma[tagIdx][anchorIdx] + SPIKE_CLAMP_M;
    else if (delta < -SPIKE_CLAMP_M) sample = filterEma[tagIdx][anchorIdx] - SPIKE_CLAMP_M;
  }

  int wi = filterWriteIdx[tagIdx][anchorIdx];
  filterHistory[tagIdx][anchorIdx][wi] = sample;
  filterWriteIdx[tagIdx][anchorIdx] = (wi + 1) % MEDIAN_WINDOW;
  if (filterCount[tagIdx][anchorIdx] < MEDIAN_WINDOW) filterCount[tagIdx][anchorIdx]++;

  float tmp[MEDIAN_WINDOW];
  int n = filterCount[tagIdx][anchorIdx];
  for (int i = 0; i < n; i++) tmp[i] = filterHistory[tagIdx][anchorIdx][i];
  float med = medianInPlace(tmp, n);

  if (!filterEmaValid[tagIdx][anchorIdx]) {
    filterEma[tagIdx][anchorIdx]      = med;
    filterEmaValid[tagIdx][anchorIdx] = true;
  } else {
    filterEma[tagIdx][anchorIdx] += EMA_ALPHA * (med - filterEma[tagIdx][anchorIdx]);
  }

  out = filterEma[tagIdx][anchorIdx];
  return true;
}

// -----------------------------
// Distance state per tag
// distances[tagIdx][anchorIdx] = smoothed distance, 0 = invalid
// -----------------------------
static float distances[MAX_TAGS][MAX_ANCHORS];
static unsigned long lastUpdateMs[MAX_TAGS][MAX_ANCHORS];
static const unsigned long DIST_TIMEOUT_MS = 2000; // distance expires after 2s

// -----------------------------
// 2D Trilateration (least squares)
// -----------------------------
bool trilaterate2D(const float *d, float &x, float &y, int &used) {
  int validIdx[MAX_ANCHORS];
  used = 0;
  for (int i = 0; i < MAX_ANCHORS; i++) {
    bool hasPos = !isnan(anchorPos[i][0]) && !isnan(anchorPos[i][1]);
    if (hasPos && d[i] > 0.0f) validIdx[used++] = i;
  }
  if (used < 3) return false;

  int i0 = validIdx[0];
  float x1 = anchorPos[i0][0], y1 = anchorPos[i0][1], r1 = d[i0];

  float ata00 = 0, ata01 = 0, ata11 = 0, atb0 = 0, atb1 = 0;
  int eq = 0;
  for (int k = 1; k < used; k++) {
    int i = validIdx[k];
    float a = 2.0f * (anchorPos[i][0] - x1);
    float b = 2.0f * (anchorPos[i][1] - y1);
    float c = (r1*r1 - d[i]*d[i]) - (x1*x1 - anchorPos[i][0]*anchorPos[i][0])
                                    - (y1*y1 - anchorPos[i][1]*anchorPos[i][1]);
    ata00 += a*a; ata01 += a*b; ata11 += b*b;
    atb0  += a*c; atb1  += b*c;
    eq++;
  }
  if (eq < 2) return false;

  float det = ata00 * ata11 - ata01 * ata01;
  if (fabsf(det) < 1e-6f) return false;

  x = (atb0 * ata11 - atb1 * ata01) / det;
  y = (ata00 * atb1 - ata01 * atb0) / det;
  return true;
}

// -----------------------------
// CmdM:4 packet parser
// Header: 'C','m','d','M',':','4'  (6 bytes)
// Then:   anchorID (1 byte)
//         tagID    (1 byte)
//         distance (4 bytes, uint32 LE, mm)
// -----------------------------
static const uint8_t HEADER[]    = {0x43, 0x6D, 0x64, 0x4D, 0x3A, 0x34};
static const size_t  HEADER_SIZE = 6;
static size_t headerIdx = 0;

void processPacket(uint8_t anchorID, uint8_t tagID, uint32_t distMm) {
  if (anchorID >= MAX_ANCHORS || tagID >= MAX_TAGS) return;
  if (isnan(anchorPos[anchorID][0])) return; // Anchor not configured

  float rawM = (distMm / 1000.0f) + distanceOffset[anchorID];
  float smoothed = 0.0f;
  if (!smoothDistance(tagID, anchorID, rawM, smoothed)) return;

  distances[tagID][anchorID]    = smoothed;
  lastUpdateMs[tagID][anchorID] = millis();

  // Expire stale distances
  unsigned long now = millis();
  for (int a = 0; a < MAX_ANCHORS; a++) {
    if (distances[tagID][a] > 0.0f && (now - lastUpdateMs[tagID][a]) > DIST_TIMEOUT_MS) {
      distances[tagID][a] = 0.0f;
    }
  }

  // Trilaterate and output
  float x = 0.0f, y = 0.0f;
  int used = 0;
  bool ok = trilaterate2D(distances[tagID], x, y, used);

  Serial.print(tagID);
  Serial.print(",");
  if (ok) {
    Serial.print(x, 3);
    Serial.print(",");
    Serial.print(y, 3);
  } else {
    Serial.print("nan,nan");
  }
  Serial.print(",");
  Serial.print(used);
  for (int a = 0; a < 4; a++) {
    Serial.print(",");
    Serial.print(distances[tagID][a], 3);
  }
  Serial.println();
}

void setup() {
  Serial.begin(USB_BAUD);
  bu03Uart.begin(BU03_BAUD, SERIAL_8N1, BU03_RX_PIN, BU03_TX_PIN);

  memset(distances,      0, sizeof(distances));
  memset(lastUpdateMs,   0, sizeof(lastUpdateMs));
  memset(filterCount,    0, sizeof(filterCount));
  memset(filterWriteIdx, 0, sizeof(filterWriteIdx));
  memset(filterEma,      0, sizeof(filterEma));
  memset(filterEmaValid, 0, sizeof(filterEmaValid));

  Serial.println("tag,x,y,anchors_used,d0,d1,d2,d3");
}

void loop() {
  while (bu03Uart.available()) {
    uint8_t b = (uint8_t)bu03Uart.read();

    // Header matching
    if (b == HEADER[headerIdx]) {
      headerIdx++;
      if (headerIdx == HEADER_SIZE) {
        headerIdx = 0;

        // Wait for 6 payload bytes (anchorID + tagID + 4 bytes distance)
        unsigned long t0 = millis();
        while (bu03Uart.available() < 6 && millis() - t0 < 20) {
          delayMicroseconds(10);
        }
        if (bu03Uart.available() < 6) continue; // timeout, skip

        uint8_t  anchorID  = bu03Uart.read();
        uint8_t  tagID     = bu03Uart.read();
        uint32_t d0        = bu03Uart.read();
        uint32_t d1        = bu03Uart.read();
        uint32_t d2        = bu03Uart.read();
        uint32_t d3        = bu03Uart.read();
        uint32_t distMm    = d0 | (d1 << 8) | (d2 << 16) | (d3 << 24);

        processPacket(anchorID, tagID, distMm);
      }
    } else {
      // Restart header search; check if this byte starts a new header
      headerIdx = (b == HEADER[0]) ? 1 : 0;
    }
  }
}
