# Story Mode

A single-player game mode for Dome Keeper where the keeper digs down a ladder of ever more valuable minerals, sells them for dollars, and spends dollars in the shop.

## Language

### What the keeper mines

**Mineral**:
Something mined that turns into dollars when it is delivered to the dome: bronze, iron, gold, sapphire, emerald, ruby, mythril, diamond and unobtainium.
_Avoid_: Resource, ore (for these)

**Resource**:
Water or cobalt: mined, counted one unit at a time, and spent directly on the upgrades and gadgets that use it. A resource never turns into dollars.
_Avoid_: Mineral (for these), sand (the game code's name for cobalt)

**Dollar value**:
The fixed number of dollars one unit of a mineral pays on delivery, the same wherever it was found.
_Avoid_: Price (prices belong to shop items)

**Mineral ladder**:
The minerals in order of rising dollar value, which is also the order they become common going down the map.
_Avoid_: Tier list

**Deposit**:
A connected cluster of tiles of one mineral, found together in the rock.
_Avoid_: Vein, node, cluster

### The map

**Biome**:
One of the ragged bands the map is split into from the surface down, each with its own rock colour, rock hardness and mineral mix. Numbered B1, B2 and so on from the top.
_Avoid_: Layer, tier, level

**Mineral mix**:
The share of a biome's deposits that each mineral gets.
_Avoid_: Spawn table, drop rate

**Metal tile**:
A tile that drilling cannot break and a Suit Blaster explosion can.
_Avoid_: Steel, armour block, gate tile

**Gate**:
An unbroken wall of metal tiles along the boundary between two biomes, so the only way deeper is to blast through it.
_Avoid_: Barrier, door

**Lava ocean**:
The solid band of lava below the last biome, the only place unobtainium is found.
_Avoid_: Lava lake, lava floor

### Winning

**Retire Rich**:
The $1,000,000 shop item that ends a Story Mode run as a win the moment it is bought. Until the boss exists it is the only way to win; Story Mode has no relic.
_Avoid_: Victory item, buyout
