// ============================================================
// GameObject.pde  –  Tab für alle Spielobjekte
// Coin, PowerUp, Obstacle – alles erbt von hier.
// ============================================================

class GameObject {
  String type;
  color col;
  float x, y;
  boolean active = true;

  GameObject(String type, color col) {
    this.type = type;
    this.col  = col;
  }

  // Basis-Draw: Rechteck (kann in Subklassen überschrieben werden)
  void draw(PGraphics pg, float size) {
    if (!active) return;
    pg.fill(col);
    pg.rect(gx(x, pg), gy(y, pg), size, size);
  }
}


// --- Subklassen für spezifische Objekte ---

// Beispiel: PowerUp (Dreieck statt Rechteck)
class PowerUp extends GameObject {
  PowerUp() {
    super("powerup", color(0, 255, 100));
  }

  @Override
  void draw(PGraphics pg, float size) {
    if (!active) return;
    pg.fill(col);
    float cx = gx(x, pg);
    float cy = gy(y, pg);
    pg.triangle(
      cx,           cy - size/2,
      cx - size/2,  cy + size/2,
      cx + size/2,  cy + size/2
    );
  }
}

// Beispiel: Hindernis (größeres graues Rechteck)
class Obstacle extends GameObject {
  Obstacle() {
    super("obstacle", color(150));
  }

  @Override
  void draw(PGraphics pg, float size) {
    if (!active) return;
    pg.fill(col);
    pg.rect(gx(x, pg), gy(y, pg), size * 2, size); // breiter als hoch
  }
}
