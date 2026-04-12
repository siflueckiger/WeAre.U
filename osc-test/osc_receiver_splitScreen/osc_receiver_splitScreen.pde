import oscP5.*;
import netP5.*;

OscP5 oscP5;
PGraphics canvas; 

int state = 0;
float p1x, p1y, p2x, p2y;
float coinX, coinY;
int timeLeft, scoreP1, scoreP2;

float playerSize; 
float coinSize;

void setup() {
  size(800, 400); // Gesamtfenster am Pi 
  canvas = createGraphics(400, 400); // Einzelnes Spielfeld 
  
  oscP5 = new OscP5(this, 12001); 
  
  // Da unser Canvas 400px breit ist, das Original 800px (Verhältnis 0.5)
  // Sender playerSize = 50 -> Receiver playerSize = 25
  playerSize = 60 * (400.0 / 800.0); 
  coinSize   = 40 * (400.0 / 800.0);  
  rectMode(CENTER);
  ellipseMode(CENTER);
}

void draw() {
  background(0);

  canvas.beginDraw();
  canvas.background(20);
  canvas.rectMode(CENTER);
  canvas.ellipseMode(CENTER);

  if (state == 0) {
    drawReceiverMenu(canvas);
  } else if (state == 1) {
    drawReceiverGame(canvas);
  } else if (state == 2) {
    drawReceiverGameOver(canvas); 
  }
  canvas.endDraw();

  // Split-Screen Darstellung [cite: 77]
  image(canvas, 0, 0);       
  image(canvas, 400, 0);     
  
  stroke(100);
  line(400, 0, 400, height);
}

void drawReceiverGame(PGraphics pg) {
  // --- KORRIGIERTES MAPPING ---
  // Wir wandeln die 800x800 Koordinaten des Senders in 400x400 um [cite: 28, 82]
  float drawP1x = map(p1x, 0, 800, 0, pg.width);
  float drawP1y = map(p1y, 0, 800, 0, pg.height); // Neu: Y-Mapping
  
  float drawP2x = map(p2x, 0, 800, 0, pg.width);
  float drawP2y = map(p2y, 0, 800, 0, pg.height); // Neu: Y-Mapping
  
  float drawCX  = map(coinX, 0, 800, 0, pg.width);
  float drawCY  = map(coinY, 0, 800, 0, pg.height); // Neu: Y-Mapping

  // Spieler 1
  pg.fill(50, 150, 255);
  pg.noStroke();
  pg.ellipse(drawP1x, drawP1y, playerSize, playerSize);
  
  // Spieler 2
  pg.fill(255, 50, 50);
  pg.ellipse(drawP2x, drawP2y, playerSize, playerSize);

  // Münze
  pg.fill(255, 255, 0);
  pg.rect(drawCX, drawCY, coinSize, coinSize);
  
  // UI
  // UI - Spieler 1
  pg.fill(50, 150, 255);
  pg.textSize(30);
  pg.textAlign(LEFT);
  pg.text(scoreP1, 20, 30);
  
  // UI - Spieler 2
  pg.fill(255, 50, 50); 
  pg.textSize(30);
  pg.textAlign(RIGHT);
  pg.text(scoreP2, pg.width - 20, 30);
  
  // UI - Zeit
  pg.fill(255);
  pg.textSize(18);
  pg.textAlign(CENTER);
  pg.text("Zeit: " + timeLeft, pg.width/2, 30);
}

// Menü und GameOver Funktionen bleiben wie gehabt...
void drawReceiverMenu(PGraphics pg) {
  pg.textAlign(CENTER, CENTER);
  pg.fill(255);
  pg.textSize(26);
  pg.text("WARTEN AUF SPIELSTART", pg.width/2, pg.height/2);
}

void drawReceiverGameOver(PGraphics pg) {
  pg.textAlign(CENTER, CENTER);
  pg.fill(255);
  pg.textSize(32);
  pg.text("SPIEL BEENDET", pg.width/2, pg.height/2 - 40);
}

void oscEvent(OscMessage msg) {
  if (msg.checkAddrPattern("/game/sync")) {
    state    = msg.get(0).intValue();
    p1x      = msg.get(1).floatValue();
    p1y      = msg.get(2).floatValue();
    p2x      = msg.get(3).floatValue();
    p2y      = msg.get(4).floatValue();
    coinX    = msg.get(5).floatValue();
    coinY    = msg.get(6).floatValue();
    // WICHTIG: Die fehlenden Daten für Score und Zeit wieder hinzufügen! [cite: 49]
    timeLeft = msg.get(7).intValue();
    scoreP1  = msg.get(8).intValue();
    scoreP2  = msg.get(9).intValue();
  }
}
