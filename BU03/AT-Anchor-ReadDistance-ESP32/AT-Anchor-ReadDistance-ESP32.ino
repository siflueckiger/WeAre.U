#include <Arduino.h>

static const int MAX_ANCHORS = 8;
static const int MEDIAN_WINDOW = 5;

static const float DIST_MIN_M = 0.05f;
static const float DIST_MAX_M = 30.0f;
static const float SPIKE_CLAMP_M = 0.80f;
static const float EMA_ALPHA = 0.25f;

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

static float filterHistory[MAX_ANCHORS][MEDIAN_WINDOW];
static int filterCount[MAX_ANCHORS] = {0};
static int filterWriteIdx[MAX_ANCHORS] = {0};
static float filterEma[MAX_ANCHORS] = {0.0f};
static bool filterEmaValid[MAX_ANCHORS] = {false};

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

bool smoothDistance(int anchorIdx, float rawDistance, float &smoothedDistance) {
  if (anchorIdx < 0 || anchorIdx >= MAX_ANCHORS) {
    return false;
  }

  if (!(rawDistance >= DIST_MIN_M && rawDistance <= DIST_MAX_M)) {
    filterCount[anchorIdx] = 0;
    filterWriteIdx[anchorIdx] = 0;
    filterEmaValid[anchorIdx] = false;
    return false;
  }

  float sample = rawDistance;
  if (filterEmaValid[anchorIdx]) {
    float delta = sample - filterEma[anchorIdx];
    if (delta > SPIKE_CLAMP_M) {
      sample = filterEma[anchorIdx] + SPIKE_CLAMP_M;
    } else if (delta < -SPIKE_CLAMP_M) {
      sample = filterEma[anchorIdx] - SPIKE_CLAMP_M;
    }
  }

  int wi = filterWriteIdx[anchorIdx];
  filterHistory[anchorIdx][wi] = sample;
  filterWriteIdx[anchorIdx] = (wi + 1) % MEDIAN_WINDOW;
  if (filterCount[anchorIdx] < MEDIAN_WINDOW) {
    filterCount[anchorIdx]++;
  }

  float tmp[MEDIAN_WINDOW];
  int n = filterCount[anchorIdx];
  for (int i = 0; i < n; i++) {
    tmp[i] = filterHistory[anchorIdx][i];
  }
  float med = medianInPlace(tmp, n);

  if (!filterEmaValid[anchorIdx]) {
    filterEma[anchorIdx] = med;
    filterEmaValid[anchorIdx] = true;
  } else {
    filterEma[anchorIdx] += EMA_ALPHA * (med - filterEma[anchorIdx]);
  }

  smoothedDistance = filterEma[anchorIdx];
  return true;
}

bool decodeUwbDistances(uint8_t *data, int dataLen, float *distances) {
  // Initialize all distances to -1 (equivalent to None)
  for (int i = 0; i < MAX_ANCHORS; i++) {
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
  for (int i = 0; i < MAX_ANCHORS; i++) {
    int byteOffset = 3 + (i * 4);
    if (byteOffset + 1 < dataLen) {
      uint16_t distanceRawMm = ((uint16_t)data[byteOffset]) |
                               ((uint16_t)data[byteOffset + 1] << 8);

      if (distanceRawMm > 0) {
        distances[i] = distanceRawMm / 1000.0f;
      }
    }
  }

  return true;
}

void printDistances(float *rawDistances, float *smoothedDistances, bool validData) {
  if (!validData) {
    Serial.println("Invalid data received");
    return;
  }

  for (int i = 0; i <= 3; i++) {
    Serial.print("BS");
    Serial.print(i);
    Serial.print(" raw=");
    if (rawDistances[i] > 0) {
      Serial.print(rawDistances[i], 3);
    } else {
      Serial.print("NA");
    }

    Serial.print("m smooth=");
    if (smoothedDistances[i] > 0) {
      Serial.print(smoothedDistances[i], 3);
      Serial.println("m");
    } else {
      Serial.println("NA");
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

        float rawDistances[MAX_ANCHORS];
        bool validData = decodeUwbDistances(buffer, bufferIndex, rawDistances);

        float smoothedDistances[MAX_ANCHORS];
        for (int i = 0; i < MAX_ANCHORS; i++) {
          smoothedDistances[i] = -1.0f;
          float out = -1.0f;
          if (smoothDistance(i, rawDistances[i], out)) {
            smoothedDistances[i] = out;
          }
        }

        printDistances(rawDistances, smoothedDistances, validData);

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
