// ============================ OSC OUT ============================
// All OSC traffic to the Raspberry Pi receivers goes through here.
// Protocol (v2): see docs/osc-protocol.md

void sendPos(int tagid, float x, float y) {
  if (!OSC_ENABLED || osc == null || piAddr == null) return;
  OscMessage m = new OscMessage(tagid == TAG0_ID ? "/p1/pos" : "/p2/pos");
  m.add(x);
  m.add(y);
  osc.send(m, piAddr);
  oscSent++;
}

void sendModeOsc() {
  if (!OSC_ENABLED || osc == null || piAddr == null) return;
  OscMessage m = new OscMessage("/game/mode");
  m.add(currentMode.id);
  m.add(currentMode.displayName);
  osc.send(m, piAddr);
  oscSent++;
}

void sendGameOsc() {
  if (!OSC_ENABLED || osc == null || piAddr == null) return;
  if (millis() - lastGameOscMs < OSC_GAME_INTERVAL_MS) return;
  lastGameOscMs = millis();
  int[] sc = currentMode.scores();
  int tl = (gameState == STATE_READY) ? (int)ceil(timeLeft) : (int)floor(timeLeft);
  OscMessage stats = new OscMessage("/game/stats");
  stats.add(gameState);
  stats.add(tl);
  stats.add(sc[0]);
  stats.add(sc[1]);
  stats.add(roundWinner);   // -1 = derive winner from scores (receiver-side)
  osc.send(stats, piAddr);

  for (int i = 0; i < 2; i++) {
    OscMessage o = new OscMessage("/game/oob");
    o.add(i);                                // player index: 0 = P1, 1 = P2
    o.add((int)ceil(oobCountdown[i]));       // seconds left
    o.add(oobActive[i] ? 1 : 0);             // 1 = warning active
    osc.send(o, piAddr);
  }

  if (gameState == STATE_GAMEOVER) sendResultOsc();
  if (gameState == STATE_PLAYING) sendHudOsc();
  sendEntitiesOsc();
}

void sendResultOsc() {
  String[] rt = currentMode.resultText();
  String title = (rt != null && rt.length > 0) ? rt[0] : "GAME OVER";
  String subtitle = (rt != null && rt.length > 1) ? rt[1] : defaultSubtitle();
  OscMessage m = new OscMessage("/game/result");
  m.add(title);
  m.add(subtitle);
  osc.send(m, piAddr);
}

String defaultSubtitle() {
  if (roundWinner == 1) return "SPIELER 1 GEWINNT!";
  if (roundWinner == 2) return "SPIELER 2 GEWINNT!";
  return "UNENTSCHIEDEN!";
}

void sendHudOsc() {
  String[] lines = currentMode.hudLines();
  if (lines == null || lines.length == 0) return;
  OscMessage m = new OscMessage("/hud");
  for (String l : lines) m.add(l);
  osc.send(m, piAddr);
}

// Generic entity sync: upsert on spawn, pos every tick, remove on despawn.
void sendEntitiesOsc() {
  for (Integer id : removedEntityIds) {
    OscMessage r = new OscMessage("/ent/remove");
    r.add(id);
    osc.send(r, piAddr);
  }
  removedEntityIds.clear();

  for (Entity e : entities.values()) {
    if (!e.visible) continue;
    if (e.needsUpsert) {
      OscMessage u = new OscMessage("/ent/upsert");
      u.add(e.id);
      u.add(e.type);
      u.add(e.x);
      u.add(e.y);
      u.add(e.radius);
      u.add(red(e.c));
      u.add(green(e.c));
      u.add(blue(e.c));
      osc.send(u, piAddr);
      e.needsUpsert = false;
    }
    OscMessage p = new OscMessage("/ent/pos");
    p.add(e.id);
    p.add(e.x);
    p.add(e.y);
    osc.send(p, piAddr);
  }
}

void sendStartZones() {
  if (!OSC_ENABLED || osc == null || piAddr == null) return;
  OscMessage m1 = new OscMessage("/start/p1");
  m1.add(P1_START[0]);
  m1.add(P1_START[1]);
  osc.send(m1, piAddr);
  OscMessage m2 = new OscMessage("/start/p2");
  m2.add(P2_START[0]);
  m2.add(P2_START[1]);
  osc.send(m2, piAddr);
  oscSent += 2;
}

void sendAnchors() {
  if (!OSC_ENABLED || osc == null || piAddr == null) return;
  OscMessage m = new OscMessage("/anchors");
  for (int i = 0; i < 4; i++) m.add(AX[i]);
  for (int i = 0; i < 4; i++) m.add(AY[i]);
  osc.send(m, piAddr);
  oscSent++;
}
