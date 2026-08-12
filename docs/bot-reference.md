# MiniClassColors - bot reference

Version 1.1.6. Interface versions: 120100, 120007, 50504, 40402, 38002,
38000, 30405, 30300, 20506, 11509 (retail plus the classic client lines).
No saved variables.

## What it does

Colours the health bars of the default Blizzard unit frames by class for
players, and by reaction for NPCs. Covers the frames Blizzard updates
through its shared health bar code (target, focus, target-of-target), plus
the player frame and pet frame which are hooked directly.

## Colour rules

- Players: their class colour. The pet frame uses the owner's (your) class
  colour.
- NPCs: green if friendly, yellow if neutral (or when reaction is unknown),
  red if unfriendly/hostile, grey if tap-denied (someone else's kill credit).
- The bar texture is desaturated so the colour reads cleanly.

## How it works

- Retail: hooks UnitFrameHealthBar_Update. Classic/TBC: hooks
  UnitFrameHealthBar_OnValueChanged so colours survive health updates.
- Player and pet frames get a direct SetStatusBarColor hook so other code
  cannot overwrite the colour.
- Only default Blizzard unit frames are affected; raid frames, nameplates,
  and unit frame replacement addons are untouched.

## Settings

None. No options panel, no slash commands, no saved variables. Install to
enable, remove to disable.

## Troubleshooting

- "A mob's bar is grey": that mob is tapped by another player or the enemy
  faction; grey is intentional.
- "My raid frames/nameplates are not class coloured": out of scope; this
  addon only touches the default player, pet, target, focus and
  target-of-target style frames.
- "Lua error about secret keys in a dungeon": fixed in 1.1.6; retail hides
  the class of units you are not allowed to identify, so older versions
  errored on every target-of-target update in instanced combat.
- "Colours conflict with my unit frame addon": another addon replacing or
  recolouring the same Blizzard bars will fight this one; disable one of
  them.
