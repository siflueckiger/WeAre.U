// ============================ VIRTUAL PLAY MODE ============================
// Debug simulation: two players driven by keyboard, feeding positions into
// the SAME TagData pipeline the serial frames use. Modes can't tell the
// difference between UWB data and virtual players.
//
// Controls:  WASD = P1, arrow keys = P2, V = toggle active/virtual
// V switches between the real UWB stream (active) and simulated players
// (virtual). While virtual is on, serial frames are ignored and vice versa.
// Players can walk out of the anchor field -- the engine's out-of-bounds
// warning kicks in (see Core_GameMode.pde).

float VIRTUAL_SPEED_MM_S = 1500;    // walking speed

boolean virtualOn = false;
long virtualLastMs = 0;
HashSet<Character> vKeys = new HashSet<Character>();
HashSet<Integer> vCodes = new HashSet<Integer>();

boolean virtualEnabled() {
  return virtualOn;
}

void toggleVirtual() {
  virtualOn = !virtualOn;
  if (virtualOn) ensureVirtualPlayers();
  println("Virtual play: " + onOff(virtualOn) + " (WASD = P1, arrows = P2)");
}

// Fill in positions only if a player has none yet -- never snap existing
// positions back to the start zones.
void ensureVirtualPlayers() {
  virtualLastMs = 0;
  for (int i = 0; i < 2; i++) {
    int id = (i == 0) ? TAG0_ID : TAG1_ID;
    float[] start = (i == 0) ? P1_START : P2_START;
    TagData t = tags.get(id);
    if (t == null) {
      t = new TagData(id);
      tags.put(id, t);
    }
    if (t.pos == null) {
      t.pos = new PVector(start[0], start[1]);
      t.speedMs = 0;
      t.lastFixMs = millis();
      sendPos(id, t.pos.x, t.pos.y);
    }
  }
}

void updateVirtualTags() {
  if (appMode != MODE_GAME) return;
  if (!virtualOn) return;

  long now = millis();
  if (virtualLastMs == 0) virtualLastMs = now;
  float dt = (now - virtualLastMs) / 1000.0f;
  virtualLastMs = now;
  if (dt < 0) dt = 0;
  if (dt > 0.25f) dt = 0.25f;

  lastFrameMs = now;   // keep HUD "no data" warning + tag fade quiet
  moveVirtual(TAG0_ID, 'w', 's', 'a', 'd', dt);
  moveVirtual(TAG1_ID, UP, DOWN, LEFT, RIGHT, dt);
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
    // no field clamp: players may walk out of the anchor field (like real
    // players), which triggers the engine's out-of-bounds warning.
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
