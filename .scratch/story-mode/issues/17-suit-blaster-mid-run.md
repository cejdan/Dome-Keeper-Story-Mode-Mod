# How can the Engineer get the Suit Blaster mid-run?

Type: research (AFK)
Status: open
Blocked by: none

## Question

The Suit Blaster (`suitblaster` in `upgrades.yaml`, `content/gadgets/suitblaster/`) is a primary gadget picked in the loadout and takes the `keepersuit` slot. What would it take to grant it from the shop mid-run instead?

Find out: how primary gadgets are applied at run start (`prepareGameMode`, `Level.stage`, `GameWorld.unlockElement`), what else uses the `keepersuit` slot, whether its HUD and tutorial assume loadout selection, and whether its upgrade tree then shows in the shop.
