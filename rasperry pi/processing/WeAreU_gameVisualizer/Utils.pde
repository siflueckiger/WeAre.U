// ============================================================
// Utils.pde  –  Tab für globale Hilfsfunktionen & Konstanten
// ============================================================

// --- State-Konstanten ---
final int STATE_MENU     = 0;
final int STATE_PLAYING  = 1;
final int STATE_GAMEOVER = 2;
// Neue States einfach hier hinzufügen:
// final int STATE_PAUSE = 3;


// --- Koordinaten-Mapping ---
// Rechnet Spielfeld-Koordinaten (0–GAME_SIZE) in Viewport-Koordinaten um.
// GAME_SIZE kommt aus Main.pde und ist dort als global deklariert.

float gx(float x, PGraphics pg) {
  return map(x, 0, GAME_SIZE, 0, pg.width);
}

float gy(float y, PGraphics pg) {
  return map(y, 0, GAME_SIZE, 0, pg.height);
}
