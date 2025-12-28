## test_globals.gd
## Unit tests for globals.gd saving/loading.
##
## Focuses on shared config preservation.

extends GdUnitTestSuite

var globals: Node
var test_path: String = "user://test_globals.cfg"  # Temp for isolation

func before_test() -> void:
	## Per-test setup: Instantiate globals.
	##
	## :rtype: void
	globals = auto_free(load("res://scripts/globals.gd").new())

func after_test() -> void:
	## Per-test cleanup: Remove test file.
	##
	## :rtype: void
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)

func test_save_settings_preserves_other_sections() -> void:
	## Tests settings save preserves unrelated sections (e.g., "audio").
	##
	## :rtype: void
	# Pre-create config with non-settings section
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "master_volume", 0.6)
	config.save(test_path)
	
	# Save settings
	globals.difficulty = 1.2
	globals._save_settings(test_path)
	
	# Reload and check both preserved
	config = ConfigFile.new()
	config.load(test_path)
	assert_float(config.get_value("Settings", "difficulty", 1.0)).is_equal(1.2)
	assert_float(config.get_value("audio", "master_volume", 1.0)).is_equal(0.6)

func test_load_settings_with_other_sections() -> void:
	## Tests load ignores/preserves other sections.
	##
	## :rtype: void
	# Pre-save mixed config
	var config: ConfigFile = ConfigFile.new()
	config.set_value("Settings", "difficulty", 0.8)
	config.set_value("audio", "sfx_volume", 0.9)  # Mock audio
	config.save(test_path)
	
	# Load and verify settings loaded, others ignored
	globals._load_settings(test_path)
	assert_float(globals.difficulty).is_equal(0.8)
	# No assert on audio, as it's not loaded here
