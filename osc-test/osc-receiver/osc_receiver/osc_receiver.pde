import oscP5.*;
import netP5.*;

OscP5 oscP5;

// Variablen für die Daten vom Sender
int state = 0; // 0: Menu, 1: Play, 2: GameOver
float p1x, p1y, p2x, p2y;
float coinX, coinY;
int timeLeft, scoreP1, scoreP2;

// Größen-Definitionen
float playerSize = 50;
float coinSize = 30;

void setup() {
  size(800, 600);
  oscP5 = new OscP5(this, 12001); // Port muss zum Sender passen
  
  rectMode(CENTER);
  ellipseMode(CENTER);
}

void draw() {
  background(20);

  // --- STATE 0: MENU ---
  if (state == 0) {
    drawReceiverMenu();
  } 
  
  // --- STATE 1: PLAY ---
  else if (state == 1) {
    drawReceiverGame();
  } 
  
  // --- STATE 2: GAMEOVER ---
  else if (state == 2) {
    drawReceiverGameOver();
  }
}

// --- VISUALISIERUNGS-FUNKTIONEN ---

void drawReceiverMenu() {
  textAlign(CENTER, CENTER);
  fill(255);
  textSize(45);
  text("WARTEN AUF SPIELSTART", width/2, height/2);
  
  // Kleiner pulsierender Effekt für den Text
  textSize(20);
  fill(150 + sin(frameCount * 0.1) * 100); 
  text("Spieler bereiten sich vor...", width/2, height/2 + 60);
}

void drawReceiverGame() {
  // Spieler 1: BLAU
  fill(50, 150, 255);
  noStroke();
  ellipse(p1x, p1y, playerSize, playerSize);
  
  // Spieler 2: ROT
  fill(255, 50, 50);
  ellipse(p2x, p2y, playerSize, playerSize);
  
  // Münze: GELBES QUADRAT
  fill(255, 255, 0);
  rect(coinX, coinY, coinSize, coinSize);
  
  // Scores & Zeit oben anzeigen
  fill(255);
  textSize(24);
  textAlign(LEFT);
  text("Blau: " + scoreP1, 30, 40);
  textAlign(RIGHT);
  text("Rot: " + scoreP2, width - 30, 40);
  textAlign(CENTER);
  text("Zeit: " + timeLeft, width/2, 40);
}

void drawReceiverGameOver() {
  textAlign(CENTER, CENTER);
  fill(255);
  textSize(50);
  text("SPIEL BEENDET", width/2, height/2 - 80);
  
  textSize(30);
  text("Ergebnis: " + scoreP1 + " zu " + scoreP2, width/2, height/2 - 20);
  
  // Gewinner-Ankündigung
  textSize(40);
  if (scoreP1 > scoreP2) {
    fill(50, 150, 255);
    text("BLAU HAT GEWONNEN!", width/2, height/2 + 50);
  } else if (scoreP2 > scoreP1) {
    fill(255, 50, 50);
    text("ROT HAT GEWONNEN!", width/2, height/2 + 50);
  } else {
    fill(200);
    text("UNENTSCHIEDEN!", width/2, height/2 + 50);
  }
}

// --- OSC EMPFANG ---

void oscEvent(OscMessage msg) {
  if (msg.checkAddrPattern("/game/sync")) {
    // EXAKTE Reihenfolge wie im Sender-Sketch:
    state    = msg.get(0).intValue();
    p1x      = msg.get(1).floatValue();
    p1y      = msg.get(2).floatValue();
    p2x      = msg.get(3).floatValue();
    p2y      = msg.get(4).floatValue();
    coinX    = msg.get(5).floatValue();
    coinY    = msg.get(6).floatValue();
    timeLeft = msg.get(7).intValue();
    scoreP1  = msg.get(8).intValue();
    scoreP2  = msg.get(9).intValue();
  }
}
