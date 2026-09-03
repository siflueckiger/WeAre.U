// ============================ GAME MODE FRAMEWORK ============================
// Every game mode lives in its own Mode_*.pde file and only talks to the
// engine through this interface. The engine owns the shared state machine
// (WAIT -> READY -> PLAYING -> GAMEOVER), start zones, countdown and the
// round timer. Modes implement the round content only.

abstract class GameMode {
  String id;
  String displayName;

  GameMode(String id, String displayName) {
    this.id = id;
    this.displayName = displayName;
  }

  void onModeEnter() {}                 // mode selected (engine setup / switch)
  abstract void onRoundStart();         // engine calls when PLAYING begins
  abstract void update(float dt);       // per-frame during PLAYING, dt in seconds
  abstract int[] scores();              // { p1, p2 } for /game/stats + HUD
  abstract void drawWorld();            // sender debug rendering (top view)
  abstract void sendOscEntities();      // mode-specific OSC entity sync
  void keyPressed(char k) {}            // mode-specific keys (default: none)
}

// Mode registry. Phase 3 adds M-key switching + config.json persistence;
// new modes only need to be appended here.
GameMode[] modes = { new ModeCoinHunt() };
GameMode currentMode = modes[0];

// ============================ ENGINE STATE MACHINE ============================

void setState(int s) {
  gameState = s;
  stateEnteredMs = millis();
  lastTickMs = millis();
  lastGameOscMs = 0;   // force immediate /game/stats send
  println("game state -> " + stateName(s));
}

String stateName(int s) {
  if (s == STATE_WAIT) return "WAIT";
  if (s == STATE_PLAYING) return "PLAYING";
  if (s == STATE_GAMEOVER) return "GAMEOVER";
  if (s == STATE_READY) return "READY";
  return "?";
}

void updateGame() {
  TagData t0 = tags.get(TAG0_ID);
  TagData t1 = tags.get(TAG1_ID);

  if (gameState == STATE_WAIT) {
    timeLeft = 0;
    if (inZone(t0, P1_START) && inZone(t1, P2_START)) setState(STATE_READY);
  } else if (gameState == STATE_READY) {
    timeLeft = max(0, READY_S - (millis() - stateEnteredMs) / 1000.0f);
    if (!inZone(t0, P1_START) || !inZone(t1, P2_START)) {
      setState(STATE_WAIT);   // a player left the zone -> abort countdown
    } else if (timeLeft <= 0) {
      currentMode.onRoundStart();
      setState(STATE_PLAYING);
    }
  } else if (gameState == STATE_PLAYING) {
    timeLeft = max(0, GAME_TIME_S - (millis() - stateEnteredMs) / 1000.0f);
    float dt = (millis() - lastTickMs) / 1000.0f;
    lastTickMs = millis();
    if (dt < 0) dt = 0;
    if (dt > 0.25f) dt = 0.25f;   // clamp huge gaps (tab switch, load hitches)
    currentMode.update(dt);
    if (timeLeft <= 0) setState(STATE_GAMEOVER);
  } else if (gameState == STATE_GAMEOVER) {
    if (millis() - stateEnteredMs > GAMEOVER_S * 1000) setState(STATE_WAIT);
  }
}

// Modes call this to end the round early (e.g. a player ran out of lives).
void requestEnd() {
  if (gameState == STATE_PLAYING) setState(STATE_GAMEOVER);
}

// Debug helper (SPACE): start the round immediately, skipping the start-zone check.
void debugStartRound() {
  currentMode.onRoundStart();
  setState(STATE_PLAYING);
  println("SPACE: manual round start (debug)");
}
