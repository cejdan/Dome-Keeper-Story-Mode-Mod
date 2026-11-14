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

**Translator chamber**:
A small 2x2 chamber, built like a vanilla gadget chamber, that holds a translator. There are three, in B2, B4 and B6.
_Avoid_: Relic chamber, artifact chamber

**Supplement chamber**:
The vanilla chamber that offers a choice of gadget supplements, unchanged in Story Mode.
_Avoid_: Water chamber, power core chamber, relic chamber

**Boss chamber**:
The sealed room under the lava ocean, centred on the map, where the horror sleeps.
_Avoid_: Boss room, arena

### The story

**Horror**:
The ancient thing asleep in the boss chamber, which speaks to the keeper and urges them to dig deeper. Its true name is revealed late in the run.
_Avoid_: Monster (that word is the dome attackers'), boss (that is the fight, not the character), eldritch

**Monsters**:
The planet's native creatures that attack the dome in waves, trying to stop the keeper before the horror wakes.
_Avoid_: Aliens, enemies

**Story beat**:
A text box from the horror that pauses the wave countdown, shown once per run when the keeper first reaches a depth or event.
_Avoid_: Cutscene, dialogue, milestone (that is the trigger, not the beat)

**Plea**:
A line from the monsters that appears above the dome during a wave without pausing the fight.
_Avoid_: Bark, taunt

**Miner bones**:
The remains of an earlier miner, found in the rock once per biome, that hold a data log and are worth dollars when delivered to the dome.
_Avoid_: Skeleton, corpse, fossil

**Data log**:
The journal entry an earlier miner left with their bones, read the moment the bones are uncovered.
_Avoid_: Note, diary, lore entry

**Runes**:
The alien script the monsters' pleas are written in until the keeper can translate them; each rune stands for one letter.
_Avoid_: Glyphs, gibberish, alien text

**Translator**:
An alien artifact, one of three, that the keeper carries home to the dome to understand more of the monsters' pleas.
_Avoid_: Relic (Story Mode has none), artifact, decoder

**Translation stage**:
How much of each plea shows in English, set by the number of translators installed: none, about a third, about two thirds, then all of it. Key words translate first.
_Avoid_: Translation level, fluency

**Awakening**:
The horror's slow rise from sleep: each unobtainium taken from the lava ocean weakens its seal, and breaking into the boss chamber wakes it fully.
_Avoid_: Summoning, release

### Winning

**Retire Rich**:
The $1,000,000 shop item that ends a Story Mode run the moment it is bought. It is a won run but the doom ending: the keeper leaves rich and the woken horror destroys the planet.
_Avoid_: Victory item, buyout

**Doom ending**:
The ending that follows Retire Rich: the horror thanks the keeper, then the planet is lost.
_Avoid_: Bad ending, game over

**Saved ending**:
The ending that follows defeating the horror: the planet is saved. Until the boss fight exists, only a dev command reaches it.
_Avoid_: Good ending, true ending
