// ============================ VIRTUAL PLAY MODE ============================
// Debug simulation: two players driven by keyboard, feeding positions into
// the SAME TagData pipeline the serial frames use. Modes can't tell the
// difference between UWB data and virtual players.
//
// Controls:  WASD = P1, arrow keys = P2, V = toggle
// Auto-engage: if no serial port is found within VIRTUAL_AUTO_AFTER_MS after
// startup, virtual mode switches on by itself. It disengages again as soon
// as a serial port connects.

boolean VIRTUAL_AUTO         = true;
int     VIRTUAL_AUTO_AFTER_MS = 5000;
float   VIRTUAL_SPEED_MM_S    = 1500;    // walking speed
int     VIRTUAL_EDGE_MARGIN_MM = 200;    // keep players inside the field

boolean virtualOn = false;
boolean virtualAutoEngaged = false;
boolean oobSim = false;       // debug: hold P1 outside the field (O key) to test the warning
long virtualLastMs = 0;
HashSet<Character> vKeys = new HashSet<Character>();
HashSet<Integer> vCodes = new HashSet<Integer>();

boolean virtualEnabled() {
  return virtualOn;
}

void toggleVirtual() {
  virtualOn = !virtualOn;
  virtualAutoEngaged = false;   // manual toggle overrides the auto decision
  if (virtualOn) resetVirtualPlayers();
  println("Virtual play: " + onOff(virtualOn) + " (WASD = P1, arrows = P2)");
}

void resetVirtualPlayers() {
  virtualLastMs = 0;
  for (int i = 0; i < 2; i++) {
    int id = (i == 0) ? TAG0_ID : TAG1_ID;
    float[] start = (i == 0) ? P1_START : P2_START;
    TagData t = tags.get(id);
    if (t == null) {
      t = new TagData(id);
      tags.put(id, t);
    }
    t.pos = new PVector(start[0], start[1]);
    t.speedMs = 0;
    t.trail.clear();
    t.lastFixMs = millis();
    sendPos(id, t.pos.x, t.pos.y);
  }
}

void updateVirtualTags() {
  if (appMode != MODE_GAME) return;

  if (!virtualOn) {
    if (VIRTUAL_AUTO && !virtualAutoEngaged && port == null
        && millis() - appStartMs > VIRTUAL_AUTO_AFTER_MS) {
      virtualOn = true;
      virtualAutoEngaged = true;
      resetVirtualPlayers();
      println("Virtual play auto-engaged (no serial port found)");
    }
    return;
  }

  long now = millis();
  if (virtualLastMs == 0) virtualLastMs = now;
  float dt = (now - virtualLastMs) / 1000.0f;
  virtualLastMs = now;
  if (dt < 0) dt = 0;
  if (dt > 0.25f) dt = 0.25f;

  lastFrameMs = now;   // keep HUD "no data" warning + tag fade quiet
  if (oobSim) {
    forceOob(TAG0_ID);
    moveVirtual(TAG1_ID, UP, DOWN, LEFT, RIGHT, dt);
  } else {
    moveVirtual(TAG0_ID, 'w', 's', 'a', 'd', dt);
    moveVirtual(TAG1_ID, UP, DOWN, LEFT, RIGHT, dt);
  }
}

// Debug: park P1 just outside the field so the out-of-bounds warning + countdown
// can be tested without hardware. Bypasses the field clamp.
void forceOob(int id) {
  TagData t = tags.get(id);
  if (t == null || t.pos == null) return;
  float[] b = fieldBounds();
  t.pos.x = b[0] - OOB_MARGIN_MM - 600;
  t.pos.y = (b[2] + b[3]) / 2;
  t.speedMs = 0;
  t.trail.add(t.pos.copy());
  if (t.trail.size() > TRAIL_MAX) t.trail.remove(0);
  t.lastFixMs = millis();
  sendPos(id, t.pos.x, t.pos.y);
}

void moveVirtual(int id, int upK, int downK, int leftK, int rightK, float dt) {
  PVector dir = new PVector(0, 0);
  if (hasKey(upK)) dir.y += 1;
  if (hasKey(downK)) dir.y -= 1;
  if (hasKey(leftK)) dir.x -= 1;
  if (hasKey(rightK)) dir.x += 1;

  TagData t = tags.get(id);
  if (t == null || t.pos == null) return;

  float speed = 0;
  if (dir.mag() > 0) {
    dir.normalize();
    speed = VIRTUAL_SPEED_MM_S;
    t.pos.x += dir.x * speed * dt;
    t.pos.y += dir.y * speed * dt;
    float[] b = fieldBounds();
    t.pos.x = constrain(t.pos.x, b[0] + VIRTUAL_EDGE_MARGIN_MM, b[1] - VIRTUAL_EDGE_MARGIN_MM);
    t.pos.y = constrain(t.pos.y, b[2] + VIRTUAL_EDGE_MARGIN_MM, b[3] - VIRTUAL_EDGE_MARGIN_MM);
  }
  t.speedMs = speed;
  t.trail.add(t.pos.copy());
  if (t.trail.size() > TRAIL_MAX) t.trail.remove(0);
  t.lastFixMs = millis();
  sendPos(id, t.pos.x, t.pos.y);
}

boolean hasKey(int k) {
  if (k == UP || k == DOWN || k == LEFT || k == RIGHT) return vCodes.contains(k);
  return vKeys.contains((char)k);
}

// Returns true if the key was consumed as a movement key.
boolean vKeyDown() {
  if (key == CODED) {
    if (keyCode == UP || keyCode == DOWN || keyCode == LEFT || keyCode == RIGHT) {
      vCodes.add(keyCode);
      return true;
    }
    return false;
  }
  if (key == 'w' || key == 'W' || key == 'a' || key == 'A'
      || key == 's' || key == 'S' || key == 'd' || key == 'D') {
    vKeys.add(key);
    return true;
  }
  return false;
}

void vKeyUp() {
  if (key == CODED) {
    vCodes.remove(keyCode);
    return;
  }
  vKeys.remove(key);
}
