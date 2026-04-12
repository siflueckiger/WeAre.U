// ============================================================
// Player.pde  –  Tab für die Spieler-Klasse
// ============================================================

class Player {
  String id;
  color col;
  float x, y;
  int score;

  Player(String id, color col) {
    this.id  = id;
    this.col = col;
  }

  void draw(PGraphics pg, float size) {
    pg.fill(col);
    pg.ellipse(
      gx(x, pg),
      gy(y, pg),
      size, size
    );
  }
}
