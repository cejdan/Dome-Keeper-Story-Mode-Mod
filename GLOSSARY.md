# Story Mode

A game mode for Dome Keeper, played alone or in co-op (online or splitscreen). The keeper digs down a ladder of ever more valuable minerals, sells them for dollars and spends the dollars in the shop. A voice in the deep urges them on.

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
One of the eight ragged bands the map is split into from the surface down, each with its own rock colour, rock hardness and mineral mix. Numbered B1 to B8 from the top.
_Avoid_: Layer, tier, level

**Mineral mix**:
The share of a biome's deposits that each mineral gets.
_Avoid_: Spawn table, drop rate

**Metal tile**:
A tile the keeper's drill cannot break. A Suit Blaster blast breaks it, and so do the Mine Driller and Drillbert once their team owns that gadget's Metal Bit. Found in the gate and in scattered clumps in B6 to B8.
_Avoid_: Steel, armour block, gate tile

**Gate**:
The one-tile wall of metal tiles along the B3/B4 boundary, so the only way past B3 is to blast or cut through it.
_Avoid_: Barrier, door

**Magma pocket**:
A hidden pocket of lava in plain rock that floods the keeper's tunnels when broken into.
_Avoid_: Lava vein

**Lava pool**:
An enclosed cavern, B5 and deeper, already full of standing lava.
_Avoid_: Lava lake

**Lava ocean**:
The funnel of lava below B8, the only place unobtainium is found. It is full width at the top, so digging down from anywhere breaks into it, and narrows down to the boss chamber.
_Avoid_: Lava lake, lava floor

**Gas pocket**:
A hidden pocket of noxious gas in plain rock, B2 down to the lava ocean. Broken into, it releases gas that climbs whatever the keeper has dug.
_Avoid_: Gas vein, poison

**Gas cavern**:
An enclosed cavern, B2 and deeper, already full of noxious gas.
_Avoid_: Gas pool

**Translator chamber**:
A small 2x2 chamber, built like a vanilla gadget chamber, that holds a translator. There are three, in B2, B4 and B6.
_Avoid_: Relic chamber, artifact chamber

**Supplement chamber**:
The vanilla chamber that offers a choice of gadget supplements, unchanged in Story Mode. Gadgets are bought in the shop, never found in chambers, and there is no relic.
_Avoid_: Water chamber, power core chamber, relic chamber

**Boss chamber**:
The sealed room under the narrow end of the lava ocean, centred on the map, where the horror sleeps.
_Avoid_: Boss room, arena

**Chains**:
The chains that bind every unobtainium deposit in the lava ocean to the boss chamber's roof. Mining a deposit breaks its chain.
_Avoid_: Roots, tethers

### The keeper's dangers

**Suit heat**:
The keeper's heat bar. It fills from depth heat, lava and burning gas; at 100% the suit makes an overheat recall.
_Avoid_: Temperature, heat damage

**Depth heat**:
The heat that builds in deep biomes. It starts in B4 and each Heat Shielding level pushes it one biome deeper.
_Avoid_: Passive heat (code only), ambient heat

**Heat Shielding**:
A suit upgrade in four levels, bought per keeper, that slows lava heat and moves depth heat deeper.
_Avoid_: Heat resistance, cooling

**Overheat recall**:
The suit's emergency teleport back to the dome when suit heat or the toxin bar is full.
_Avoid_: Death, respawn

**Toxin bar**:
The green bar that fills while the keeper breathes noxious gas, in the mine or in a gassed dome. When full, the keeper is recalled.
_Avoid_: Poison bar, health

**Vent the Dome**:
The shop item that clears the gas that has vented into the dome.
_Avoid_: Air filter

**Suit Blaster**:
The keeper's mining blaster, bought in the shop per keeper. Its blast breaks rock and metal tiles.
_Avoid_: Bomb, Blast Suit (an old name)

**Metal Bit**:
A shop item that lets a drilling gadget (the Mine Driller, Drillbert) cut metal tiles.
_Avoid_: Metal drill

### The story

**Horror**:
The ancient thing asleep in the boss chamber, which speaks to the keeper and urges them to dig deeper. Its name, Velle, is revealed late in the run.
_Avoid_: Monster (that word is the dome attackers'), boss (that is the fight, not the character), eldritch

**Monsters**:
The planet's native creatures that attack the dome in waves, trying to stop the keeper before the horror wakes.
_Avoid_: Aliens, enemies

**Halcyon Minerals**:
The company that sent the keeper (Halcyon Minerals Inc.). It knew about the horror, and only the data logs say so.
_Avoid_: The corporation, the employer

**Story beat**:
A text box from the horror or the narrator that pauses the wave countdown. It is shown once per run when the keeper first reaches a depth or event. The horror's lines grow louder and stranger over four style tiers.
_Avoid_: Cutscene, dialogue, milestone (that is the trigger, not the beat)

**Narrator**:
The voice in a story beat that describes what the keeper feels or sees, apart from the horror's lines.
_Avoid_: Keeper's thoughts

**Plea**:
A line from the monsters that appears above the dome during a wave without pausing the fight.
_Avoid_: Bark, taunt

**Runes**:
The alien script the monsters' pleas are written in until the keeper can translate them. Each rune stands for one letter.
_Avoid_: Glyphs, gibberish, alien text

**Translator**:
An alien artifact, one of three, that the keeper carries home to the dome to understand more of the monsters' pleas.
_Avoid_: Relic (Story Mode has none), artifact, decoder

**Translation stage**:
How much of each plea shows in English, set by the number of translators installed: none, about a third, about two thirds, then all of it. Key words translate first.
_Avoid_: Translation level, fluency

**Miner bones**:
The remains of an earlier keeper, one set per biome, worth dollars when delivered to the dome.
_Avoid_: Skeleton, corpse, fossil

**Data log**:
The suit log an earlier keeper left with their bones, opened when the bones are sold at the dome. The keeper's own welcome memo from Halcyon Minerals is shown in the same box at the start of a run.
_Avoid_: Note, diary, lore entry

**Awakening**:
The horror's slow rise from sleep: each unobtainium taken from the lava ocean weakens its seal, and breaking into the boss chamber wakes it fully.
_Avoid_: Summoning, release

### The boss

**Boss sequence**:
What follows the horror waking: the fight, then the chase, then the finale. Through it the keepers have hearts, the waves stop and nobody talks.
_Avoid_: Boss level, boss phase

**Fight**:
The battle with Velle inside the sealed boss chamber.
_Avoid_: Boss phase one

**Chase**:
After Velle's body dies, its eye-tipped tentacles follow the keeper's path back up to the dome.
_Avoid_: Escape, run

**Finale**:
The last battle at the surface. Tentacles break out of the ground beside the dome and Velle's great eye rises over it, and the dome's weapon fights them.
_Avoid_: Surface phase, last wave

**Hearts**:
The keeper's lives through the boss sequence. A hit costs one, and so does an overheat, since the recall is jammed.
_Avoid_: Health, HP

### Winning and losing

**Fill Quota**:
The $1,000,000 shop item that ends a run as a won run the moment it is bought. The win is the doom ending: the keeper leaves rich and the woken horror destroys the planet. Its code id is still `storyretirerich`.
_Avoid_: Retire Rich (its old name), victory item, buyout

**Doom ending**:
The ending that follows Fill Quota: the horror thanks the keeper, the planet is lost, and the monsters speak their last words.
_Avoid_: Bad ending, game over

**Saved ending**:
The ending that follows defeating the horror in the finale: the planet is saved.
_Avoid_: Good ending, true ending

**Fallen ending**:
The ending when the keepers run out of hearts during the boss sequence: the horror is awake and the planet is lost.
_Avoid_: Death, game over (that is the dome falling)
