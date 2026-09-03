# Session Log: Sender HUD Redesign

## Goal
Make the sender.pde HUD clearer and easier to scan by reorganizing the condensed
top-left text block into dedicated corner panels, with priority on score+time,
then warnings, then state/mode.

## Branch
agent/game-modes-core

## Files Changed
- sender/sender.pde: replaced drawHud()/hudTag() with panel-based HUD

## Changes
- Scoreboard panel (top-center): mode + game state title bar (color-coded per
  state), large P1/P2 scores in tag colors, prominent remaining time.
- Warnings panel (top-center below scoreboard): flashing red banners for OOB
  countdowns, no tag data, serial not connected; orange for unknown TagID.
- Player cards (left/right edges): position + speed; debug details (tagid,
  mask, per-anchor distances, trail) behind D key toggle.
- System panel (bottom-left): serial status, frames, filters, OSC target,
  scale.
- Mode panel (bottom-right): mode-specific hudLines (e.g. Coin Hunt lives,
  powerup effects).
- Keys panel (top-right): consolidated key bindings, H toggles visibility.

## Commands Executed
- git add sender/sender.pde
- git commit -m "feat: reorganize sender HUD into corner panels with scoreboard and warnings"
