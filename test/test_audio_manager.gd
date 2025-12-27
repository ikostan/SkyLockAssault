## test_audio_manager.gd
## Unit tests for audio_manager.gd.
##
## Covers load/save/apply volumes.
##
## Uses GdUnitTestSuite for assertions and file handling.

extends GdUnitTestSuite

var manager: Node
var test_path: String = "user://test_audio.cfg"  # Temp for isolation

func before_test() -> void:
	## Per-test setup: Instantiate manager.
	##
	## :rtype: void
	manager = auto_free(load("res://scripts/audio_manager.gd").new())

func after_test() -> void:
	## Per-test cleanup: Remove test file.
	##
	## :rtype: void
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)

func test_load_volumes_defaults_on_missing() -> void:
	## Tests load uses defaults if file missing.
	##
	## :rtype: void
	manager._load_volumes(test_path)  # Isolated path (assumed missing)
	assert_float(manager.master_volume).is_equal(1.0)
	# Similar for others

func test_save_and_load_volumes() -> void:
	## Tests save/load round-trip.
	##
	## :rtype: void
	manager.master_volume = 0.5
	manager._save_volumes(test_path)
	assert_bool(FileAccess.file_exists(test_path)).is_true()
	
	manager.master_volume = 1.0  # Reset
	manager._load_volumes(test_path)
	assert_float(manager.master_volume).is_equal(0.5)

func test_apply_volume_to_bus_sets_db() -> void:
	## Tests apply sets db if bus exists.
	##
	## :rtype: void
	manager._apply_volume_to_bus("Master", 0.5)
	assert_float(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))).is_equal_approx(linear_to_db(0.5), 1e-6)

func test_save_volumes_preserves_other_sections() -> void:
	## Tests audio save preserves unrelated sections (e.g., "Settings").
	##
	## :rtype: void
	# Pre-create config with non-audio section
	var config: ConfigFile = ConfigFile.new()
	config.set_value("Settings", "difficulty", 1.5)
	config.save(test_path)
	
	# Save audio
	manager.master_volume = 0.7
	manager._save_volumes(test_path)
	
	# Reload and check both sections preserved
	config = ConfigFile.new()
	config.load(test_path)
	assert_float(config.get_value("audio", "master_volume", 1.0)).is_equal(0.7)
	assert_float(config.get_value("Settings", "difficulty", 1.0)).is_equal(1.5)

func test_load_volumes_with_other_sections() -> void:
	## Tests load ignores/preserves other sections.
	##
	## :rtype: void
	# Pre-save mixed config
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "music_volume", 0.4)
	config.set_value("input", "fire", ["key:32"])  # Mock input
	config.save(test_path)
	
	# Load and verify audio loaded, others ignored
	manager._load_volumes(test_path)
	assert_float(manager.music_volume).is_equal(0.4)
	# No assert on input, as it's not loaded here
