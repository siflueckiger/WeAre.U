// ============================ SETUP MODE ============================
// Interactive calibration: measured anchor distances -> auto-layout,
// start zones via live tag capture or mouse drag. Toggle with TAB.
//
// Keys:  hoch/runter wählen, links/rechts -/+10mm (shift = 1mm)
//        ziffern: wert eingeben, backspace: löschen, enter: bestätigen
//        L = auto-layout, R = standard 3x7m, Z/X = P1-/P2-Startposition
//        übernehmen, V = config speichern

int anchorDIdx = 0;     // selected distance entry (0..5)
int dragAnchor = -1;    // anchor index being dragged, -1 = none
int dragZone = -1;      // 0 = P1 zone, 1 = P2 zone, -1 = none
String setupStatus = "";
boolean shiftHeld = false;   // set in keyPressed()/keyReleased() (main tab)
String distInput = "";       // typed digits for the selected distance

void keyReleased() {
  if (key == CODED && keyCode == SHIFT) shiftHeld = false;
}

void setupDraw() {
  drawDistances();
  drawAnchorHighlight();
  drawStartZones();
  drawSetupPanel();
}

void drawDistances() {
  textAlign(CENTER, CENTER);
  for (int i = 0; i < 6; i++) {
    int a = D_PAIRS[i][0], b = D_PAIRS[i][1];
    PVector pa = scr(AX[a], AY[a]);
    PVector pb = scr(AX[b], AY[b]);
    if (i == anchorDIdx) {
      stroke(255, 230, 120, 220);
      strokeWeight(2);
    } else {
      stroke(140, 140, 170, 90);
      strokeWeight(1);
    }
    line(pa.x, pa.y, pb.x, pb.y);
    fill(i == anchorDIdx ? color(255, 230, 120) : color(200, 200, 255));
    text(nf(anchorD[i], 0, 0), (pa.x + pb.x) / 2, (pa.y + pb.y) / 2 - 6);
  }
}

void drawAnchorHighlight() {
  noFill();
  stroke(255, 230, 120);
  strokeWeight(3);
  int a = D_PAIRS[anchorDIdx][0], b = D_PAIRS[anchorDIdx][1];
  for (int k = 0; k < 2; k++) {
    int idx = (k == 0) ? a : b;
    PVector p = scr(AX[idx], AY[idx]);
    rect(p.x - 11, p.y - 11, 22, 22);
  }
}

void drawSetupPanel() {
  int x = 10, y = 10;
  textAlign(LEFT, TOP);
  fill(255, 230, 120);
  text("SETUP-MODUS  |  TAB -> GAME", x, y);
  y += 20;
  fill(200);
  text("Anker-Distanzen (gemessen):", x, y);
  y += 18;
  for (int i = 0; i < 6; i++) {
    fill(i == anchorDIdx ? color(255, 230, 120) : color(200));
    String val = (i == anchorDIdx && !distInput.isEmpty())
      ? distInput + "_"
      : nf(anchorD[i], 0, 0) + " mm";
    text((i == anchorDIdx ? "> " : "  ") + D_NAMES[i] + " = " + val, x, y);
    y += 16;
  }
  y += 6;
  fill(150);
  for (int i = 0; i < 4; i++) {
    text("A" + i + " = (" + nf(AX[i], 0, 0) + ", " + nf(AY[i], 0, 0) + ")", x, y);
    y += 14;
  }
  y += 6;
  fill(200);
  text("hoch/runter: wählen   links/rechts: -/+10mm (shift 1mm)", x, y);
  y += 14;
  text("ziffern: wert eingeben   backspace: löschen   enter: bestätigen", x, y);
  y += 14;
  text("L: auto-layout   Z/X: P1-/P2-Startposition übernehmen", x, y);
  y += 14;
  text("R: standard 3x7m   maus: anchors + zonen ziehen   V: config speichern", x, y);
  y += 14;
  if (!setupStatus.isEmpty()) {
    fill(255, 150, 150);
    text(setupStatus, x, y);
  }
}

void setupKey() {
  if (key == CODED) {
    distInput = "";
    if (keyCode == UP) {
      anchorDIdx = (anchorDIdx + 5) % 6;
      setupStatus = "gewählt: " + D_NAMES[anchorDIdx];
    } else if (keyCode == DOWN) {
      anchorDIdx = (anchorDIdx + 1) % 6;
      setupStatus = "gewählt: " + D_NAMES[anchorDIdx];
    } else if (keyCode == LEFT) {
      anchorD[anchorDIdx] = max(0, anchorD[anchorDIdx] - (shiftHeld ? 1 : 10));
    } else if (keyCode == RIGHT) {
      anchorD[anchorDIdx] += (shiftHeld ? 1 : 10);
    }
    return;
  }
  if (key >= '0' && key <= '9') {
    distInput += key;
    anchorD[anchorDIdx] = float(distInput);
    setupStatus = D_NAMES[anchorDIdx] + " Eingabe: " + distInput;
    return;
  }
  if (key == BACKSPACE || key == DELETE) {
    if (distInput.length() > 0) {
      distInput = distInput.substring(0, distInput.length() - 1);
      anchorD[anchorDIdx] = distInput.isEmpty() ? 0 : float(distInput);
    }
    return;
  }
  if (key == ENTER || key == RETURN) {
    distInput = "";
    setupStatus = D_NAMES[anchorDIdx] + " = " + nf(anchorD[anchorDIdx], 0, 0) + " mm";
    return;
  }
  if (key == ESC) {
    distInput = "";
    setupStatus = "Eingabe abgebrochen";
    return;
  }
  if (key == 'l' || key == 'L') {
    applyLayout();
  } else if (key == 'r' || key == 'R') {
    standardLayout();
  } else if (key == 'z' || key == 'Z') {
    captureZone(0);
  } else if (key == 'x' || key == 'X') {
    captureZone(1);
  } else if (key == 'v' || key == 'V') {
    saveConfig();
    sendStartZones();
    setupStatus = "Config gespeichert";
  }
}

// Auto-layout from the 6 measured distances:
// A0 = origin, A1 on +X axis, A2/A3 above the A0-A1 axis (circle intersection).
// D23 is only used as a sanity check.
void applyLayout() {
  distInput = "";
  float d01 = anchorD[0], d02 = anchorD[1], d03 = anchorD[2];
  float d12 = anchorD[3], d13 = anchorD[4], d23 = anchorD[5];
  if (d01 < 1) {
    setupStatus = "A0-A1 zu klein";
    return;
  }
  AX[0] = 0; AY[0] = 0;
  AX[1] = d01; AY[1] = 0;

  float x2 = (d02 * d02 - d12 * d12 + d01 * d01) / (2 * d01);
  float y2sq = d02 * d02 - x2 * x2;
  float x3 = (d03 * d03 - d13 * d13 + d01 * d01) / (2 * d01);
  float y3sq = d03 * d03 - x3 * x3;

  setupStatus = "Layout berechnet";
  if (y2sq < 0) {
    setupStatus = "WARNUNG: A2 inkonsistent (Dreiecksungleichung) – geklemmt";
    y2sq = 0;
  }
  if (y3sq < 0) {
    setupStatus = "WARNUNG: A3 inkonsistent (Dreiecksungleichung) – geklemmt";
    y3sq = 0;
  }
  AX[2] = x2; AY[2] = sqrt(y2sq);
  AX[3] = x3; AY[3] = sqrt(y3sq);

  float d23c = dist(AX[2], AY[2], AX[3], AY[3]);
  if (abs(d23c - d23) > LAYOUT_WARN_MM) {
    setupStatus = "WARNUNG: A2-A3-Check fehlgeschlagen (" + nf(d23c, 0, 0) + " vs " + nf(d23, 0, 0) + ")";
  }
  computeD();   // keep panel consistent with geometry
  sendAnchors();
}

// Reset to the standard 3x7m field: A0 top left, A1 bottom left,
// A2 bottom right, A3 top right.
void standardLayout() {
  AX[0] = 0;      AY[0] = 3000;
  AX[1] = 0;      AY[1] = 0;
  AX[2] = 7000;   AY[2] = 0;
  AX[3] = 7000;   AY[3] = 3000;
  distInput = "";
  computeD();
  sendAnchors();
  setupStatus = "Standard-Layout 3x7m gesetzt";
}

void captureZone(int player) {
  int id = player == 0 ? TAG0_ID : TAG1_ID;
  TagData t = tags.get(id);
  if (t == null || t.pos == null) {
    setupStatus = "P" + (player + 1) + ": noch kein Positions-Fix";
    return;
  }
  if (player == 0) { P1_START[0] = t.pos.x; P1_START[1] = t.pos.y; }
  else { P2_START[0] = t.pos.x; P2_START[1] = t.pos.y; }
  sendStartZones();
  setupStatus = "P" + (player + 1) + "-Start -> (" + nf(t.pos.x, 0, 0) + ", " + nf(t.pos.y, 0, 0) + ")";
}

PVector worldFromScreen(float px, float py) {
  return new PVector((px - ox) / s, (oy - py) / s);
}

void mousePressed() {
  if (appMode != MODE_SETUP) return;
  dragAnchor = -1;
  dragZone = -1;
  for (int i = 1; i >= 0; i--) {
    float[] z = (i == 0) ? P1_START : P2_START;
    PVector q = scr(z[0], z[1]);
    if (dist(mouseX, mouseY, q.x, q.y) < max(20, START_ZONE_RADIUS_MM * s)) {
      dragZone = i;
      return;
    }
  }
  for (int i = 3; i >= 0; i--) {
    PVector q = scr(AX[i], AY[i]);
    if (dist(mouseX, mouseY, q.x, q.y) < 20) {
      dragAnchor = i;
      return;
    }
  }
}

void mouseDragged() {
  if (appMode != MODE_SETUP) return;
  PVector w = worldFromScreen(mouseX, mouseY);
  if (dragAnchor >= 0) {
    AX[dragAnchor] = w.x;
    AY[dragAnchor] = w.y;
  } else if (dragZone >= 0) {
    if (dragZone == 0) { P1_START[0] = w.x; P1_START[1] = w.y; }
    else { P2_START[0] = w.x; P2_START[1] = w.y; }
  }
}

void mouseReleased() {
  if (appMode != MODE_SETUP) return;
  if (dragAnchor >= 0) {
    computeD();
    sendAnchors();
    setupStatus = "A" + dragAnchor + " verschoben – Distanzen neu berechnet";
  } else if (dragZone >= 0) {
    sendStartZones();
    setupStatus = "P" + (dragZone + 1) + "-Zone verschoben";
  }
  dragAnchor = -1;
  dragZone = -1;
}
