# Choplifter Clone — Design Document

## Game Overview

A faithful-but-modernized clone of Dan Gorlin's *Choplifter* (1982).

## Core Loop

1. Take off from base
2. Navigate side-scrolling terrain under enemy fire
3. Land near hostage buildings to rescue prisoners
4. Return rescued hostages to base
5. Repeat across escalating levels

## Player Controls

| Action         | Input       |
|----------------|-------------|
| Move left/right | Arrow keys / WASD |
| Climb / Descend | Up/Down arrow |
| Face left       | Z / Q       |
| Face right      | X / E       |
| Face forward    | C           |
| Fire            | Space       |

## Enemies

- **Tanks** — ground units, fire at low-flying helicopter
- **Jets** — aerial enemies on later levels
- **Soldiers** — shoot/capture hostages on the ground

## Win / Lose Conditions

- **Win:** Rescue all hostages and return them safely
- **Lose:** Helicopter destroyed, or all hostages killed/captured

## Technical Notes

_To be filled in once engine is chosen._
