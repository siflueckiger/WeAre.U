import processing.serial.*;
import java.util.*;
import oscP5.*;
import netP5.*;

// ============================ CONFIG ============================
String PORT_HINT = "usbmodem";   // substring to auto-find the port (Serial.list())
int BAUD = 115200;

// Anchor positions A0..A3 in mm -- standard layout: 3x7m field.
// A0 top left, A1 bottom left, A2 bottom right, A3 top right.
// Setup mode (auto-layout from measured distances) or config.json override these.
float[] AX = { 0, 0, 7000, 7000 };
float[] AY = { 3000, 0, 0, 3000 };

// Tag addresses as reported in the frame (hex).
int TAG0_ID = 0x0000;
int TAG1_ID = 0x0001;

int TRAIL_MAX = 60;              // history points per tag
color C_T0 = color(0, 200, 255);
color C_T1 = color(255, 150, 40);

// Smoothing filters -- toggle live with keys 1/2, key 4 cycles alpha
boolean USE_SPEED_CLAMP = true;  // limit position jumps to MAX_SPEED_MM_S
boolean USE_EMA         = true;  // exponential smoothing on X/Y

float MAX_SPEED_MM_S = 4200;     // 10 km/h * 1.5 safety factor
float SMOOTH_ALPHA   = 0.30;     // 0 = frozen, 1 = unfiltered

// OSC out (Raspberry Pi VR headset receiver)
boolean OSC_ENABLED = true;
String  OSC_TARGET_IP   = "192.168.1.106";  // FILL IN: Pi IP
int     OSC_TARGET_PORT = 8000;
int     OSC_LOCAL_PORT  = 12000;            // unused listen port (required by oscP5)

// ============================ GAME ============================
// Game states -- MUST MATCH receiver/receiver.py
int STATE_WAIT     = 0;   // players must reach their start zones
int STATE_PLAYING  = 1;   // round running
int STATE_GAMEOVER = 2;   // winner screen, auto restart
int STATE_READY    = 3;   // countdown before round start

int GAME_TIME_S             = 30;    // round duration in seconds (engine-owned)
float READY_S               = 3;      // countdown length
float GAMEOVER_S            = 10;     // winner screen length
float START_ZONE_RADIUS_MM  = 250;    // radius a player must be within

// Out-of-bounds: real players can leave the anchor field. Engine tracks how long
// a player is outside and warns, then ends the round (see Core_GameMode.pde).
float OOB_MARGIN_MM   = 400;          // tolerance beyond the field border
float OOB_TIMEOUT_S   = 5;            // seconds outside before the round ends

// Start positions per player -- standard: middle of the field, 1 m apart.
// Override in setup mode (Z/X capture or mouse drag) / config.json.
float[] P1_START = { 3000, 1500 };
float[] P2_START = { 4000, 1500 };

int OSC_GAME_INTERVAL_MS = 100;       // stats + entity send rate

// ============================ SETUP MODE ============================
// App modes: TAB toggles between game and interactive setup.
int MODE_GAME  = 0;
int MODE_SETUP = 1;

// Measured anchor distances in mm, pairs: 01 02 03 12 13 23.
// Set in setup mode, auto-layout computes AX/AY from them.
float[] anchorD = new float[6];
int[][] D_PAIRS = { {0, 1}, {0, 2}, {0, 3}, {1, 2}, {1, 3}, {2, 3} };
String[] D_NAMES = { "A0-A1", "A0-A2", "A0-A3", "A1-A2", "A1-A3", "A2-A3" };

String CONFIG_FILENAME = "config.json";
float LAYOUT_WARN_MM = 200;           // D23 mismatch warning threshold
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

OscP5 osc;
NetAddress piAddr;
int oscSent = 0;

float s = 1, ox = 0, oy = 0;

// game state (engine-owned; mode state lives in the Mode_* classes)
int gameState = STATE_WAIT;
float timeLeft = 0;
long stateEnteredMs = 0;
long lastTickMs = 0;
long lastGameOscMs = 0;
float[] oobCountdown = { OOB_TIMEOUT_S, OOB_TIMEOUT_S };
boolean[] oobActive = { false, false };
int roundWinner = -1;   // -1 = derive from scores, 1/2 = forced winner

int appMode = MODE_GAME;

boolean hudDebug = false;   // D: full tag details in player cards
boolean hudKeys  = false;   // H: full key help overlay

void setup() {
  size(1000, 800);
  try {
    osc = new OscP5(this, OSC_LOCAL_PORT);
    piAddr = new NetAddress(OSC_TARGET_IP, OSC_TARGET_PORT);
    println("OSC -> " + OSC_TARGET_IP + ":" + OSC_TARGET_PORT);
  } catch (Exception e) {
    osc = null;
    piAddr = null;
    println("OSC init failed (disabled): " + e.getMessage());
  }
  loadConfig();
  currentMode.onModeEnter();
  sendModeOsc();
  sendStartZones();
  sendAnchors();
  trySerial();
}

void draw() {
  background(22);
  if (port == null && millis() - lastPortTry > 2000) trySerial();
  updateTransform();
  if (appMode == MODE_GAME) {
    updateVirtualTags();
    updateGame();
    sendGameOsc();
  }
  drawGrid();
  drawAnchors();
  if (appMode == MODE_GAME) {
    drawStartZones();
    currentMode.drawWorld();
    drawEntitiesDebug();
  }
  drawTag(TAG0_ID, C_T0, "P1");
  drawTag(TAG1_ID, C_T1, "P2");
  if (appMode == MODE_GAME) {
    drawOobMarkers();
    drawHud();
  }
  else setupDraw();   // defined in Setup.pde
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
  try {
    byte[] data = p.readBytes();
    if (data == null || data.length == 0) return;
    parser.push(data);
    Frame f;
    while ((f = parser.next()) != null) handleFrame(f);
  } catch (Exception e) {
    println("serialEvent error: " + e);
  }
}

void handleFrame(Frame f) {
  if (virtualOn) return;   // virtual players own the tags while enabled
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
      long now = millis();
      boolean first = (t.pos == null || t.lastFixMs == 0);
      if (!first && USE_SPEED_CLAMP) {
        float dt = (now - t.lastFixMs) / 1000.0f;
        float maxD = MAX_SPEED_MM_S * max(dt, 0.02f);
        float dx = p.x - t.pos.x, dy = p.y - t.pos.y;
        float d = sqrt(dx * dx + dy * dy);
        if (d > maxD) p = new PVector(t.pos.x + dx / d * maxD, t.pos.y + dy / d * maxD);
      }
      PVector oldPos = t.pos;
      if (!first && USE_EMA) {
        t.pos = new PVector(lerp(t.pos.x, p.x, SMOOTH_ALPHA), lerp(t.pos.y, p.y, SMOOTH_ALPHA));
      } else {
        t.pos = p;
      }
      if (!first) {
        float dt = (now - t.lastFixMs) / 1000.0f;
        if (dt > 0) t.speedMs = PVector.dist(oldPos, t.pos) / dt;
      }
      t.trail.add(t.pos.copy());
      if (t.trail.size() > TRAIL_MAX) t.trail.remove(0);
      t.lastFixMs = now;
      sendPos(f.tagid, t.pos.x, t.pos.y);
    }
  }
}

// ============================ KEYS ============================

void keyPressed() {
  if (key == CODED && keyCode == SHIFT) {
    shiftHeld = true;
    return;
  }
  if (key == TAB) {
    if (appMode == MODE_GAME) setState(STATE_WAIT);   // abort any running round
    setAppMode(appMode == MODE_GAME ? MODE_SETUP : MODE_GAME);
    return;
  }
  if (appMode == MODE_SETUP) {
    setupKey();   // defined in Setup.pde
    return;
  }
  if (key == 'v' || key == 'V') {
    toggleVirtual();
    return;
  }
  if (virtualEnabled() && vKeyDown()) return;   // movement key consumed

  if (key == 'm' || key == 'M') {
    nextMode();
    return;
  }
  if (key == 'r' || key == 'R') {
    setState(STATE_WAIT);              // reset / abort the round at any time
    if (virtualEnabled()) resetVirtualPlayers();
    println("round reset (R)");
    return;
  }
  if (key == 'd' || key == 'D') {
    hudDebug = !hudDebug;
    println("HUD debug: " + onOff(hudDebug));
    return;
  }
  if (key == 'h' || key == 'H') {
    hudKeys = !hudKeys;
    println("HUD key help: " + onOff(hudKeys));
    return;
  }

  if (key == '1') {
    USE_SPEED_CLAMP = !USE_SPEED_CLAMP;
    println("Speed clamp: " + onOff(USE_SPEED_CLAMP));
  } else if (key == '2') {
    USE_EMA = !USE_EMA;
    println("EMA: " + onOff(USE_EMA));
  } else if (key == '4') {
    if (SMOOTH_ALPHA < 0.25f) SMOOTH_ALPHA = 0.30f;
    else if (SMOOTH_ALPHA < 0.40f) SMOOTH_ALPHA = 0.50f;
    else if (SMOOTH_ALPHA < 0.65f) SMOOTH_ALPHA = 0.80f;
    else SMOOTH_ALPHA = 0.15f;
    println("EMA alpha: " + SMOOTH_ALPHA);
  } else if (key == ' ') {
    // debug: start / skip through the round from any state
    if (gameState == STATE_WAIT) {
      debugStartRound();
    } else if (gameState == STATE_READY) {
      debugStartRound();   // skip the remaining countdown
    } else if (gameState == STATE_GAMEOVER) {
      setState(STATE_WAIT);   // skip the result screen
    }
  } else {
    currentMode.keyPressed(key);   // mode-specific keys
  }
}

// ============================ APP MODE / CONFIG ============================

void setAppMode(int m) {
  appMode = m;
  if (m == MODE_GAME) {
    setState(STATE_WAIT);   // clean restart after setup
    sendModeOsc();
    sendStartZones();
    sendAnchors();
  }
  println("app mode -> " + (m == MODE_GAME ? "GAME" : "SETUP"));
}

void loadConfig() {
  File f = new File(dataPath(CONFIG_FILENAME));
  if (!f.exists()) {
    println("no " + CONFIG_FILENAME + " -- using built-in defaults");
    computeD();
    return;
  }
  try {
    JSONObject j = loadJSONObject(CONFIG_FILENAME);
    JSONArray ax = j.getJSONArray("AX");
    JSONArray ay = j.getJSONArray("AY");
    if (ax != null && ay != null && ax.size() == 4 && ay.size() == 4) {
      for (int i = 0; i < 4; i++) {
        AX[i] = ax.getFloat(i);
        AY[i] = ay.getFloat(i);
      }
    }
    JSONArray d = j.getJSONArray("D");
    if (d != null && d.size() == 6) for (int i = 0; i < 6; i++) anchorD[i] = d.getFloat(i);
    else computeD();
    JSONArray p1 = j.getJSONArray("P1_START");
    if (p1 != null && p1.size() == 2) { P1_START[0] = p1.getFloat(0); P1_START[1] = p1.getFloat(1); }
    JSONArray p2 = j.getJSONArray("P2_START");
    if (p2 != null && p2.size() == 2) { P2_START[0] = p2.getFloat(0); P2_START[1] = p2.getFloat(1); }
    String modeId = j.getString("MODE");
    if (modeId != null && !modeId.isEmpty()) applyModeId(modeId);
    println("config loaded: " + dataPath(CONFIG_FILENAME));
  } catch (Exception e) {
    println("config load failed: " + e.getMessage());
    computeD();
  }
}

void saveConfig() {
  try {
    JSONObject j = new JSONObject();
    JSONArray ax = new JSONArray();
    JSONArray ay = new JSONArray();
    for (int i = 0; i < 4; i++) { ax.setFloat(i, AX[i]); ay.setFloat(i, AY[i]); }
    j.setJSONArray("AX", ax);
    j.setJSONArray("AY", ay);
    JSONArray d = new JSONArray();
    for (int i = 0; i < 6; i++) d.setFloat(i, anchorD[i]);
    j.setJSONArray("D", d);
    JSONArray p1 = new JSONArray();
    JSONArray p2 = new JSONArray();
    p1.setFloat(0, P1_START[0]); p1.setFloat(1, P1_START[1]);
    p2.setFloat(0, P2_START[0]); p2.setFloat(1, P2_START[1]);
    j.setJSONArray("P1_START", p1);
    j.setJSONArray("P2_START", p2);
    j.setString("MODE", currentMode.id);
    saveJSONObject(j, CONFIG_FILENAME);
    println("config saved: " + dataPath(CONFIG_FILENAME));
  } catch (Exception e) {
    println("config save failed: " + e.getMessage());
  }
}

void computeD() {
  for (int i = 0; i < 6; i++) {
    anchorD[i] = dist(AX[D_PAIRS[i][0]], AY[D_PAIRS[i][0]], AX[D_PAIRS[i][1]], AY[D_PAIRS[i][1]]);
  }
}

String onOff(boolean b) {
  return b ? "ON" : "OFF";
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
  // Keep the field clear of the header (top) and footer (bottom) in game mode,
  // so no HUD panel ever overlaps the action.
  float top = (appMode == MODE_GAME) ? HUD_HEADER_H + 16 : 80;
  float bottom = (appMode == MODE_GAME) ? height - HUD_FOOTER_H - 16 : height - 80;
  float sideMargin = (appMode == MODE_GAME) ? 24 : 80;
  float availW = width - 2 * sideMargin;
  float availH = bottom - top;
  s = min(availW / w, availH / h);
  float fieldTop = top + (availH - h * s) / 2;
  ox = sideMargin + (availW - w * s) / 2 - minx * s;
  oy = fieldTop + maxy * s;
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

void drawStartZones() {
  if (appMode != MODE_SETUP && gameState != STATE_WAIT && gameState != STATE_READY) return;
  drawZone(P1_START, "P1", C_T0);
  drawZone(P2_START, "P2", C_T1);
}

void drawZone(float[] p, String label, color c) {
  PVector q = scr(p[0], p[1]);
  float r = START_ZONE_RADIUS_MM * s;
  noFill();
  stroke(c, 160);
  strokeWeight(2);
  ellipse(q.x, q.y, 2 * r, 2 * r);
  fill(c);
  textAlign(CENTER, CENTER);
  text(label, q.x, q.y);
}

void drawOobMarkers() {
  drawOobMarker(TAG0_ID, 0);
  drawOobMarker(TAG1_ID, 1);
}

void drawOobMarker(int id, int idx) {
  if (!oobActive[idx]) return;
  TagData t = tags.get(id);
  if (t == null || t.pos == null) return;
  PVector p = scr(t.pos.x, t.pos.y);
  noFill();
  stroke(255, 60, 60);
  strokeWeight(4);
  float r = max(20, 40 * s);
  ellipse(p.x, p.y, 2 * r, 2 * r);
  fill(255, 80, 80);
  textAlign(CENTER, BOTTOM);
  text("GO BACK! " + (int)ceil(oobCountdown[idx]) + "s", p.x, p.y - r - 4);
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

// ============================ HUD ============================
// Game view layout: a unified header across the top (P1 | center | P2), a
// completely free playing field in the middle, floating warnings only when
// active, and a compact status footer at the bottom. Player debug details are
// hidden behind the D key; the full key list is a centered overlay (H).

int HUD_HEADER_H = 96;
int HUD_FOOTER_H = 30;

void drawHud() {
  textSize(12);
  textAlign(LEFT, TOP);
  drawGameHeader();
  drawWarnings();
  drawFooter();
  if (hudDebug) drawDebugCards();
  if (hudKeys) drawKeyHelp();
}

// Panel background + title bar. Body text is drawn by the caller.
void hudPanel(int x, int y, int w, int h, String title, color titleCol) {
  noStroke();
  fill(12, 12, 18, 215);
  rect(x, y, w, h);
  fill(titleCol);
  rect(x, y, w, 18);
  fill(0);
  text(title, x + 6, y + 3);
}

color stateColor(int s) {
  if (s == STATE_WAIT) return color(160, 160, 160);
  if (s == STATE_READY) return color(255, 230, 120);
  if (s == STATE_PLAYING) return color(140, 230, 140);
  if (s == STATE_GAMEOVER) return color(255, 170, 60);
  return color(255, 255, 255);
}

void drawGameHeader() {
  noStroke();
  fill(12, 12, 18, 230);
  rect(0, 0, width, HUD_HEADER_H);
  // subtle separator
  stroke(60);
  line(0, HUD_HEADER_H, width, HUD_HEADER_H);
  noStroke();

  // ----- center: mode, big value, state -----
  color sc = stateColor(gameState);
  textAlign(CENTER, TOP);
  textSize(13);
  fill(200);
  text(currentMode.displayName.toUpperCase(), width / 2.0f, 8);

  textSize(36);
  fill(sc);
  text(centerValueText(), width / 2.0f, 24);

  textSize(12);
  fill(sc);
  text(stateName(gameState), width / 2.0f, HUD_HEADER_H - 32);

  String[] lines = currentMode.hudLines();
  if (lines != null && lines.length > 0) {
    textSize(11);
    fill(235, 210, 150);
    text(join(lines, "    "), width / 2.0f, HUD_HEADER_H - 16);
  }

  // ----- sides -----
  drawHeaderPlayer(0, 16);
  drawHeaderPlayer(1, width - 16);
}

String centerValueText() {
  if (gameState == STATE_WAIT) {
    return (inZone(tags.get(TAG0_ID), P1_START) && inZone(tags.get(TAG1_ID), P2_START))
      ? "STARTING" : "WAITING";
  }
  if (gameState == STATE_READY) return "" + max(1, (int)ceil(timeLeft));
  if (gameState == STATE_PLAYING) return nf(timeLeft, 0, 0) + "s";
  return "GAME OVER";
}

void drawHeaderPlayer(int p, float x) {
  color c = (p == 0) ? C_T0 : C_T1;
  boolean left = (p == 0);
  int[] sc = currentMode.scores();

  textAlign(left ? LEFT : RIGHT, TOP);
  textSize(13);
  fill(c);
  text("P" + (p + 1), x, 8);

  textSize(36);
  fill(c);
  text("" + sc[p], x, 22);

  // lives as filled pips (if the mode tracks lives)
  int lives = currentMode.playerLives(p);
  float pipY = 66;
  if (lives >= 0) {
    float pipR = 5, gap = 5;
    int n = max(1, lives);
    float total = n * 2 * pipR + (n - 1) * gap;
    float sx = left ? x : x - total;
    noStroke();
    for (int i = 0; i < n; i++) {
      float cx = sx + pipR + i * (2 * pipR + gap);
      if (i < lives) {
        fill(c);
      } else {
        noFill();
        stroke(c, 80);
        strokeWeight(1);
      }
      ellipse(cx, pipY, 2 * pipR, 2 * pipR);
      noStroke();
    }
    fill(c);
  }

  // start-zone status while waiting/ready, otherwise active powerups
  textSize(11);
  if (gameState == STATE_WAIT || gameState == STATE_READY) {
    boolean inz = inZone(tags.get(p == 0 ? TAG0_ID : TAG1_ID), p == 0 ? P1_START : P2_START);
    fill(inz ? color(140, 230, 140) : color(255, 150, 90));
    text(inz ? "IN ZONE" : "GO TO ZONE", x, 78);
  } else {
    String[] fx = currentMode.playerEffects(p);
    if (fx.length > 0) {
      fill(235, 210, 150);
      text(join(fx, "  "), x, 78);
    }
  }
  textAlign(LEFT, TOP);
}

void drawWarnings() {
  ArrayList<String> warns = new ArrayList<String>();
  if (!virtualOn && port == null) {
    warns.add("SERIAL NOT CONNECTED -- searching port \"" + PORT_HINT + "\"");
  } else if (!virtualOn && millis() - lastFrameMs > 2000) {
    warns.add("NO TAG DATA FOR >2s");
  }
  for (Integer i : seenIds) {
    if (i != TAG0_ID && i != TAG1_ID) {
      warns.add("UNKNOWN TagID 0x" + hex(i, 4) + " -- check TAG0_ID/TAG1_ID");
      break;
    }
  }
  if (oobActive[0]) warns.add("P1: GO BACK NOW OR LOSE A LIFE (" + (int)ceil(oobCountdown[0]) + "s)");
  if (oobActive[1]) warns.add("P2: GO BACK NOW OR LOSE A LIFE (" + (int)ceil(oobCountdown[1]) + "s)");

  int y = HUD_HEADER_H + 12;
  for (String w : warns) {
    boolean flash = w.startsWith("P1:") || w.startsWith("P2:");
    float a = flash ? (170 + 85 * sin(millis() / 150.0f)) : 215;
    color c = w.startsWith("UNKNOWN") ? color(255, 160, 40, a) : color(255, 50, 50, a);
    textSize(14);
    float tw = textWidth(w);
    textSize(12);
    float px = width / 2.0f - tw / 2.0f - 8;
    noStroke();
    fill(c);
    rect(px, y, tw + 16, 22);
    fill(255);
    text(w, px + 8, y + 4);
    y += 26;
  }
}

// Debug overlay (D): compact raw tag info, only on demand so it never clutters
// normal play.
void drawDebugCards() {
  int w = 300, h = 92, y = HUD_HEADER_H + 10;
  drawDebugCard(TAG0_ID, "P1", C_T0, 10, y, w, h);
  drawDebugCard(TAG1_ID, "P2", C_T1, width - 10 - w, y, w, h);
}

void drawDebugCard(int id, String label, color c, int x, int y, int w, int h) {
  hudPanel(x, y, w, h, label + "  (debug)", c);
  TagData t = tags.get(id);
  fill(255);
  textAlign(LEFT, TOP);
  textSize(11);
  if (t == null) {
    text("no frames yet", x + 8, y + 24);
    return;
  }
  if (t.pos != null) {
    text("pos " + nf(t.pos.x, 0, 0) + ", " + nf(t.pos.y, 0, 0) + " mm   " + nf(t.speedMs / 1000.0f, 0, 2) + " m/s", x + 8, y + 24);
  } else {
    text("no fix (<3 anchors)", x + 8, y + 24);
  }
  fill(200);
  text("tagid 0x" + hex(t.id, 4) + "  mask " + binary(t.mask, 8) + "  trail " + t.trail.size() + "/" + TRAIL_MAX, x + 8, y + 40);
  text(anchorStr(t, 0) + "  " + anchorStr(t, 1) + "  " + anchorStr(t, 2) + "  " + anchorStr(t, 3), x + 8, y + 56);
  fill(255);
}

String anchorStr(TagData t, int i) {
  String v = ((t.mask & (1 << i)) != 0 && t.kalman[i] > 0) ? nf(t.kalman[i], 0, 0) : "--";
  return "A" + i + "=" + v;
}

// ============================ FOOTER ============================

void drawFooter() {
  int fy = height - HUD_FOOTER_H;
  noStroke();
  fill(12, 12, 18, 238);
  rect(0, fy, width, HUD_FOOTER_H);
  stroke(60);
  line(0, fy, width, fy);
  noStroke();

  float cy = fy + HUD_FOOTER_H / 2.0f;
  textAlign(LEFT, CENTER);
  textSize(11);

  color dot;
  String serial;
  if (virtualOn) { dot = color(120, 180, 255); serial = "VIRTUAL SIM"; }
  else if (port == null) { dot = color(255, 80, 80); serial = "SERIAL --"; }
  else { dot = color(120, 230, 120); serial = "SERIAL OK"; }
  fill(dot);
  ellipse(16, cy, 10, 10);
  text(serial, 26, cy);

  fill(170);
  text("OSC " + (OSC_ENABLED ? OSC_TARGET_IP + ":" + OSC_TARGET_PORT : "OFF")
    + "   frames " + frames + "   scale " + nf(s, 0, 3), 150, cy);

  fill(170);
  text("Clamp " + onOff(USE_SPEED_CLAMP) + "  EMA " + onOff(USE_EMA) + " a=" + nf(SMOOTH_ALPHA, 0, 2), 430, cy);

  textAlign(RIGHT, CENTER);
  fill(150);
  text("V virtual   R reset   SPACE start   TAB setup   M mode   D debug   H help", width - 14, cy);
  textAlign(LEFT, TOP);
}

// ============================ KEY HELP OVERLAY (H) ============================

void drawKeyHelp() {
  String[] lines = {
    "TAB ........ Setup mode",
    "M .......... next mode / reset",
    "V .......... virtual players (debug)",
    "SPACE ...... start / skip round",
    "R .......... reset / abort round",
    "1 / 2 ...... filters on/off",
    "4 .......... EMA alpha",
    "D .......... tag debug details",
    "H .......... hide this help",
    "WASD / arrows = move virtual P1/P2"
  };
  int w = 300, h = 24 + lines.length * 18 + 10;
  int x = width / 2 - w / 2, y = height / 2 - h / 2;
  hudPanel(x, y, w, h, "KEYS", color(180, 200, 220));
  fill(255);
  textAlign(LEFT, TOP);
  textSize(12);
  for (int i = 0; i < lines.length; i++) text(lines[i], x + 10, y + 26 + i * 18);
}

class TagData {
  int id;
  int mask;
  int[] kalman = new int[8];
  float speedMs;
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
