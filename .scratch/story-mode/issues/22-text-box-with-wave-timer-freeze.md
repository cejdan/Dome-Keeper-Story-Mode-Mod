# Text box with wave-timer freeze

Type: task (AFK)
Status: open
Blocked by: 07

## Question

Show a story text box when the keeper first reaches a trigger depth, read from a mod data file (depth, text, style tier). While it is open, the wave countdown is frozen; closing it resumes from the same value. `Monsters.gd` skips its update while `GameWorld.paused` is true and stops counting down while `monsters.wavedelay` is above zero.

## Done when

- Harness: the log shows `monsters.wavecooldown` unchanged for the whole time the box is open, then counting down again after it closes.
- A screenshot shows the box with plain styling.
- Each box fires once per run.
