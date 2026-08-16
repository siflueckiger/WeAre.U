import processing.serial.*;
import java.util.*;

// ============================ CONFIG ============================
String PORT_HINT = "usbmodem";   // substring to auto-find the port (Serial.list())
int BAUD = 115200;

// Anchor positions A0..A3 in mm -- FILL THESE IN with your real geometry.
// Units must match the distance values from the BU03 (mm).
float[] AX = { 1710, 50, 6420, 6550 };
float[] AY = { 3000, 350, 130, 2960 };

// Tag addresses as reported in the frame (hex).
int TAG0_ID = 0x0000;
int TAG1_ID = 0x0001;

int TRAIL_MAX = 60;              // history points per tag
color C_T0 = color(0, 200, 255);
color C_T1 = color(255, 150, 40);
// ================================================================

static final byte[] HEAD = { 'C', 'm', 'd', 'M', ':', '4' };
static final int FRAME_LEN = 101;       // 6 head + 1 len + 91 body + 1 check + 2 foot
static final int EXPECTED_LEN = 91;     // len byte must equal this (sync guard)

Serial port;
String portName = "";
long lastPortTry = -9999;
Parser parser = new Parser();
HashMap<Integer, TagData> tags = new HashMap<Integer, TagData>();
HashSet<Integer> seenIds = new HashSet<Integer>();
int frames = 0;
long lastFrameMs = 0;

float s = 1, ox = 0, oy = 0;

void setup() {
  size(1000, 800);
  trySerial();
}

void draw() {
  background(22);
  if (port == null && millis() - lastPortTry > 2000) trySerial();
  updateTransform();
  drawGrid();
  drawAnchors();
  drawTag(TAG0_ID, C_T0, "T0");
  drawTag(TAG1_ID, C_T1, "T1");
  drawHud();
}

void trySerial() {
  lastPortTry = millis();
  String[] list = Serial.list();
  for (String p : list) {
    if (p.toLowerCase().contains(PORT_HINT.toLowerCase())) {
      try {
        port = new Serial(this, p, BAUD);
        portName = p;
        println("connected: " + p);
      } catch (Exception e) {
        port = null;
        println("failed to open " + p + ": " + e.getMessage());
      }
      return;
    }
  }
  println("no port matching \"" + PORT_HINT + "\" -- available: " + join(list, ", "));
}

void serialEvent(Serial p) {
  byte[] data = p.readBytes();
  if (data == null || data.length == 0) return;
  parser.push(data);
  Frame f;
  while ((f = parser.next()) != null) handleFrame(f);
}

void handleFrame(Frame f) {
  frames++;
  lastFrameMs = millis();
  seenIds.add(f.tagid);
  TagData t = tags.get(f.tagid);
  if (t == null) {
    t = new TagData(f.tagid);
    tags.put(f.tagid, t);
  }
  t.kalman = f.kalman;
  t.mask = f.mask;
  if (f.tagid == TAG0_ID || f.tagid == TAG1_ID) {
    PVector p = trilaterate(t);
    if (p != null) {
      t.pos = p;
      t.trail.add(p.copy());
      if (t.trail.size() > TRAIL_MAX) t.trail.remove(0);
      t.lastFixMs = millis();
    }
  }
}

PVector trilaterate(TagData t) {
  int n = 0;
  for (int i = 0; i < 4; i++) {
    if ((t.mask & (1 << i)) != 0 && t.kalman[i] > 0) n++;
  }
  if (n < 3) return null;

  int r = -1;
  for (int i = 0; i < 4; i++) {
    if ((t.mask & (1 << i)) != 0 && t.kalman[i] > 0) { r = i; break; }
  }
  if (r < 0) return null;
  float dr = t.kalman[r];

  float sxx = 0, sxy = 0, syy = 0, sbx = 0, sby = 0;
  for (int j = 0; j < 4; j++) {
    if (j == r || (t.mask & (1 << j)) == 0 || t.kalman[j] <= 0) continue;
    float a = 2 * (AX[j] - AX[r]);
    float b = 2 * (AY[j] - AY[r]);
    float c = dr * dr - t.kalman[j] * t.kalman[j]
            - (AX[r] * AX[r] + AY[r] * AY[r])
            + (AX[j] * AX[j] + AY[j] * AY[j]);
    sxx += a * a;
    sxy += a * b;
    syy += b * b;
    sbx += a * c;
    sby += b * c;
  }
  float det = sxx * syy - sxy * sxy;
  if (abs(det) < 1e-6f) return null;
  float x = (syy * sbx - sxy * sby) / det;
  float y = (sxx * sby - sxy * sbx) / det;
  return new PVector(x, y);
}

void updateTransform() {
  float minx = min(AX), maxx = max(AX);
  float miny = min(AY), maxy = max(AY);
  float w = maxx - minx;
  float h = maxy - miny;
  if (w < 1) w = 1000;
  if (h < 1) h = 1000;
  float margin = 80;
  s = min((width - 2 * margin) / w, (height - 2 * margin) / h);
  ox = (width - w * s) / 2 - minx * s;
  oy = (height + h * s) / 2 + miny * s;
}

PVector scr(float x, float y) {
  return new PVector(ox + x * s, oy - y * s);
}

void drawGrid() {
  stroke(45);
  strokeWeight(1);
  float minx = min(AX), maxx = max(AX);
  float miny = min(AY), maxy = max(AY);
  float step = 500;
  for (float gx = floor(minx / step) * step; gx <= maxx; gx += step) {
    PVector a = scr(gx, miny), b = scr(gx, maxy);
    line(a.x, a.y, b.x, b.y);
  }
  for (float gy = floor(miny / step) * step; gy <= maxy; gy += step) {
    PVector a = scr(minx, gy), b = scr(maxx, gy);
    line(a.x, a.y, b.x, b.y);
  }
}

void drawAnchors() {
  for (int i = 0; i < AX.length; i++) {
    PVector p = scr(AX[i], AY[i]);
    fill(90, 200, 90);
    stroke(200);
    strokeWeight(2);
    rect(p.x - 8, p.y - 8, 16, 16);
    fill(255);
    textAlign(CENTER, BOTTOM);
    text("A" + i, p.x, p.y - 10);
  }
}

void drawTag(int id, color c, String label) {
  TagData t = tags.get(id);
  float alphaBase = 255;
  if (t == null || t.pos == null || millis() - lastFrameMs > 2000) alphaBase = 90;

  if (t != null && t.trail.size() >= 2) {
    noFill();
    strokeWeight(2);
    for (int i = 1; i < t.trail.size(); i++) {
      PVector a = scr(t.trail.get(i - 1).x, t.trail.get(i - 1).y);
      PVector b = scr(t.trail.get(i).x, t.trail.get(i).y);
      float f = map(i, 1, t.trail.size() - 1, 15, 200);
      stroke(c, f * alphaBase / 255);
      line(a.x, a.y, b.x, b.y);
    }
  }

  if (t != null && t.pos != null) {
    PVector p = scr(t.pos.x, t.pos.y);
    fill(c, alphaBase);
    stroke(255, alphaBase);
    strokeWeight(2);
    ellipse(p.x, p.y, 14, 14);
    fill(255, alphaBase);
    textAlign(LEFT, CENTER);
    text(label, p.x + 10, p.y - 8);
  }
}

void drawHud() {
  textAlign(LEFT, TOP);
  int y = 10;
  if (port == null) {
    fill(255, 120, 120);
    text("Serial: NOT CONNECTED (looking for port containing \"" + PORT_HINT + "\")", 10, y);
    fill(255);
    y += 18;
  } else {
    text("Serial: " + portName + " @ " + BAUD + "  |  frames: " + frames, 10, y);
    y += 18;
  }

  for (Integer i : seenIds) {
    if (i != TAG0_ID && i != TAG1_ID) {
      fill(255, 200, 80);
      text("Warning: unknown TagID 0x" + hex(i, 4) + " seen -- check TAG0_ID/TAG1_ID", 10, y);
      y += 18;
      break;
    }
  }

  if (millis() - lastFrameMs > 2000 && port != null) {
    fill(255, 120, 120);
    text("No data for >2s", 10, y);
    fill(255);
    y += 18;
  }

  y += 8;
  hudTag(y, TAG0_ID, "T0", C_T0);
  y += 56;
  hudTag(y, TAG1_ID, "T1", C_T1);
  fill(150);
  text("scale: " + nf(s, 0, 3) + " px/mm  |  grid: 500 mm", 10, height - 18);
}

void hudTag(int y, int id, String label, color c) {
  TagData t = tags.get(id);
  fill(c);
  text(label, 10, y);
  fill(255);
  if (t == null) {
    text("no frames yet", 40, y);
    return;
  }
  String pos = (t.pos != null)
    ? "pos=(" + nf(t.pos.x, 0, 0) + ", " + nf(t.pos.y, 0, 0) + ") mm"
    : "pos=-- (no fix, <3 valid distances)";
  text("tagid=0x" + hex(t.id, 4) + "  " + pos + "  mask=" + binary(t.mask, 8), 40, y);
  String d = "  ";
  for (int i = 0; i < 4; i++) {
    if ((t.mask & (1 << i)) != 0 && t.kalman[i] > 0) d += "A" + i + "=" + t.kalman[i] + "  ";
    else d += "A" + i + "=--  ";
  }
  fill(200);
  text(d, 40, y + 18);
}

class TagData {
  int id;
  int mask;
  int[] kalman = new int[8];
  PVector pos;
  long lastFixMs;
  ArrayList<PVector> trail = new ArrayList<PVector>();

  TagData(int id) {
    this.id = id;
  }
}

class Frame {
  int tagid;
  int mask;
  int[] kalman = new int[8];
}

class Parser {
  byte[] buf = new byte[4096];
  int len = 0;

  void push(byte[] data) {
    if (len + data.length > buf.length) {
      buf = java.util.Arrays.copyOf(buf, max(buf.length * 2, len + data.length));
    }
    System.arraycopy(data, 0, buf, len, data.length);
    len += data.length;
  }

  Frame next() {
    int idx = findHead();
    while (idx != -1) {
      if (len - idx < FRAME_LEN) {
        shift(idx);
        return null;
      }
      if ((buf[idx + 6] & 0xFF) != EXPECTED_LEN) {
        shift(idx + 1);
        idx = findHead();
        continue;
      }
      Frame f = new Frame();
      f.tagid = u16(idx + 11);
      f.mask = buf[idx + 16] & 0xFF;
      for (int i = 0; i < 8; i++) f.kalman[i] = u32(idx + 50 + 4 * i);
      shift(idx + FRAME_LEN);
      return f;
    }
    if (len > HEAD.length - 1) shift(len - (HEAD.length - 1));
    return null;
  }

  int findHead() {
    outer:
    for (int i = 0; i + HEAD.length <= len; i++) {
      for (int j = 0; j < HEAD.length; j++) {
        if (buf[i + j] != HEAD[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  void shift(int n) {
    if (n <= 0) return;
    if (n >= len) { len = 0; return; }
    System.arraycopy(buf, n, buf, 0, len - n);
    len -= n;
  }

  int u16(int off) {
    return (buf[off] & 0xFF) | ((buf[off + 1] & 0xFF) << 8);
  }

  int u32(int off) {
    return (buf[off] & 0xFF)
         | ((buf[off + 1] & 0xFF) << 8)
         | ((buf[off + 2] & 0xFF) << 16)
         | ((buf[off + 3] & 0xFF) << 24);
  }
}
