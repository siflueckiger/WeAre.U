import oscP5.*;
import netP5.*;

OscP5 oscP5;
PGraphics canvas; 

// Spielzustand: 0 = Menü, 1 = Spiel läuft, 2 = Game Over
int state = 0;

// Variablen für Spielobjekte und UI
float p1x, p1y, p2x, p2y, coinX, coinY;
int timeLeft, scoreP1, scoreP2;

// Größen der Objekte (skaliert für den kleineren Viewport)
float playerSize, coinSize;

void setup() {
  size(800, 400); // Gesamtfenster
  canvas = createGraphics(400, 400); // Einzelner Viewport
  
  // OSC Listener auf Port 12001
  oscP5 = new OscP5(this, 12001);
  
  // Skalierung basierend auf der Sendergröße (800) zum Receiver (400)
  playerSize = 60 * (400.0 / 800.0);
  coinSize   = 40 * (400.0 / 800.0);
}

void draw() {
  background(0);

  // Zeichnen auf dem separaten Canvas beginnen
  canvas.beginDraw();
  canvas.background(20);
  canvas.rectMode(CENTER);
  canvas.ellipseMode(CENTER);

  if (state == 0) {
    // Startmenü
    drawReceiverMenu(canvas);
  } else if (state == 1) {
    // Spiel läuft
    drawReceiverGame(canvas);
  } else if (state == 2) {
    // Game Over
    drawReceiverGameOver(canvas); 
  }
  canvas.endDraw();

  // Split-Screen Rendering: Das gleiche Canvas-Bild zweimal anzeigen
  
  // linkes Bild
  image(canvas, 0, 0);
  
  // rechtes Bild
  image(canvas, 400, 0);
  
  // Trennlinie zwischen den beiden Ansichten zeichnen
  //stroke(100);
  //line(400, 0, 400, height);
}

// --- OSC-EVENT HANDLER ---
void oscEvent(OscMessage msg) {
  // Player 1
  if (msg.checkAddrPattern("/p1/pos")) {
    p1x = msg.get(0).floatValue();
    p1y = msg.get(1).floatValue();
  } 
  // Player 2
  else if (msg.checkAddrPattern("/p2/pos")) {
    p2x = msg.get(0).floatValue();
    p2y = msg.get(1).floatValue();
  } 
  // Coin
  else if (msg.checkAddrPattern("/coin/pos")) {
    coinX = msg.get(0).floatValue();
    coinY = msg.get(1).floatValue();
  } 
  // Stats
  else if (msg.checkAddrPattern("/game/stats")) {
    state    = msg.get(0).intValue();
    timeLeft = msg.get(1).intValue();
    scoreP1  = msg.get(2).intValue();
    scoreP2  = msg.get(3).intValue();
  }
}


// --- FUNKTIONEN ZUM ZEICHNEN DER GAMESTATES ---

// MENU
void drawReceiverMenu(PGraphics pg) {
  pg.textAlign(CENTER, CENTER);
  pg.fill(255);
  pg.textSize(26);
  pg.text("Warte auf Spieler...", pg.width/2, pg.height/2);
}

// SPIEL
void drawReceiverGame(PGraphics pg) {
  // Koordinaten mappen
  float drawP1x = map(p1x, 0, 800, 0, pg.width);
  float drawP1y = map(p1y, 0, 800, 0, pg.height);
  float drawP2x = map(p2x, 0, 800, 0, pg.width);
  float drawP2y = map(p2y, 0, 800, 0, pg.height);
  float drawCX  = map(coinX, 0, 800, 0, pg.width);
  float drawCY  = map(coinY, 0, 800, 0, pg.height);

  pg.noStroke();
  
  // Player 1
  pg.fill(50, 150, 255);
  pg.ellipse(drawP1x, drawP1y, playerSize, playerSize);
  
  // Player 2
  pg.fill(255, 50, 50);
  pg.ellipse(drawP2x, drawP2y, playerSize, playerSize);
  
  // Coin
  pg.fill(255, 255, 0);
  pg.rect(drawCX, drawCY, coinSize, coinSize);
  
  // --- UI ELEMENTE ---
  
  // Zeit
  pg.fill(255);
  pg.textSize(18);
  pg.textAlign(CENTER);
  pg.text(timeLeft, pg.width/2, 30);
  
  // Player 1
  pg.fill(50, 150, 255);
  pg.textSize(25);
  pg.textAlign(LEFT);
  pg.text(scoreP1, 20, 30);
  
  // Player 2
  pg.fill(255, 50, 50);
  pg.textSize(25);
  pg.textAlign(RIGHT);
  pg.text(scoreP2, pg.width - 20, 30);
}

// GAME OVER
void drawReceiverGameOver(PGraphics pg) {
  pg.textAlign(CENTER, CENTER);
  
  // 1. "GAME OVER" Titel
  pg.fill(255);
  pg.textSize(32);
  pg.text("GAME OVER", pg.width/2, pg.height/2 - 60);
  
  // 2. Gewinner-Ermittlung
  String resultText;
  if (scoreP1 > scoreP2) {
    pg.fill(50, 150, 255); // Blau für Spieler 1
    resultText = "SPIELER 1 GEWINNT!";
  } else if (scoreP2 > scoreP1) {
    pg.fill(255, 50, 50);  // Rot für Spieler 2
    resultText = "SPIELER 2 GEWINNT!";
  } else {
    pg.fill(200);           // Grau für Unentschieden
    resultText = "UNENTSCHIEDEN!";
  }
  
  pg.textSize(26);
  pg.text(resultText, pg.width/2, pg.height/2 - 10);
  
  // 3. Anzeige der Punkte in den jeweiligen Farben
  pg.textSize(22);
  
  // Punktzahl Spieler 1 (Links)
  pg.fill(50, 150, 255);
  pg.textAlign(RIGHT);
  pg.text("P1: " + scoreP1, pg.width/2 - 20, pg.height/2 + 40);
  
  // Trenner
  pg.fill(255);
  pg.textAlign(CENTER);
  pg.text("  ", pg.width/2, pg.height/2 + 40);
  
  // Punktzahl Spieler 2 (Rechts)
  pg.fill(255, 50, 50);
  pg.textAlign(LEFT);
  pg.text("P2: " + scoreP2, pg.width/2 + 20, pg.height/2 + 40);
}
