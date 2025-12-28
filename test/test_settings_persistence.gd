# test_settings_persistence.gd (extends GdUnitTestSuite)
extends GdUnitTestSuite

func test_settings_persistence() -> void:
	## Tests persistence with isolated path.
	##
	## :rtype: void
	var test_path: String = "user://test_settings.cfg"
	
	# Setup: Create and save test config
	var config: ConfigFile = ConfigFile.new()
	config.set_value("Settings", "difficulty", 1.5)
	var err: int = config.save(test_path)
	if err != OK:
		fail("Failed to save test config: " + str(err))
	
	Globals._load_settings(test_path)
	assert_float(Globals.difficulty).is_equal(1.5)  # Loaded
	
	Globals.difficulty = 2.0
	Globals._save_settings(test_path)
	
	# Reload to verify save
	Globals._load_settings(test_path)
	assert_float(Globals.difficulty).is_equal(2.0)  # Saved and loaded

func after_test() -> void:
	## Cleans test file.
	##
	## :rtype: void
	var test_path: String = "user://test_settings.cfg"
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)
