extends RefCounted

# Installs the script extensions (mod_main.modInit) so that no script loses a
# class_name to them (#252, #256).
#
# Why: a script resolves `extends Map`, `var dome: Dome`, `x is CaveBomb` or
# `Array[Tile]` when Godot 4.3 compiles it. The analyzer finds the class in the
# global class list (Map -> res://content/map/Map.gd) and parses that file,
# whose class_name makes the class "Map"; the compiler then asks the script
# cached at that path for its class "Map". Once ModLoader's take_over_path has
# put our extension at the path, the script there has no class_name, so the
# lookup fails: `extends Map` does not compile ("Could not find class "Map" in
# "res://content/map/Map.gd""), a typed variable compiles untyped ("Compiler
# bug: unresolved assign"), a typed array comes out untyped, and an `is` test
# (also `is Map.Inner`) passes for any object. Value uses (Map.new(),
# Map.CONST, static calls) are fine, and so is extending a script that has no
# class_name by path. A script compiled before the takeover keeps its
# (vanilla) classes and works; recompiling one after it breaks it, so fixing
# ModLoader's _reload_vanilla_child_classes_for (it never matches) would make
# things worse, not better.
#
# So: before the first extension goes in, compile and hold every vanilla
# script being extended and every script that names one of their classes
# (NAMED_BY). They resolve the classes to vanilla's scripts, which our
# extensions extend, so a node running an extension still passes `is Map` and
# typed assignments. Vanilla subclasses (DeviceSelectionMap `extends Map`,
# Dome3 `extends Dome`) sit on vanilla's script and do not get the extension's
# behaviour; that is all a class_name subclass can have, so one that needs it
# gets its own extension (dome3.gd, the Artillery Dome). dev/scenarios/
# t252_class_names.gd rescans the project and fails when NAMED_BY or SCENES
# is missing something.

const EXT := "res://mods-unpacked/cejdan-StoryMode/extensions/"

# Each mirrors the vanilla path it extends. ModLoader compiles each extension
# again as it installs it, and a copy of its vanilla base as well, so one whose
# source or vanilla base names another extended class in a type (Map.gd's
# `tile: Tile`, dome3.gd's `extends Dome`) goes in before that class's.
const EXTENSIONS: Array[String] = [
	"stages/deviceselection/DeviceselectionStage.gd",
	"stages/level/LevelStage.gd",
	"content/techtree/TechTree.gd",
	"stages/loadout/MultiplayerloadoutStage.gd",
	"content/hud/inventory/Inventory.gd",
	"content/techtree/Tech2.gd",
	"content/techtree/TechTreePopup.gd",
	"content/map/Map.gd",
	"content/map/tile/Tile.gd",
	"content/map/tile/DirtParticle.gd",
	"content/dome/dome3/dome3.gd",
	"content/dome/Dome.gd",
	"content/map/generation/TileDataGenerator.gd",
	"content/gadgets/suitblaster/SuitblasterExplosion.gd",
	"content/caves/treecave/Iron.gd",
	"content/gadgets/mineraltree/FruitGrowth.gd",
	"content/gadgets/mineraltree/MineralTree.gd",
	"content/gadgets/minedriller/TileToucher.gd",
	"content/gadgets/drillbot/Drillbot.gd",
	"content/caves/bombcave/CaveBomb.gd",
	"content/gadgets/blastMining/Mine.gd",
	"systems/camera/KeeperCamera.gd",
	"content/gadgets/droneyard/TransportDrone.gd",
	"content/gadgets/droneyard/Squidley.gd",
	"content/keeper/keeper1/TileHitSounds.gd",
]

# Scripts that name a class_name of EXTENSIONS in a type: extends, a typed
# variable, parameter or return, an `is` / `as` test, a typed array. Vanilla
# ones and the mod's own (not the extensions or the scripts they extend,
# held anyway, and not dev/scenarios/, which Story.scenario_boot compiles at
# boot).
const NAMED_BY: Array[String] = [
	"res://content/caves/bombcave/BombCave.gd",
	"res://content/caves/bombcave/BombCaveSynchronizer.gd",
	"res://content/caves/drillicave/DrillbertCave.gd",
	"res://content/caves/seedcave/SeedCave.gd",
	"res://content/caves/seedcave/SeedCaveSynchronizer.gd",
	"res://content/critters/Critters.gd",
	"res://content/drop/egg/Egg.gd",
	"res://content/drop/mushroomfarm/Spore.gd",
	"res://content/drop/seed/Seed.gd",
	"res://content/drop/treat/Treat.gd",
	"res://content/gadgets/converter/Converter.gd",
	"res://content/gadgets/drillbot/DrillbotStation.gd",
	"res://content/gadgets/drillbot/DrillbotSynchronizer.gd",
	"res://content/gadgets/droneyard/DroneDispatcher.gd",
	"res://content/gadgets/droneyard/DroneYard.gd",
	"res://content/gadgets/extractor/Extractor.gd",
	"res://content/gadgets/lift/Lift.gd",
	"res://content/gadgets/lift/LiftOrb.gd",
	"res://content/gadgets/mineraltree/MineralTreeSynchronizer.gd",
	"res://content/gadgets/shockwave/Shockwave.gd",
	"res://content/gadgets/shockwave/ShockwaveHammer.gd",
	"res://content/gadgets/stunLaser/StunLaser.gd",
	"res://content/keeper/keeper2/BundleResourceTracker.gd",
	"res://content/keeper/keeper2/Explode.gd",
	"res://content/keeper/keeper2/Keeper2Synchronizer.gd",
	"res://content/keeper/keeper3/KunaiCarrier.gd",
	"res://content/keeper/keeper4/GoblinHole.gd",
	"res://content/keeper/keeper4/Keeper4.gd",
	"res://content/map/DropSynchronizer.gd",
	"res://content/map/Drops.gd",
	"res://content/map/Tiles.gd",
	"res://content/monster/Monsters.gd",
	"res://content/monster/diver/Diver.gd",
	"res://content/monster/phaser/Phaser.gd",
	"res://content/pause/PauseMenu.gd",
	"res://content/techtree/techtrack/TechTrack.gd",
	"res://content/weapons/artillery/Bullet.gd",
	"res://content/weapons/sword/Sword.gd",
	"res://content/worlds/ParallaxBackground.gd",
	"res://game/GameWorld.gd",
	"res://stages/deviceselection/DeviceSelectionMap.gd",
	"res://stages/landing/LandingStage.gd",
	"res://stages/level/Level.gd",
	"res://stages/level/Viewports.gd",
	"res://stages/manager/StageManager.gd",
	"res://systems/achievements/Achievements.gd",
	"res://systems/options/SoundtrackPanel.gd",
	"res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd",
	"res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd",
	"res://mods-unpacked/cejdan-StoryMode/dev/harness.gd",
	"res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd",
	"res://mods-unpacked/cejdan-StoryMode/gas/gas_director.gd",
	"res://mods-unpacked/cejdan-StoryMode/lava/lava_director.gd",
	"res://mods-unpacked/cejdan-StoryMode/lava/lava_field.gd",
	"res://mods-unpacked/cejdan-StoryMode/lava/dev_lava_finder.gd",
	"res://mods-unpacked/cejdan-StoryMode/lava/dev_lava_probe.gd",
]

# Scenes and resources that use an extended script. One cached before the
# install (loaded at boot, or preloaded by a script held above) still holds
# vanilla's script; reloading it in place makes its nodes run the extension.
const SCENES: Array[String] = [
	"res://content/caves/bombcave/CaveBomb.tscn",
	"res://content/caves/treecave/IronTreeCave.tscn",
	"res://content/dome/Dome.tscn",
	"res://content/dome/dome3/Dome3.tscn",
	"res://content/gadgets/blastMining/Mine.tscn",
	"res://content/gadgets/drillbot/Drillbot.tscn",
	"res://content/gadgets/droneyard/Squidley.tscn",
	"res://content/gadgets/droneyard/TransportDrone.tscn",
	"res://content/gadgets/minedriller/Drill.tscn",
	"res://content/gadgets/minedriller/SideDriller.tscn",
	"res://content/gadgets/mineraltree/MineralTree.tscn",
	"res://content/gadgets/suitblaster/SuitblasterExplosion.tscn",
	"res://content/hud/inventory/Inventory.tscn",
	"res://content/map/generation/TileDataGenerator.tscn",
	"res://content/map/Map.tscn",
	"res://content/map/tile/DirtParticle.tscn",
	"res://content/map/tile/Tile.tscn",
	"res://content/map/tile/TileBreakParticles.tscn",
	"res://content/shared/sounds/TileHitSounds.tscn",
	"res://content/techtree/Tech2.tscn",
	"res://content/techtree/TechTree.tscn",
	"res://content/techtree/TechTreePopup.tscn",
	"res://stages/deviceselection/DeviceselectionStage.tscn",
	"res://stages/level/LevelStage.tscn",
	"res://stages/loadout/MultiplayerloadoutStage.tscn",
	"res://systems/camera/Camera.tscn",
	"res://test/caves/CaveTest.tscn",
]


# `held` keeps the compiled scripts and reloaded scenes alive (a script let go
# of would be compiled again on its next load, after the takeover). `hold`
# false (dev: `--noclasshold`) skips the hold, to show what it prevents.
static func install(held: Array, hold: bool = true) -> void:
	if hold:
		for rel: String in EXTENSIONS:
			held.append(load("res://" + rel))
		for path: String in NAMED_BY:
			# The dev/ folder is left out of release builds.
			if ResourceLoader.exists(path):
				held.append(load(path))
	for rel: String in EXTENSIONS:
		ModLoaderMod.install_script_extension(EXT + rel)
	for path: String in SCENES:
		if ResourceLoader.has_cached(path):
			held.append(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE))
