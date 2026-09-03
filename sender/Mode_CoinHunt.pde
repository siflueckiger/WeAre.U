// ============================ MODE: COIN HUNT ============================
// Competitive coin collection. Spawn rules and scoring live here and only
// here -- editing other modes or the engine cannot break this mode.

class ModeCoinHunt extends GameMode {

  float COLLECT_RADIUS_MM       = 300;   // distance to pick up the coin (touch-feel)
  float COIN_MARGIN_MM          = 500;   // coin spawn: distance to field border
  float COIN_MIN_DIST_PLAYER_MM = 800;   // coin must not spawn on top of a player
  float COIN_FAIR_DIFF_MM       = 1200;  // fairness: |distP1 - distP2| <= this

  color C_COIN = color(255, 220, 40);
  int COIN_SIZE_PX = 14;

  int scoreP1 = 0, scoreP2 = 0;
  float[] coinPos = null;

  ModeCoinHunt() {
    super("coinHunt", "Coin Hunt");
  }

  void onRoundStart() {
    scoreP1 = 0;
    scoreP2 = 0;
    spawnCoin();
  }

  void update(float dt) {
    if (coinPos == null) return;
    TagData t0 = tags.get(TAG0_ID);
    TagData t1 = tags.get(TAG1_ID);
    if (t0 != null && t0.pos != null && dist(t0.pos.x, t0.pos.y, coinPos[0], coinPos[1]) < COLLECT_RADIUS_MM) {
      collectCoin(1);
    } else if (t1 != null && t1.pos != null && dist(t1.pos.x, t1.pos.y, coinPos[0], coinPos[1]) < COLLECT_RADIUS_MM) {
      collectCoin(2);
    }
  }

  int[] scores() {
    return new int[] { scoreP1, scoreP2 };
  }

  void sendOscEntities() {
    if (gameState == STATE_PLAYING && coinPos != null) {
      OscMessage c = new OscMessage("/coin/pos");
      c.add(coinPos[0]);
      c.add(coinPos[1]);
      osc.send(c, piAddr);
    }
  }

  void drawWorld() {
    if (gameState != STATE_PLAYING) return;

    // hitbox debug ring: shows the actual collect radius around each player
    drawHitboxRing(TAG0_ID, C_T0);
    drawHitboxRing(TAG1_ID, C_T1);

    if (coinPos == null) return;
    PVector p = scr(coinPos[0], coinPos[1]);
    fill(C_COIN);
    stroke(255);
    strokeWeight(2);
    ellipse(p.x, p.y, COIN_SIZE_PX, COIN_SIZE_PX);
    fill(0);
    textAlign(CENTER, CENTER);
    text("$", p.x, p.y + 1);
  }

  void drawHitboxRing(int id, color c) {
    TagData t = tags.get(id);
    if (t == null || t.pos == null) return;
    PVector q = scr(t.pos.x, t.pos.y);
    float r = COLLECT_RADIUS_MM * s;
    noFill();
    stroke(c, 90);
    strokeWeight(1);
    ellipse(q.x, q.y, 2 * r, 2 * r);
  }

  void collectCoin(int player) {
    if (player == 1) scoreP1++;
    else scoreP2++;
    println("P" + player + " collected coin -> P1:" + scoreP1 + " P2:" + scoreP2);
    spawnCoin();
  }

  // Spawn rule: inside the field bounds (any venue size), away from players,
  // fair for both players. Falls back to a random point in the margin box.
  void spawnCoin() {
    float[] b = fieldBounds();
    TagData t0 = tags.get(TAG0_ID);
    TagData t1 = tags.get(TAG1_ID);
    for (int i = 0; i < 100; i++) {
      float x = random(b[0] + COIN_MARGIN_MM, b[1] - COIN_MARGIN_MM);
      float y = random(b[2] + COIN_MARGIN_MM, b[3] - COIN_MARGIN_MM);
      float d0 = (t0 != null && t0.pos != null) ? dist(x, y, t0.pos.x, t0.pos.y) : Float.MAX_VALUE;
      float d1 = (t1 != null && t1.pos != null) ? dist(x, y, t1.pos.x, t1.pos.y) : Float.MAX_VALUE;
      if (min(d0, d1) < COIN_MIN_DIST_PLAYER_MM) continue;              // too close to a player
      if (t0 != null && t1 != null && t0.pos != null && t1.pos != null
          && abs(d0 - d1) > COIN_FAIR_DIFF_MM) continue;                 // unfair for one player
      coinPos = new float[] { x, y };
      return;
    }
    // fallback (e.g. no player fix yet): random inside margin box
    coinPos = new float[] { random(b[0] + COIN_MARGIN_MM, b[1] - COIN_MARGIN_MM),
                            random(b[2] + COIN_MARGIN_MM, b[3] - COIN_MARGIN_MM) };
  }
}
