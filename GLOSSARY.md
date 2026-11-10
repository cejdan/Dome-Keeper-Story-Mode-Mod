# Story Mode

A single-player game mode for Dome Keeper where the keeper digs down a ladder of ever more valuable minerals, sells them for dollars, and spends dollars in the shop.

## Language

### What the keeper mines

**Mineral**:
Something mined that turns into dollars when it is delivered to the dome: bronze, iron, gold, sapphire, emerald, ruby, diamond, mythril and unobtainium.
_Avoid_: Resource, ore (for these)

**Resource**:
Water or cobalt: mined, counted one unit at a time, and spent directly on the upgrades and gadgets that use it. A resource never turns into dollars.
_Avoid_: Mineral (for these), sand (the game code's name for cobalt)

**Dollar value**:
The fixed number of dollars one unit of a mineral pays on delivery, the same wherever it was found.
_Avoid_: Price (prices belong to shop items)

**Mineral ladder**:
The minerals in order of rising dollar value, which is also the order they appear going down the map.
_Avoid_: Tier list
