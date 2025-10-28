# test_settings_persistence.gd (extends GdUnitTestSuite)
extends GdUnitTestSuite

func test_settings_persistence() -> void:
	# Setup: Create and save a test config
	var test_path: = "user://test_settings.cfg"
	var config: = ConfigFile.new()
	config.set_value("Settings", "difficulty", 1.5)
	config.save(test_path)
	
	var real_path: = "user://settings.cfg"
	var global_real_path: = ProjectSettings.globalize_path(real_path)
	
	# Temporarily override path if _load_settings takes param; here, rename to settings.cfg or modify to load test_path
	# For simplicity, move test to real path (but clean after to avoid interference)
	if FileAccess.file_exists(real_path):
		OS.move_to_trash(global_real_path)
	else:
		pass  # Clean existing
		
	config.save(real_path)  # Use real path for test
	
	Globals._load_settings()
	assert_float(Globals.difficulty).is_equal(1.5)  # Loaded
	
	Globals.difficulty = 2.0
	Globals._save_settings()  # Now exists in globals.gd
	# Reload to verify save
	Globals._load_settings()
	assert_float(Globals.difficulty).is_equal(2.0)  # Saved and loaded

func after_test() -> void:
	var real_path: = "user://settings.cfg"
	var global_real_path: = ProjectSettings.globalize_path(real_path)  # New: Globalize
	# Clean test file
	if FileAccess.file_exists(real_path):
		OS.move_to_trash(global_real_path)
	else:
		pass
