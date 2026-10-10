// ============================ MODE: COIN HUNT (Mode 1) ============================
// Competitive coin collection. Hazards spawn progressively as coins are
// collected: they roam the field as bouncing squares and cost a life on touch
// (relevant to BOTH players). Powerups spawn over time and change the rules
// (never movement -- players move physically). Editing this file cannot break
// other modes or the engine.

class ModeCoinHunt extends GameMode {

  // --- coins ---
  float COLLECT_RADIUS_MM       = 300;    // pickup distance (touch-feel)
  float COIN_MARGIN_MM          = 500;    // spawn distance to field border
  float COIN_MIN_DIST_PLAYER_MM = 800;    // coin not on top of a player
  float COIN_FAIR_DIFF_MM       = 1200;   // fairness: |distP1 - distP2| <= this
  float COIN_VISUAL_MM          = 120;    // coin size (visual, sent to receiver)
  color C_COIN = color(255, 220, 40);

  // --- hazards (bouncing, neutral to both players) ---
  float ENEMY_SPEED_MM_S       = 600;    // constant travel speed
  float ENEMY_CATCH_RADIUS_MM  = 350;    // touch distance to cost a life
  float ENEMY_VISUAL_MM        = 200;    // half-size; also wall bounce margin
  float ENEMY_SPAWN_SAFE_MM    = 1200;   // spawn away from players
  int   ENEMY_SPAWN_COINS_1    = 3;      // 1st hazard after N coins (combined)
  int   ENEMY_SPAWN_COINS_2    = 6;      // 2nd hazard after N coins (combined)
  color C_ENEMY = color(255, 60, 60);

  // --- lives ---
  int   START_LIVES = 3;
  int   MAX_LIVES   = 5;
  float INVULN_S    = 2.0;                 // invulnerability after being caught

  // --- powerups ---
  float POWERUP_INTERVAL_S         = 8;    // time between powerups
  float POWERUP_LIFETIME_S         = 15;   // despawn if not collected
  float POWERUP_COLLECT_RADIUS_MM  = 400;
  float POWERUP_VISUAL_MM          = 200;
  float MAGNET_PULL_MM_S           = 700;  // coin drag speed while magnet active
  float MAGNET_S = 5, INVIS_S = 5, FREEZE_S = 4;

  static final int PU_MAGNET = 0, PU_INVIS = 1, PU_FREEZE = 2, PU_DOUBLE = 3, PU_LIFE = 4;

  int scoreP1 = 0, scoreP2 = 0;
  Entity coin = null;

  int[] lives = new int[2];
  float[] invuln = new float[2];   // remaining invulnerability seconds
  float[] magnet = new float[2];   // remaining magnet seconds
  float[] invis  = new float[2];   // remaining invisibility seconds
  float freezeAll = 0;
  boolean nextCoinDouble = false;  // next coin (by either player) counts double

  ArrayList<Enemy> enemies = new ArrayList<Enemy>();

  Entity powerup = null;
  int powerupType = PU_MAGNET;
  float powerupTimer = POWERUP_INTERVAL_S;
  float powerupLife = 0;

  ModeCoinHunt() {
    super("coinHunt", "Coin Hunt");
  }

  void onRoundEnd() {
    coin = null;
    powerup = null;
    enemies.clear();
    freezeAll = 0;
    nextCoinDouble = false;
    for (int i = 0; i < 2; i++) {
      invuln[i] = 0;
      magnet[i] = 0;
      invis[i]  = 0;
    }
  }

  void onRoundStart() {
    scoreP1 = 0;
    scoreP2 = 0;
    clearEntities();
    coin = null;
    powerup = null;
    enemies.clear();
    for (int i = 0; i < 2; i++) {
      lives[i] = START_LIVES;
      invuln[i] = 0;
      magnet[i] = 0;
      invis[i] = 0;
    }
    freezeAll = 0;
    nextCoinDouble = false;
    powerupTimer = POWERUP_INTERVAL_S;
    spawnCoin();
  }

  void update(float dt) {
    tickTimers(dt);
    updateMagnet(dt);
    updateEnemies(dt);
    updatePowerup(dt);
    if (coin != null) collectCoinCheck();
  }

  int[] scores() {
    return new int[] { scoreP1, scoreP2 };
  }

  void drawWorld() {
    if (gameState != STATE_PLAYING) return;
    drawHitboxRing(TAG0_ID, C_T0);
    drawHitboxRing(TAG1_ID, C_T1);
    drawInvulnBlink(TAG0_ID, 0);
    drawInvulnBlink(TAG1_ID, 1);
  }

  // Blink a white ring around an invulnerable player (visible hit feedback).
  void drawInvulnBlink(int id, int idx) {
    if (invuln[idx] <= 0) return;
    if ((millis() / 150) % 2 != 0) return;   // blink on/off
    TagData t = tags.get(id);
    if (t == null || t.pos == null) return;
    PVector p = scr(t.pos.x, t.pos.y);
    noFill();
    stroke(255);
    strokeWeight(3);
    ellipse(p.x, p.y, 34, 34);
  }

  String[] hudLines() {
    ArrayList<String> lines = new ArrayList<String>();
    if (freezeAll > 0) lines.add("ENEMIES FROZEN " + (int)freezeAll + "s");
    if (nextCoinDouble) lines.add("NEXT COIN x2");
    return lines.toArray(new String[0]);
  }

  int playerLives(int player) {
    return lives[player];
  }

  String[] playerEffects(int player) {
    ArrayList<String> fx = new ArrayList<String>();
    if (magnet[player] > 0) fx.add("MAGNET " + (int)ceil(magnet[player]) + "s");
    if (invis[player] > 0)  fx.add("INVIS " + (int)ceil(invis[player]) + "s");
    return fx.toArray(new String[0]);
  }

  // ============================ TIMERS ============================

  void tickTimers(float dt) {
    freezeAll = max(0, freezeAll - dt);
    for (int i = 0; i < 2; i++) {
      invuln[i] = max(0, invuln[i] - dt);
      magnet[i] = max(0, magnet[i] - dt);
      invis[i]  = max(0, invis[i] - dt);
    }
  }

  // ============================ COINS ============================

  // Magnet drags the coin slowly toward the nearest magnet-active player.
  void updateMagnet(float dt) {
    if (coin == null) return;
    int best = -1;
    float bestD = Float.MAX_VALUE;
    for (int p = 0; p < 2; p++) {
      if (magnet[p] <= 0) continue;
      TagData t = tags.get(p == 0 ? TAG0_ID : TAG1_ID);
      if (t == null || t.pos == null) continue;
      float d = dist(t.pos.x, t.pos.y, coin.x, coin.y);
      if (d < bestD) { bestD = d; best = p; }
    }
    if (best < 0) return;
    TagData t = tags.get(best == 0 ? TAG0_ID : TAG1_ID);
    float dx = t.pos.x - coin.x;
    float dy = t.pos.y - coin.y;
    float d = sqrt(dx * dx + dy * dy);
    if (d < 1) return;
    float step = MAGNET_PULL_MM_S * dt;
    if (step > d) step = d;   // don't overshoot
    coin.x += dx / d * step;
    coin.y += dy / d * step;
  }

  void collectCoinCheck() {
    for (int p = 0; p < 2; p++) {
      TagData t = tags.get(p == 0 ? TAG0_ID : TAG1_ID);
      if (t == null || t.pos == null) continue;
      if (dist(t.pos.x, t.pos.y, coin.x, coin.y) < COLLECT_RADIUS_MM) {
        collectCoin(p);
        break;
      }
    }
  }

  void collectCoin(int player) {
    int gain = nextCoinDouble ? 2 : 1;
    nextCoinDouble = false;
    if (player == 0) scoreP1 += gain;
    else scoreP2 += gain;
    println("P" + (player + 1) + " collected coin (+" + gain + ") -> P1:" + scoreP1 + " P2:" + scoreP2);
    // Magnet is consumed by the player who actually captures the coin; if the
    // other player steals it, the holder's magnet keeps running for the next coin.
    if (magnet[player] > 0) {
      magnet[player] = 0;
      println("P" + (player + 1) + " magnet consumed on coin capture");
    }
    if (coin != null) removeEntity(coin.id);
    coin = null;
    maybeSpawnEnemies();
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
      if (min(d0, d1) < COIN_MIN_DIST_PLAYER_MM) continue;
      if (t0 != null && t1 != null && t0.pos != null && t1.pos != null
          && abs(d0 - d1) > COIN_FAIR_DIFF_MM) continue;
      coin = spawnEntity("coin", x, y, COIN_VISUAL_MM, C_COIN);
      return;
    }
    coin = spawnEntity("coin", random(b[0] + COIN_MARGIN_MM, b[1] - COIN_MARGIN_MM),
                       random(b[2] + COIN_MARGIN_MM, b[3] - COIN_MARGIN_MM), COIN_VISUAL_MM, C_COIN);
  }

  // ============================ HAZARDS ============================

  // Progressive difficulty: one hazard after ENEMY_SPAWN_COINS_1 coins, a
  // second after ENEMY_SPAWN_COINS_2 (counted over both players combined).
  void maybeSpawnEnemies() {
    int total = scoreP1 + scoreP2;
    if (enemies.size() == 0 && total >= ENEMY_SPAWN_COINS_1) {
      spawnEnemy();
    } else if (enemies.size() == 1 && total >= ENEMY_SPAWN_COINS_2) {
      spawnEnemy();
    }
  }

  // Spawn a hazard at a random safe point, moving diagonally at constant speed.
  // The angle avoids near-axis travel so it always sweeps the whole field.
  void spawnEnemy() {
    float[] pos = randomFarPoint(ENEMY_SPAWN_SAFE_MM);
    float speed = ENEMY_SPEED_MM_S;
    float ang = radians(random(25, 65)) + int(random(4)) * HALF_PI;
    float vx = cos(ang) * speed;
    float vy = sin(ang) * speed;
    Entity e = spawnEntity("enemy", pos[0], pos[1], ENEMY_VISUAL_MM, C_ENEMY);
    enemies.add(new Enemy(e, vx, vy));
    println("Hazard spawned (" + enemies.size() + ")");
  }

  // Move every hazard and bounce it off the field walls; a hazard is neutral and
  // threatens BOTH players. Frozen hazards stand still but are still solid.
  void updateEnemies(float dt) {
    float[] b = fieldBounds();
    float m = ENEMY_VISUAL_MM;
    for (Enemy en : enemies) {
      if (freezeAll <= 0) {
        en.ent.x += en.vx * dt;
        en.ent.y += en.vy * dt;
        if (en.ent.x < b[0] + m) { en.ent.x = b[0] + m; en.vx = abs(en.vx); }
        if (en.ent.x > b[1] - m) { en.ent.x = b[1] - m; en.vx = -abs(en.vx); }
        if (en.ent.y < b[2] + m) { en.ent.y = b[2] + m; en.vy = abs(en.vy); }
        if (en.ent.y > b[3] - m) { en.ent.y = b[3] - m; en.vy = -abs(en.vy); }
      }
      for (int p = 0; p < 2; p++) {
        if (invis[p] > 0 || invuln[p] > 0) continue;   // phased-out or just hit
        TagData td = tags.get(p == 0 ? TAG0_ID : TAG1_ID);
        if (td == null || td.pos == null) continue;
        if (dist(en.ent.x, en.ent.y, td.pos.x, td.pos.y) < ENEMY_CATCH_RADIUS_MM) {
          catchPlayer(p, en);
        }
      }
    }
  }

  // A hazard touched a player: costs a life, then bounces off and keeps going.
  void catchPlayer(int player, Enemy en) {
    lives[player]--;
    invuln[player] = INVULN_S;
    println("P" + (player + 1) + " hit by hazard! lives=" + lives[player]);
    sendHit(player, INVULN_S);   // flash + blink on the receiver
    en.vx = -en.vx;              // deflect instead of teleporting
    en.vy = -en.vy;
    if (lives[player] <= 0) {
      roundWinner = (player == 0) ? 2 : 1;
      requestEnd();
    }
  }

  // ============================ POWERUPS ============================

  void updatePowerup(float dt) {
    if (powerup != null) {
      powerupLife -= dt;
      if (powerupLife <= 0) {
        removeEntity(powerup.id);
        powerup = null;
        powerupTimer = POWERUP_INTERVAL_S;
        return;
      }
      for (int p = 0; p < 2; p++) {
        TagData t = tags.get(p == 0 ? TAG0_ID : TAG1_ID);
        if (t != null && t.pos != null
            && dist(t.pos.x, t.pos.y, powerup.x, powerup.y) < POWERUP_COLLECT_RADIUS_MM) {
          applyPowerup(powerupType, p);
          removeEntity(powerup.id);
          powerup = null;
          powerupTimer = POWERUP_INTERVAL_S;
          return;
        }
      }
    } else {
      powerupTimer -= dt;
      if (powerupTimer <= 0) spawnPowerup();
    }
  }

  void spawnPowerup() {
    powerupType = (int)random(5);
    float[] pos = randomFarPoint(COIN_MIN_DIST_PLAYER_MM);
    powerup = spawnEntity("powerup", pos[0], pos[1], POWERUP_VISUAL_MM, powerupColor(powerupType));
    powerup.label = powerupLabel(powerupType);
    powerupLife = POWERUP_LIFETIME_S;
    println("Powerup spawned: " + powerupName(powerupType));
  }

  color powerupColor(int type) {
    if (type == PU_MAGNET) return color(120, 220, 255);
    if (type == PU_INVIS)  return color(180, 140, 255);
    if (type == PU_FREEZE) return color(120, 255, 200);
    if (type == PU_DOUBLE) return color(255, 200, 120);
    return color(255, 120, 200);   // life
  }

  String powerupLabel(int type) {
    if (type == PU_MAGNET) return "MAG";
    if (type == PU_INVIS)  return "INV";
    if (type == PU_FREEZE) return "FRE";
    if (type == PU_DOUBLE) return "DOU";
    return "LIF";
  }

  String powerupName(int type) {
    if (type == PU_MAGNET) return "MAGNET";
    if (type == PU_INVIS)  return "INVIS";
    if (type == PU_FREEZE) return "FREEZE";
    if (type == PU_DOUBLE) return "DOUBLE";
    return "LIFE";
  }

  void applyPowerup(int type, int player) {
    if (type == PU_MAGNET) magnet[player] = MAGNET_S;
    else if (type == PU_INVIS) invis[player] = INVIS_S;
    else if (type == PU_FREEZE) freezeAll = FREEZE_S;
    else if (type == PU_DOUBLE) nextCoinDouble = true;
    else if (type == PU_LIFE) lives[player] = min(lives[player] + 1, MAX_LIVES);
    println("P" + (player + 1) + " got " + powerupName(type));
  }

  // ============================ HELPERS ============================

  // Random point inside the field, at least minDist away from both players.
  float[] randomFarPoint(float minDist) {
    float[] b = fieldBounds();
    TagData t0 = tags.get(TAG0_ID);
    TagData t1 = tags.get(TAG1_ID);
    for (int i = 0; i < 100; i++) {
      float x = random(b[0] + COIN_MARGIN_MM, b[1] - COIN_MARGIN_MM);
      float y = random(b[2] + COIN_MARGIN_MM, b[3] - COIN_MARGIN_MM);
      float d0 = (t0 != null && t0.pos != null) ? dist(x, y, t0.pos.x, t0.pos.y) : Float.MAX_VALUE;
      float d1 = (t1 != null && t1.pos != null) ? dist(x, y, t1.pos.x, t1.pos.y) : Float.MAX_VALUE;
      if (min(d0, d1) < minDist) continue;
      return new float[] { x, y };
    }
    return new float[] { random(b[0] + COIN_MARGIN_MM, b[1] - COIN_MARGIN_MM),
                         random(b[2] + COIN_MARGIN_MM, b[3] - COIN_MARGIN_MM) };
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
}

class Enemy {
  Entity ent;
  float vx, vy;   // velocity in mm/s

  Enemy(Entity e, float vx, float vy) {
    ent = e;
    this.vx = vx;
    this.vy = vy;
  }
}
