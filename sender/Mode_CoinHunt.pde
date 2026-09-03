// ============================ MODE: COIN HUNT (Mode 1) ============================
// Competitive coin collection. After a combined coin threshold two enemies spawn
// (one per player, chasing their target). Players have lives; enemies cost lives.
// Powerups spawn over time and change the rules (never movement -- players move
// physically). Editing this file cannot break other modes or the engine.

class ModeCoinHunt extends GameMode {

  // --- coins ---
  float COLLECT_RADIUS_MM       = 300;    // pickup distance (touch-feel)
  float COIN_MARGIN_MM          = 500;    // spawn distance to field border
  float COIN_MIN_DIST_PLAYER_MM = 800;    // coin not on top of a player
  float COIN_FAIR_DIFF_MM       = 1200;   // fairness: |distP1 - distP2| <= this
  float COIN_VISUAL_MM          = 120;    // coin size (visual, sent to receiver)
  color C_COIN = color(255, 220, 40);

  // --- enemies ---
  int   ENEMY_AFTER_COINS        = 5;      // combined coins before enemies spawn
  float ENEMY_SPEED_MM_S         = 700;    // chase speed
  float ENEMY_CATCH_RADIUS_MM    = 350;    // touch distance to catch a player
  float ENEMY_MIN_DIST_PLAYER_MM = 1200;   // spawn/respawn away from players
  float ENEMY_VISUAL_MM          = 200;
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
  float MAGNET_RADIUS_MM           = 1500; // collect radius while magnet active
  float MAGNET_S = 5, INVIS_S = 5, FREEZE_S = 4, DOUBLE_S = 5;

  static final int PU_MAGNET = 0, PU_INVIS = 1, PU_FREEZE = 2, PU_DOUBLE = 3, PU_LIFE = 4;

  int scoreP1 = 0, scoreP2 = 0;
  Entity coin = null;

  int[] lives = new int[2];
  float[] invuln = new float[2];   // remaining invulnerability seconds
  float[] magnet = new float[2];   // remaining magnet seconds
  float[] invis  = new float[2];   // remaining invisibility seconds
  float[] doubleT = new float[2];  // remaining double-coin seconds
  float freezeAll = 0;

  ArrayList<Enemy> enemies = new ArrayList<Enemy>();
  boolean enemiesSpawned = false;

  Entity powerup = null;
  int powerupType = PU_MAGNET;
  float powerupTimer = POWERUP_INTERVAL_S;
  float powerupLife = 0;

  ModeCoinHunt() {
    super("coinHunt", "Coin Hunt");
  }

  void onRoundStart() {
    scoreP1 = 0;
    scoreP2 = 0;
    clearEntities();
    coin = null;
    powerup = null;
    enemies.clear();
    enemiesSpawned = false;
    for (int i = 0; i < 2; i++) {
      lives[i] = START_LIVES;
      invuln[i] = 0;
      magnet[i] = 0;
      invis[i] = 0;
      doubleT[i] = 0;
    }
    freezeAll = 0;
    powerupTimer = POWERUP_INTERVAL_S;
    spawnCoin();
  }

  void update(float dt) {
    tickTimers(dt);
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
    lines.add("P1 lives " + lives[0] + "    P2 lives " + lives[1]);
    if (freezeAll > 0) lines.add("ENEMIES FROZEN " + (int)freezeAll + "s");
    for (int p = 0; p < 2; p++) {
      String fx = "";
      if (magnet[p] > 0) fx += "MAGNET ";
      if (invis[p] > 0) fx += "INVIS ";
      if (doubleT[p] > 0) fx += "DOUBLE ";
      if (!fx.isEmpty()) lines.add("P" + (p + 1) + ": " + fx.trim());
    }
    return lines.toArray(new String[0]);
  }

  // ============================ TIMERS ============================

  void tickTimers(float dt) {
    freezeAll = max(0, freezeAll - dt);
    for (int i = 0; i < 2; i++) {
      invuln[i] = max(0, invuln[i] - dt);
      magnet[i] = max(0, magnet[i] - dt);
      invis[i]  = max(0, invis[i] - dt);
      doubleT[i] = max(0, doubleT[i] - dt);
    }
  }

  // ============================ COINS ============================

  void collectCoinCheck() {
    for (int p = 0; p < 2; p++) {
      TagData t = tags.get(p == 0 ? TAG0_ID : TAG1_ID);
      if (t == null || t.pos == null) continue;
      float radius = (magnet[p] > 0) ? MAGNET_RADIUS_MM : COLLECT_RADIUS_MM;
      if (dist(t.pos.x, t.pos.y, coin.x, coin.y) < radius) {
        collectCoin(p);
        break;
      }
    }
  }

  void collectCoin(int player) {
    int gain = (doubleT[player] > 0) ? 2 : 1;
    if (player == 0) scoreP1 += gain;
    else scoreP2 += gain;
    println("P" + (player + 1) + " collected coin (+" + gain + ") -> P1:" + scoreP1 + " P2:" + scoreP2);
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

  // ============================ ENEMIES ============================

  void maybeSpawnEnemies() {
    if (!enemiesSpawned && (scoreP1 + scoreP2) >= ENEMY_AFTER_COINS) {
      enemiesSpawned = true;
      spawnEnemy(0);   // enemy 1 targets P1
      spawnEnemy(1);   // enemy 2 targets P2
      println("Enemies spawned: one per player");
    }
  }

  void spawnEnemy(int target) {
    float[] pos = randomFarPoint(ENEMY_MIN_DIST_PLAYER_MM);
    Entity e = spawnEntity("enemy", pos[0], pos[1], ENEMY_VISUAL_MM, C_ENEMY);
    enemies.add(new Enemy(e, target));
  }

  void updateEnemies(float dt) {
    for (Enemy en : enemies) {
      int t = targetFor(en);
      TagData td = tags.get(t == 0 ? TAG0_ID : TAG1_ID);
      if (freezeAll <= 0 && td != null && td.pos != null) {
        float dx = td.pos.x - en.ent.x;
        float dy = td.pos.y - en.ent.y;
        float d = sqrt(dx * dx + dy * dy);
        if (d > 1) {
          float step = ENEMY_SPEED_MM_S * dt;
          en.ent.x += dx / d * step;
          en.ent.y += dy / d * step;
        }
      }
      if (td != null && td.pos != null && invuln[t] <= 0
          && dist(en.ent.x, en.ent.y, td.pos.x, td.pos.y) < ENEMY_CATCH_RADIUS_MM) {
        catchPlayer(t, en);
      }
    }
  }

  // A player's enemy chases them; if the target is invisible, chase the other.
  int targetFor(Enemy en) {
    int t = en.target;
    if (invis[t] > 0) t = 1 - t;
    return t;
  }

  void catchPlayer(int player, Enemy en) {
    lives[player]--;
    invuln[player] = INVULN_S;
    println("P" + (player + 1) + " caught! lives=" + lives[player]);
    sendHit(player, INVULN_S);   // flash + blink on the receiver
    float[] pos = randomFarPoint(ENEMY_MIN_DIST_PLAYER_MM);
    en.ent.x = pos[0];
    en.ent.y = pos[1];
    en.ent.needsUpsert = true;
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
    else if (type == PU_DOUBLE) doubleT[player] = DOUBLE_S;
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
  int target;   // 0 = P1, 1 = P2

  Enemy(Entity e, int t) {
    ent = e;
    target = t;
  }
}
