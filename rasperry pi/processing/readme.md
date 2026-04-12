# WeAreU-GameVisualizer

A multi-tab Processing sketch designed to visualize a local multiplayer game transmitted via **Open Sound Control (OSC)**. This application acts as the receiver/visualizer, displaying a split-screen view of the game state.

---

## Overview
The Visualizer receives real-time data from a sender including player positions, coin locations, and game statistics. It renders these onto a central canvas which is then mirrored for a split-screen effect, suitable for VR or dual-display setups.

---

## Key Features
* **Split-Screen Rendering:** The game is drawn to an internal canvas and displayed twice on the main window.
* **Modular Architecture:** Uses dedicated tabs for configuration, game objects, and player logic.
* **Coordinate Mapping:** Automatically scales game coordinates from the sender's coordinate space (600x600) to the local viewport.
* **Real-time OSC Handling:** Listens for incoming movement and state updates.

---

## OSC Handling Details

The communication between the sender and the visualizer is managed through a structured OSC messaging system. The visualizer listens for incoming data on a specific network port and processes various message types to sync the game state.

### Network Configuration
* **Port:** The system listens for incoming OSC data on port **12001**.
* **Local Testing:** By default, the sender is configured to target IP `127.0.0.1` (localhost).

### Message Protocol
The visualizer parses messages based on specific address patterns to update game elements:

* **Player Positions (`/p1/pos`, `/p2/pos`):** Receives two float values representing the `X` and `Y` coordinates of the players.
* **Coin Position (`/coin/pos`):** Receives the current `X` and `Y` coordinates for the collectible coin.
* **Game Statistics (`/game/stats`):** A bundled message containing four integer values:
    * The current game state (Menu, Play, or GameOver).
    * The remaining time left in the round.
    * The current score for Player 1.
    * The current score for Player 2.

### Implementation Logic
* **Data Bundling:** The sender packs multiple messages into an `OscBundle` to ensure all data for a single frame is transmitted together.
* **Event Handling:** The `oscEvent` function in the visualizer acts as an interrupt, automatically updating the local `Player` and `GameObject` instances whenever new data arrives.
* **Coordinate Scaling:** Because the sender uses a fixed coordinate space of 600x600, the visualizer uses a mapping function to scale these coordinates to fit the local viewport dimensions.

---

## Project Structure
* **`WeAreU-gameVisualizer.pde`**: The main entry point handling setup, the draw loop, and OSC event listeners.
* **`Config.pde`**: Centralized parameters for window dimensions, colors, and object sizes.
* **`GameObject.pde`**: Contains the base class for items like Coins, Power-ups, and Obstacles.
* **`Player.pde`**: Defines the Player class with ID-specific colors and scoring.
* **`Utils.pde`**: Global constants for game states and coordinate mapping functions.

---

## Game States
The visualizer dynamically updates its UI based on the `state` variable received via OSC:
1.  **Menu (`STATE_MENU`)**: Displays "Warte auf Spieler..." (Waiting for players).
2.  **Playing (`STATE_PLAYING`)**: Renders active players, game objects, and the HUD (timer and scores).
3.  **Game Over (`STATE_GAMEOVER`)**: Displays the final winner and final score tallies.
