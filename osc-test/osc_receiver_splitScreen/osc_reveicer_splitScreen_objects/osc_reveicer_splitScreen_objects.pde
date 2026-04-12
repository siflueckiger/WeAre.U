// ============================================================
// Main.pde  –  Haupt-Tab
// Nur Setup, Draw und OSC-Handler. Keine Spiellogik hier.
// ============================================================

import oscP5.*;
import netP5.*;

OscP5 oscP5;
PGraphics canvas;

// Spielzustand
int state = STATE_MENU;

// Spielobjekte
Player p1, p2;
ArrayList<GameObject> gameObjects = new ArrayList<GameObject>();

// Stats
int timeLeft;

// Konstante Spielfeldgröße (Senderseite)
final float GAME_SIZE = 800.0;

// Größen (skaliert für Viewport)
float playerSize, coinSize;


void setup() {
  size(800, 400);
  canvas = createGraphics(400, 400);

  oscP5 = new OscP5(this, 12001);

  playerSize = 60 * (400.0 / GAME_SIZE);
  coinSize   = 40 * (400.0 / GAME_SIZE);

  // Spieler anlegen – Farbe und ID übergeben
  p1 = new Player("p1", color(50, 150, 255));
  p2 = new Player("p2", color(255, 50, 50));

  // Coin als erstes GameObject anlegen
  gameObjects.add(new GameObject("coin", color(255, 255, 0)));
}


void draw() {
  background(0);

  canvas.beginDraw();
  canvas.background(20);
  canvas.rectMode(CENTER);
  canvas.ellipseMode(CENTER);

  if      (state == STATE_MENU)     drawReceiverMenu(canvas);
  else if (state == STATE_PLAYING)  drawReceiverGame(canvas);
  else if (state == STATE_GAMEOVER) drawReceiverGameOver(canvas);

  canvas.endDraw();

  // Split-Screen
  image(canvas, 0, 0);
  image(canvas, 400, 0);
}


// --- OSC-EVENT HANDLER ---
void oscEvent(OscMessage msg) {
  String addr = msg.addrPattern();

  if (addr.equals("/p1/pos")) {
    p1.x = msg.get(0).floatValue();
    p1.y = msg.get(1).floatValue();
  }
  else if (addr.equals("/p2/pos")) {
    p2.x = msg.get(0).floatValue();
    p2.y = msg.get(1).floatValue();
  }
  else if (addr.equals("/coin/pos")) {
    // Coin ist immer das erste GameObject in der Liste
    gameObjects.get(0).x = msg.get(0).floatValue();
    gameObjects.get(0).y = msg.get(1).floatValue();
  }
  else if (addr.equals("/game/stats")) {
    state    = msg.get(0).intValue();
    timeLeft = msg.get(1).intValue();
    p1.score = msg.get(2).intValue();
    p2.score = msg.get(3).intValue();
  }

  // Neue OSC-Adressen einfach hier unten anfügen:
  // else if (addr.equals("/powerup/pos")) { ... }
}


// --- DRAW STATES ---

void drawReceiverMenu(PGraphics pg) {
  pg.textAlign(CENTER, CENTER);
  pg.fill(255);
  pg.textSize(26);
  pg.text("Warte auf Spieler...", pg.width/2, pg.height/2);
}

void drawReceiverGame(PGraphics pg) {
  pg.noStroke();

  // Alle GameObjects zeichnen (Coin, PowerUps, etc.)
  for (GameObject obj : gameObjects) {
    obj.draw(pg, coinSize);
  }

  // Spieler zeichnen
  p1.draw(pg, playerSize);
  p2.draw(pg, playerSize);

  // UI
  drawHUD(pg);
}

void drawReceiverGameOver(PGraphics pg) {
  pg.textAlign(CENTER, CENTER);

  pg.fill(255);
  pg.textSize(32);
  pg.text("GAME OVER", pg.width/2, pg.height/2 - 60);

  String resultText;
  if (p1.score > p2.score) {
    pg.fill(p1.col);
    resultText = "SPIELER 1 GEWINNT!";
  } else if (p2.score > p1.score) {
    pg.fill(p2.col);
    resultText = "SPIELER 2 GEWINNT!";
  } else {
    pg.fill(200);
    resultText = "UNENTSCHIEDEN!";
  }

  pg.textSize(26);
  pg.text(resultText, pg.width/2, pg.height/2 - 10);

  pg.textSize(22);
  pg.fill(p1.col);
  pg.textAlign(RIGHT);
  pg.text("P1: " + p1.score, pg.width/2 - 20, pg.height/2 + 40);

  pg.fill(p2.col);
  pg.textAlign(LEFT);
  pg.text("P2: " + p2.score, pg.width/2 + 20, pg.height/2 + 40);
}

void drawHUD(PGraphics pg) {
  pg.fill(255);
  pg.textSize(18);
  pg.textAlign(CENTER);
  pg.text(timeLeft, pg.width/2, 30);

  pg.fill(p1.col);
  pg.textSize(25);
  pg.textAlign(LEFT);
  pg.text(p1.score, 20, 30);

  pg.fill(p2.col);
  pg.textAlign(RIGHT);
  pg.text(p2.score, pg.width - 20, 30);
}
