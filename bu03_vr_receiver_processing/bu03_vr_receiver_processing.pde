import java.util.*;
import java.net.*;
import oscP5.*;
import netP5.*;

// ============================ CONFIG ============================
int LISTEN_PORT = 8000;      // must match OSC_TARGET_PORT in bu03_visualizer.pde

// Anchor positions A0..A3 in mm -- MUST MATCH the sender sketch.
float[] AX = { 1710, 50, 6420, 6550 };
float[] AY = { 3000, 350, 130, 2960 };

int TRAIL_MAX = 60;
color C_T0 = color(0, 200, 255);
color C_T1 = color(255, 150, 40);

boolean FULLSCREEN = true;   // false -> fixed window (debug on desktop)
int WINDOW_W = 1280;
int WINDOW_H = 720;

long STALE_MS = 2000;        // warn if no packets for this long
// ================================================================

OscP5 osc;
HashMap<Integer, TagData> tags = new HashMap<Integer, TagData>();
int packets = 0;
long lastPacketMs = 0;

float s = 1, ox = 0, oy = 0;

void settings() {
  if (FULLSCREEN) fullScreen();
  else size(WINDOW_W, WINDOW_H);
}

void setup() {
  textSize(16);
  osc = new OscP5(this, LISTEN_PORT);
  println("listening for OSC on port " + LISTEN_PORT);
  try {
    println("local IP: " + InetAddress.getLocalHost().getHostAddress());
  } catch (Exception e) {
    println("could not determine local IP");
  }
}

void draw() {
  background(22);
  updateTransform();
  drawGrid();
  drawAnchors();
  for (Integer id : tags.keySet()) {
    color c = tagColor(id);
    drawTag(id, c, id == 0x0000 ? "T0" : (id == 0x0001 ? "T1" : "0x" + hex(id, 4)));
  }
  drawHud();
}

color tagColor(int id) {
  if (id == 0x0000) return C_T0;
  if (id == 0x0001) return C_T1;
  return color(200, 200, 255);
}

void oscEvent(OscMessage m) {
  if (!m.checkAddrPattern("/pos")) return;
  if (m.typetag().length() < 3) return;
  int tagid = m.get(0).intValue();
  float x = m.get(1).floatValue();
  float y = m.get(2).floatValue();
  packets++;
  lastPacketMs = millis();
  TagData t = tags.get(tagid);
  if (t == null) {
    t = new TagData(tagid);
    tags.put(tagid, t);
  }
  t.pos = new PVector(x, y);
  t.trail.add(t.pos.copy());
  if (t.trail.size() > TRAIL_MAX) t.trail.remove(0);
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
  if (t == null) return;
  if (t.trail.size() >= 2) {
    noFill();
    strokeWeight(2);
    for (int i = 1; i < t.trail.size(); i++) {
      PVector a = scr(t.trail.get(i - 1).x, t.trail.get(i - 1).y);
      PVector b = scr(t.trail.get(i).x, t.trail.get(i).y);
      float f = map(i, 1, t.trail.size() - 1, 15, 200);
      stroke(c, f);
      line(a.x, a.y, b.x, b.y);
    }
  }
  if (t.pos != null) {
    PVector p = scr(t.pos.x, t.pos.y);
    fill(c);
    stroke(255);
    strokeWeight(2);
    ellipse(p.x, p.y, 14, 14);
    fill(255);
    textAlign(LEFT, CENTER);
    text(label, p.x + 10, p.y - 8);
  }
}

void drawHud() {
  textAlign(LEFT, TOP);
  long age = millis() - lastPacketMs;
  if (lastPacketMs == 0) {
    fill(255, 120, 120);
    text("Waiting for OSC on port " + LISTEN_PORT + " ...", 10, 10);
  } else if (age > STALE_MS) {
    fill(255, 120, 120);
    text("STALE: no packets for " + (age / 1000.0f) + " s", 10, 10);
  } else {
    fill(180, 230, 180);
    text("OSC :" + LISTEN_PORT + "  |  packets: " + packets + "  |  age: " + age + " ms", 10, 10);
  }
  int y = 30;
  for (Integer id : tags.keySet()) {
    TagData t = tags.get(id);
    fill(tagColor(id));
    text("0x" + hex(id, 4), 10, y);
    fill(255);
    text(t.pos != null ? "pos=(" + nf(t.pos.x, 0, 0) + ", " + nf(t.pos.y, 0, 0) + ") mm" : "no pos", 60, y);
    y += 20;
  }
  fill(150);
  text("scale: " + nf(s, 0, 3) + " px/mm  |  grid: 500 mm", 10, height - 18);
}

class TagData {
  int id;
  PVector pos;
  ArrayList<PVector> trail = new ArrayList<PVector>();

  TagData(int id) {
    this.id = id;
  }
}
