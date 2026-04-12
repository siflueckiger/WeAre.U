// ============================================================
// Config.pde  –  Alle anpassbaren Spielparameter
// Hier ändern, nie tief im Code suchen müssen.
// ============================================================

// --- Fenster & Viewport ---
final int   WINDOW_W     = 800;
final int   WINDOW_H     = 480;
final int   VIEWPORT_W   = 400;
final int   VIEWPORT_H   = 480;

// --- Netzwerk ---
final int   OSC_PORT     = 12001;

// --- Spielfeld ---
// GAME_SIZE bleibt in [MAIN].pde, da Global sein muss und gx()/gy() in Utils.pde davon abhängen

// --- Objektgrössen (auf Senderseite, werden automatisch skaliert) ---
final float PLAYER_SIZE  = 60.0;
final float COIN_SIZE    = 40.0;
final float POWERUP_SIZE = 35.0;

// --- Farben ---
final color COL_P1       = #3296FF;  // Blau
final color COL_P2       = #FF3232;  // Rot
final color COL_COIN     = #FFFF00;  // Gelb
final color COL_POWERUP  = #00FF64;  // Grün
final color COL_OBSTACLE = #969696;  // Grau
final color COL_BG       = #141414;  // Hintergrund
