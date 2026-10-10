/**
 * Game mode interface. The engine owns the shared state machine, start zones,
 * countdown, round timer and out-of-bounds handling; a mode only implements the
 * round content. Ported from `sender_py/modes/base.py`.
 */
import type { GameEngine } from "../engine.js";

export abstract class GameMode {
  readonly id: string = "base";
  readonly displayName: string = "Base";
  protected engine: GameEngine;

  constructor(engine: GameEngine) {
    this.engine = engine;
  }

  // lifecycle
  onModeEnter(): void {}
  onRoundEnd(): void {}
  abstract onRoundStart(): void;
  abstract update(dt: number): void;

  // data
  scores(): [number, number] {
    return [0, 0];
  }
  hudLines(): string[] {
    return [];
  }
  resultText(): [string, string] | null {
    return null;
  }
  playerLives(_player: number): number {
    return -1;
  }
  playerEffects(_player: number): string[] {
    return [];
  }

  /** seconds of remaining invulnerability (drives hit flash); 0 by default */
  playerInvuln(_player: number): number {
    return 0;
  }

  // engine hook when a player stayed out of bounds too long
  onPlayerOut(player: number): void {
    this.engine.roundWinner = player === 0 ? 2 : 1;
    console.log(`P${player + 1} out of bounds -> round over`);
    this.engine.requestEnd();
  }
}
