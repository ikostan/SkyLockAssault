## test_audio_manager.gd
## Unit tests for audio_manager.gd.
##
## Covers load/save/apply volumes.
##
## Uses GdUnitTestSuite for assertions and file handling.

extends GdUnitTestSuite

var manager: Node
var test_path: String = "user://test_audio.cfg"  # Temp for isolation

## Per-test setup: Instantiate manager and init defaults.
## :rtype: void
func before_test() -> void:
	manager = auto_free(load("res://scripts/audio_manager.gd").new())
	manager._init_to_defaults()  # Manually set defaults (since _ready() not called in isolation)

## Per-test cleanup: Remove test file.
## :rtype: void
func after_test() -> void:
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)

## Tests load uses defaults if file missing.
## :rtype: void
func test_load_volumes_defaults_on_missing() -> void:
	manager.load_volumes(test_path)  # Isolated path (assumed missing)
	assert_float(manager.get_volume(AudioConstants.BUS_MASTER)).is_equal(1.0)
	assert_bool(manager.get_muted(AudioConstants.BUS_MASTER)).is_false()
	assert_float(manager.get_volume(AudioConstants.BUS_MUSIC)).is_equal(1.0)
	assert_bool(manager.get_muted(AudioConstants.BUS_MUSIC)).is_false()
	assert_float(manager.get_volume(AudioConstants.BUS_SFX)).is_equal(1.0)
	assert_bool(manager.get_muted(AudioConstants.BUS_SFX)).is_false()
	assert_float(manager.get_volume(AudioConstants.BUS_SFX_WEAPON)).is_equal(1.0)
	assert_bool(manager.get_muted(AudioConstants.BUS_SFX_WEAPON)).is_false()
	assert_float(manager.get_volume(AudioConstants.BUS_SFX_ROTORS)).is_equal(1.0)
	assert_bool(manager.get_muted(AudioConstants.BUS_SFX_ROTORS)).is_false()

## Tests save/load round-trip.
## :rtype: void
func test_save_and_load_volumes() -> void:
	manager.set_volume(AudioConstants.BUS_MASTER, 0.5)
	manager.save_volumes(test_path)
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	manager.set_volume(AudioConstants.BUS_MASTER, 1.0)  # Reset
	manager.load_volumes(test_path)
	assert_float(manager.get_volume(AudioConstants.BUS_MASTER)).is_equal(0.5)

## Tests apply sets db if bus exists.
## :rtype: void
func test_apply_volume_to_bus_sets_db() -> void:
	manager.apply_volume_to_bus("Master", 0.5, false)
	assert_float(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))).is_equal_approx(linear_to_db(0.5), 1e-6)

## Tests audio save preserves unrelated sections (e.g., "Settings").
## :rtype: void
func test_save_volumes_preserves_other_sections() -> void:
	# Pre-create config with non-audio section
	var config: ConfigFile = ConfigFile.new()
	config.set_value("Settings", "difficulty", 1.5)
	config.save(test_path)
	
	# Save audio
	manager.set_volume(AudioConstants.BUS_MASTER, 0.7)
	manager.save_volumes(test_path)
	
	# Reload and check both sections preserved
	config = ConfigFile.new()
	config.load(test_path)
	assert_float(config.get_value("audio", "master_volume", 1.0)).is_equal(0.7)
	assert_float(config.get_value("Settings", "difficulty", 1.0)).is_equal(1.5)

## Tests load ignores/preserves other sections.
## :rtype: void
func test_load_volumes_with_other_sections() -> void:
	# Pre-save mixed config
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "music_volume", 0.4)
	config.set_value("input", "fire", ["key:32"])  # Mock input
	config.save(test_path)
	
	# Load and verify audio loaded, others ignored
	manager.load_volumes(test_path)
	assert_float(manager.get_volume(AudioConstants.BUS_MUSIC)).is_equal(0.4)
	# No assert on input, as it's not loaded here
