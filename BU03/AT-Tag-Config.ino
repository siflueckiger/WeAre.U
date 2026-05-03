#include <Arduino.h>
static const uint32_t TAG_BAUD = 115200;

// D1 mini UART0 pins:
// GPIO3 (RX0) <- module TX
// GPIO1 (TX0) -> module RX
// Note: UART0 is shared with USB serial on most D1 mini boards.
HardwareSerial &tagUart = Serial;
HardwareSerial &debugOut = Serial1; // TX only on GPIO2 (D4)

String readTagResponse(uint32_t waitMs) {
  String response;
  uint32_t start = millis();
  while (millis() - start < waitMs) {
    while (tagUart.available() > 0) {
      int c = tagUart.read();
      if (c >= 0) {
        response += (char)c;
      }
    }
    delay(2);
  }
  return response;
}

void sendAT(const char *cmd, uint32_t responseWaitMs) {
  debugOut.print("\n> ");
  debugOut.println(cmd);
  tagUart.print(cmd);
  tagUart.print("\r\n");

  String response = readTagResponse(responseWaitMs);
  if (response.length() > 0) {
    debugOut.println(response);
  } else {
    debugOut.println("(no response)");
  }
}

void setup() {
  debugOut.begin(TAG_BAUD);
  tagUart.begin(TAG_BAUD);
  delay(200);

  // Equivalent to the provided MicroPython script flow.
  sendAT("AT+SETCFG=0,0,1,1", 1000);
  delay(3000);
  sendAT("AT+SAVE", 3000);
  sendAT("AT+GETCFG", 100);

  debugOut.println("\nDone.");

}

void loop() {
  // Nothing else required after initial AT configuration.
}
