// ============================ OSC OUT ============================
// All OSC traffic to the Raspberry Pi receivers goes through here.
// Protocol (v1): see docs/osc-protocol.md

void sendPos(int tagid, float x, float y) {
  if (!OSC_ENABLED || osc == null || piAddr == null) return;
  OscMessage m = new OscMessage(tagid == TAG0_ID ? "/p1/pos" : "/p2/pos");
  m.add(x);
  m.add(y);
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
  currentMode.sendOscEntities();
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
