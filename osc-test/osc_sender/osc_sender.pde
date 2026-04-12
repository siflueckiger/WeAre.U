import oscP5.*;
import netP5.*;

OscP5 oscP5;
NetAddress receiverAddress;

// --- GAME STATES ---
int state = 0; // 0: Menu, 1: Play, 2: GameOver

// Spieler-Daten
float p1x, p1y, p2x, p2y;
float speed = 6;
float playerSize = 50;
float coinX, coinY;
float coinSize = 30;

// Scores & Zeit
int scoreP1 = 0, scoreP2 = 0;
int timeLeft;
int gameDuration = 20; // Sekunden
int startTime;

// Steuerung
boolean w, s, a, d, up, down, left, right;

void setup() {
  size(800, 800);
  oscP5 = new OscP5(this, 12000);
  // IP des Empfängers (z.B. Raspberry Pi oder VR-Brille) eintragen
  receiverAddress = new NetAddress("127.0.0.1", 12001); 
  initGame(); 
}

void draw() {
  background(30);

  if (state == 0) {
    drawMenu();
  } 
  else if (state == 1) {
    updateGame();
    drawGame();
  } 
  else if (state == 2) {
    drawGameOver();
  }

  sendOSC(); // Datenübertragung pro Frame
}

// --- KOMMUNIKATION (MODULAR GEBÜNDELT) ---
void sendOSC() {
  OscBundle bundle = new OscBundle();

  // Position von Spieler 1
  OscMessage msgP1 = new OscMessage("/p1/pos");
  msgP1.add(p1x); msgP1.add(p1y);
  bundle.add(msgP1);

  // Position von Spieler 2
  OscMessage msgP2 = new OscMessage("/p2/pos");
  msgP2.add(p2x); msgP2.add(p2y);
  bundle.add(msgP2);

  // Position der Münze
  OscMessage msgCoin = new OscMessage("/coin/pos");
  msgCoin.add(coinX); msgCoin.add(coinY);
  bundle.add(msgCoin);

  // Spiel-Statistiken (Zustand, Zeit, Scores)
  OscMessage msgStats = new OscMessage("/game/stats");
  msgStats.add(state);
  msgStats.add(timeLeft);
  msgStats.add(scoreP1);
  msgStats.add(scoreP2);
  bundle.add(msgStats);

  oscP5.send(bundle, receiverAddress);
}

// --- LOGIK-SEKTIONEN ---
void initGame() {
  p1x = 200; p1y = 300;
  p2x = 600; p2y = 300;
  scoreP1 = 0; scoreP2 = 0;
  resetCoin();
}

void updateGame() {
  if (w) p1y -= speed; if (s) p1y += speed;
  if (a) p1x -= speed; if (d) p1x += speed;
  if (up) p2y -= speed; if (down) p2y += speed;
  if (left) p2x -= speed; if (right) p2x += speed;

  float r = playerSize/2;
  p1x = constrain(p1x, r, width-r); p1y = constrain(p1y, r, height-r);
  p2x = constrain(p2x, r, width-r); p2y = constrain(p2y, r, height-r);

  timeLeft = gameDuration - (millis() - startTime) / 1000;
  if (timeLeft <= 0) {
    timeLeft = 0;
    state = 2;
  }

  if (dist(p1x, p1y, coinX, coinY) < (playerSize/2 + coinSize/2)) { scoreP1++; resetCoin(); }
  if (dist(p2x, p2y, coinX, coinY) < (playerSize/2 + coinSize/2)) { scoreP2++; resetCoin(); }
}

void resetCoin() {
  float minD = 200;
  boolean found = false;
  while (!found) {
    float tx = random(50, width-50), ty = random(50, height-50);
    if (dist(tx, ty, p1x, p1y) > minD && dist(tx, ty, p2x, p2y) > minD) {
      coinX = tx; coinY = ty; found = true;
    }
    minD -= 0.5;
  }
}

// --- ZEICHNEN ---
void drawMenu() {
  textAlign(CENTER); fill(255); textSize(40);
  text("WeAre.U", width/2, height/2 - 50);
  textSize(20); text("ENTER zum Starten", width/2, height/2 + 20);
}

void drawGame() {
  noFill(); strokeWeight(3); ellipseMode(CENTER); rectMode(CENTER);
  stroke(50, 150, 255); ellipse(p1x, p1y, playerSize, playerSize);
  stroke(255, 50, 50); ellipse(p2x, p2y, playerSize, playerSize);
  fill(255, 255, 0); noStroke(); rect(coinX, coinY, coinSize, coinSize);
}

void drawGameOver() {
  textAlign(CENTER); fill(255); textSize(40);
  text("GAME OVER", width/2, height/2 - 50);
  textSize(20); text("P1: " + scoreP1 + " | P2: " + scoreP2, width/2, height/2);
}

// --- INPUT ---
void keyPressed() {
  if (keyCode == ENTER) {
    if (state == 0) { state = 1; startTime = millis(); }
    else if (state == 2) { state = 0; initGame(); }
  }
  if (key == 'w' || key == 'W') w = true; if (key == 's' || key == 'S') s = true;
  if (key == 'a' || key == 'A') a = true; if (key == 'd' || key == 'D') d = true;
  if (key == CODED) {
    if (keyCode == UP) up = true; if (keyCode == DOWN) down = true;
    if (keyCode == LEFT) left = true; if (keyCode == RIGHT) right = true;
  }
}

void keyReleased() {
  if (key == 'w' || key == 'W') w = false; if (key == 's' || key == 'S') s = false;
  if (key == 'a' || key == 'A') a = false; if (key == 'd' || key == 'D') d = false;
  if (key == CODED) {
    if (keyCode == UP) up = false; if (keyCode == DOWN) down = false;
    if (keyCode == LEFT) left = false; if (keyCode == RIGHT) right = false;
  }
}
