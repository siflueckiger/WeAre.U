import processing.serial.*;

// ---------- Serial ----------
Serial serialPort;
int serialPortIndex = 8;   // Change if needed after checking console output
int serialBaud = 115200;
int maxSerialLinesPerFrame = 40;
int parseErrorCount = 0;
int lastParseErrorMs = 0;

// ---------- World / anchors (meters) ----------
float[][] anchors = {
  {0.8, 2.0},
  {0.15, 6.7},
  {2.83, 6.5},
  {2.7, 0.0}
};

// Visible map bounds in meters
float minX = -0.5;
float maxX = 7.2;
float minY = -0.5;
float maxY = 3.5;

// Auto-fit view to include anchors + current tag points.
boolean autoFitView = false;
float autoFitPadding = 0.5;

// Swap plotted coordinates (X <-> Y) for anchors only.
boolean swapXYCoordinates = true;

// ---------- Live data ----------
static final int MAX_TAGS = 2;
float[] tagX = new float[MAX_TAGS];
float[] tagY = new float[MAX_TAGS];
float[] tagXFiltered = new float[MAX_TAGS];
float[] tagYFiltered = new float[MAX_TAGS];
int[] anchorsUsed = new int[MAX_TAGS];
float[][] d = new float[MAX_TAGS][4];
boolean[] hasData = new boolean[MAX_TAGS];

// Trails per tag
ArrayList<PVector>[] rawTrail = new ArrayList[MAX_TAGS];
ArrayList<PVector>[] filteredTrail = new ArrayList[MAX_TAGS];
int maxTrail = 120;

// ---------- Simple 2D Kalman ----------
float[][] kState = new float[MAX_TAGS][4];
float[] kP00 = new float[MAX_TAGS];
float[] kP11 = new float[MAX_TAGS];
float kQ = 0.12;
float kR = 1.1;
float kDt = 0.10;
boolean[] kalmanInitialized = new boolean[MAX_TAGS];

void setup() {
  size(1200, 800);
  smooth(8);

  for (int i = 0; i < MAX_TAGS; i++) {
    tagX[i] = Float.NaN;
    tagY[i] = Float.NaN;
    tagXFiltered[i] = Float.NaN;
    tagYFiltered[i] = Float.NaN;
    kP00[i] = 1.0;
    kP11[i] = 1.0;
    rawTrail[i] = new ArrayList<PVector>();
    filteredTrail[i] = new ArrayList<PVector>();
  }

  println("Available serial ports:");
  printArray(Serial.list());

  if (Serial.list().length == 0) {
    println("No serial ports found.");
    return;
  }

  int selectedIndex = serialPortIndex;
  if (selectedIndex < 0 || selectedIndex >= Serial.list().length) {
    selectedIndex = 0;
  }

  serialPort = new Serial(this, Serial.list()[selectedIndex], serialBaud);
  serialPort.clear();
  println("Using serial port: " + Serial.list()[selectedIndex]);
}

void draw() {
  pollSerial(maxSerialLinesPerFrame);
  updateViewBounds();
  drawBackgroundGrid();
  drawAnchors();
  drawTrails();
  drawTags();
  drawHud();
}

float plotX(float x, float y) {
  return swapXYCoordinates ? y : x;
}

float plotY(float x, float y) {
  return swapXYCoordinates ? x : y;
}

void updateViewBounds() {
  if (!autoFitView) {
    return;
  }

  float minVX = 1e9;
  float maxVX = -1e9;
  float minVY = 1e9;
  float maxVY = -1e9;

  // Always include anchors in view.
  for (int i = 0; i < anchors.length; i++) {
    float px = plotX(anchors[i][0], anchors[i][1]);
    float py = plotY(anchors[i][0], anchors[i][1]);
    minVX = min(minVX, px);
    maxVX = max(maxVX, px);
    minVY = min(minVY, py);
    maxVY = max(maxVY, py);
  }

  // Include current raw + filtered points in their original coordinate system.
  for (int t = 0; t < MAX_TAGS; t++) {
    if (!Float.isNaN(tagX[t]) && !Float.isNaN(tagY[t])) {
      minVX = min(minVX, tagX[t]);
      maxVX = max(maxVX, tagX[t]);
      minVY = min(minVY, tagY[t]);
      maxVY = max(maxVY, tagY[t]);
    }
    if (!Float.isNaN(tagXFiltered[t]) && !Float.isNaN(tagYFiltered[t])) {
      minVX = min(minVX, tagXFiltered[t]);
      maxVX = max(maxVX, tagXFiltered[t]);
      minVY = min(minVY, tagYFiltered[t]);
      maxVY = max(maxVY, tagYFiltered[t]);
    }
  }

  // Keep a sensible minimum world size to avoid jittery zooming.
  if (maxVX - minVX < 1.0) {
    float cx = (maxVX + minVX) * 0.5;
    minVX = cx - 0.5;
    maxVX = cx + 0.5;
  }
  if (maxVY - minVY < 1.0) {
    float cy = (maxVY + minVY) * 0.5;
    minVY = cy - 0.5;
    maxVY = cy + 0.5;
  }

  minX = minVX - autoFitPadding;
  maxX = maxVX + autoFitPadding;
  minY = minVY - autoFitPadding;
  maxY = maxVY + autoFitPadding;
}

void drawBackgroundGrid() {
  background(18);

  stroke(45);
  strokeWeight(1);

  for (float x = floor(minX); x <= ceil(maxX); x += 0.5) {
    float sx = worldToScreenX(x);
    line(sx, 40, sx, height - 40);
  }

  for (float y = floor(minY); y <= ceil(maxY); y += 0.5) {
    float sy = worldToScreenY(y);
    line(40, sy, width - 40, sy);
  }

  stroke(110);
  strokeWeight(2);
  line(worldToScreenX(0), 40, worldToScreenX(0), height - 40);
  line(40, worldToScreenY(0), width - 40, worldToScreenY(0));
}

void drawAnchors() {
  textAlign(CENTER, CENTER);
  textSize(14);

  for (int i = 0; i < anchors.length; i++) {
    float ax = anchors[i][0];
    float ay = anchors[i][1];
    float px = plotX(ax, ay);
    float py = plotY(ax, ay);

    float sx = worldToScreenX(px);
    float sy = worldToScreenY(py);

    // Range ring from current frame
    if (hasData[0] && d[0][i] > 0.0) {
      noFill();
      stroke(70, 120, 220, 130);
      strokeWeight(1);
      float radiusPx = metersToPixels(d[0][i]);
      ellipse(sx, sy, radiusPx * 2, radiusPx * 2);
    }

    fill(255, 160, 60);
    noStroke();
    ellipse(sx, sy, 16, 16);

    fill(235);
    text("A" + i, sx, sy - 18);
  }
}

void drawTrails() {
  int[][] rawColors    = {{255, 120, 120}, {120, 180, 255}};
  int[][] filtColors   = {{120, 220, 120}, {220, 220, 80}};

  for (int t = 0; t < MAX_TAGS; t++) {
    if (rawTrail[t].size() >= 2) {
      noFill();
      stroke(rawColors[t][0], rawColors[t][1], rawColors[t][2], 160);
      strokeWeight(1.5);
      beginShape();
      for (PVector p : rawTrail[t]) {
        vertex(worldToScreenX(p.x), worldToScreenY(p.y));
      }
      endShape();
    }

    if (filteredTrail[t].size() >= 2) {
      noFill();
      stroke(filtColors[t][0], filtColors[t][1], filtColors[t][2], 180);
      strokeWeight(2);
      beginShape();
      for (PVector p : filteredTrail[t]) {
        vertex(worldToScreenX(p.x), worldToScreenY(p.y));
      }
      endShape();
    }
  }
}

void drawTags() {
  int[][] rawColors  = {{255, 120, 120}, {120, 180, 255}};
  int[][] filtColors = {{80, 255, 120}, {255, 240, 80}};

  for (int t = 0; t < MAX_TAGS; t++) {
    if (hasData[t] && !Float.isNaN(tagX[t]) && !Float.isNaN(tagY[t])) {
      float sx = worldToScreenX(tagX[t]);
      float sy = worldToScreenY(tagY[t]);
      stroke(rawColors[t][0], rawColors[t][1], rawColors[t][2]);
      strokeWeight(2);
      fill(rawColors[t][0], rawColors[t][1], rawColors[t][2]);
      ellipse(sx, sy, 12, 12);
      line(sx - 8, sy, sx + 8, sy);
      line(sx, sy - 8, sx, sy + 8);
    }

    if (hasData[t] && !Float.isNaN(tagXFiltered[t]) && !Float.isNaN(tagYFiltered[t])) {
      float sx = worldToScreenX(tagXFiltered[t]);
      float sy = worldToScreenY(tagYFiltered[t]);
      stroke(filtColors[t][0], filtColors[t][1], filtColors[t][2]);
      strokeWeight(2);
      fill(filtColors[t][0], filtColors[t][1], filtColors[t][2]);
      ellipse(sx, sy, 14, 14);
      stroke(filtColors[t][0], filtColors[t][1], filtColors[t][2], 180);
      line(sx - 10, sy, sx + 10, sy);
      line(sx, sy - 10, sx, sy + 10);
      textAlign(CENTER, BOTTOM);
      textSize(13);
      fill(filtColors[t][0], filtColors[t][1], filtColors[t][2]);
      text("T" + t, sx, sy - 12);
    }
  }
}

void drawHud() {
  fill(255);
  textAlign(LEFT, TOP);
  textSize(15);

  int[][] hudColors = {{255, 120, 120}, {120, 180, 255}};

  for (int t = 0; t < MAX_TAGS; t++) {
    int yOff = t * 44;
    fill(hudColors[t][0], hudColors[t][1], hudColors[t][2]);
    String raw = "T" + t + " raw: n/a";
    String filt = "T" + t + " filt: n/a";
    if (hasData[t] && !Float.isNaN(tagX[t]) && !Float.isNaN(tagY[t])) {
      raw = "T" + t + " raw: (" + nf(tagX[t], 1, 3) + ", " + nf(tagY[t], 1, 3) + ") m";
    }
    if (hasData[t] && !Float.isNaN(tagXFiltered[t]) && !Float.isNaN(tagYFiltered[t])) {
      filt = "T" + t + " filt: (" + nf(tagXFiltered[t], 1, 3) + ", " + nf(tagYFiltered[t], 1, 3) + ") m";
    }
    text(raw,  20, 12 + yOff);
    text(filt, 20, 28 + yOff);
  }

  fill(255);
  text("view x:[" + nf(minX, 1, 2) + ", " + nf(maxX, 1, 2) + "] y:[" + nf(minY, 1, 2) + ", " + nf(maxY, 1, 2) + "]", 20, 100);
  text("anchorSwapXY=" + (swapXYCoordinates ? "on" : "off"), 20, 122);
}

void kalmanPredict() {
  for (int t = 0; t < MAX_TAGS; t++) {
    if (!kalmanInitialized[t]) continue;
    kState[t][0] += kState[t][2] * kDt;
    kState[t][1] += kState[t][3] * kDt;
    kP00[t] += kQ;
    kP11[t] += kQ;
  }
}

void kalmanUpdate(int t, float mx, float my) {
  if (!kalmanInitialized[t]) {
    kState[t][0] = mx;
    kState[t][1] = my;
    kState[t][2] = 0;
    kState[t][3] = 0;
    kalmanInitialized[t] = true;
    return;
  }

  float kx = kP00[t] / (kP00[t] + kR);
  float ky = kP11[t] / (kP11[t] + kR);

  float prevX = kState[t][0];
  float prevY = kState[t][1];

  kState[t][0] = kState[t][0] + kx * (mx - kState[t][0]);
  kState[t][1] = kState[t][1] + ky * (my - kState[t][1]);

  if (kDt > 0) {
    kState[t][2] = (kState[t][0] - prevX) / kDt;
    kState[t][3] = (kState[t][1] - prevY) / kDt;
  }

  kP00[t] = (1 - kx) * kP00[t];
  kP11[t] = (1 - ky) * kP11[t];
}

void pollSerial(int maxLines) {
  if (serialPort == null) {
    return;
  }

  int processed = 0;
  while (serialPort.available() > 0 && processed < maxLines) {
    String line = serialPort.readStringUntil('\n');
    if (line == null) {
      break;
    }

    parseSerialLine(line);
    processed++;
  }
}

void parseSerialLine(String line) {

  line = trim(line);
  if (line.length() == 0) {
    return;
  }

  // Ignore non-CSV diagnostic lines
  if (line.startsWith("tag,") || line.startsWith("[status]") || line.startsWith("Header") || line.startsWith("Raw data") || line.startsWith("BS")) {
    return;
  }

  String[] parts = split(line, ',');
  if (parts.length < 8) {
    return;
  }

  try {
    int t = int(parseFlexibleFloat(parts[0]));
    if (t < 0 || t >= MAX_TAGS) return;

    float x    = parseFlexibleFloat(parts[1]);
    float y    = parseFlexibleFloat(parts[2]);
    int used   = int(parseFlexibleFloat(parts[3]));

    d[t][0] = parseFlexibleFloat(parts[4]);
    d[t][1] = parseFlexibleFloat(parts[5]);
    d[t][2] = parseFlexibleFloat(parts[6]);
    d[t][3] = parseFlexibleFloat(parts[7]);

    tagX[t] = x;
    tagY[t] = y;
    anchorsUsed[t] = used;
    hasData[t] = true;

    if (!Float.isNaN(tagX[t]) && !Float.isNaN(tagY[t])) {
      kalmanPredict();
      kalmanUpdate(t, tagX[t], tagY[t]);
      tagXFiltered[t] = kState[t][0];
      tagYFiltered[t] = kState[t][1];
    } else {
      kalmanPredict();
      if (kalmanInitialized[t]) {
        tagXFiltered[t] = kState[t][0];
        tagYFiltered[t] = kState[t][1];
      }
    }

    if (!Float.isNaN(tagX[t]) && !Float.isNaN(tagY[t])) {
      rawTrail[t].add(new PVector(tagX[t], tagY[t]));
      while (rawTrail[t].size() > maxTrail) {
        rawTrail[t].remove(0);
      }
    }

    if (!Float.isNaN(tagXFiltered[t]) && !Float.isNaN(tagYFiltered[t])) {
      filteredTrail[t].add(new PVector(tagXFiltered[t], tagYFiltered[t]));
      while (filteredTrail[t].size() > maxTrail) {
        filteredTrail[t].remove(0);
      }
    }
  }
  catch (Exception ex) {
    parseErrorCount++;
    int now = millis();
    if (now - lastParseErrorMs > 1000) {
      lastParseErrorMs = now;
      println("Parse errors: " + parseErrorCount + " (latest line omitted)");
    }
  }
}

float parseFlexibleFloat(String s) {
  String t = trim(s);
  if (t.equalsIgnoreCase("nan")) {
    return Float.NaN;
  }
  return float(t);
}

float worldToScreenX(float x) {
  return map(x, minX, maxX, 40, width - 40);
}

float worldToScreenY(float y) {
  return map(y, minY, maxY, 40, height - 40);
}

float metersToPixels(float meters) {
  float px0 = worldToScreenX(0);
  float px1 = worldToScreenX(1);
  return abs(px1 - px0) * meters;
}
