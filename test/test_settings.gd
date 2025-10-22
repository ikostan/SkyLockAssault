# test_settings.gd (extends GdUnitTestSuite)
extends GdUnitTestSuite

func test_file_exists_and_load() -> void:
	# Setup: Create test file
	var path: = "user://test_settings.cfg"
	var config: = ConfigFile.new()
	config.set_value("Settings", "difficulty", 1.5)
	config.save(path)
	
	# Test existence
	assert_bool(FileAccess.file_exists(path)).is_true()
	
	# Load and assert
	Globals.difficulty = 1.0  # Reset
	Globals._load_settings()  # But path is test—wait, real is settings.cfg; for test, modify _load to param or use real
	# For full test, use real path (clean after)
	var real_path: = "user://settings.cfg"
	var global_real_path: = ProjectSettings.globalize_path(real_path)  # New: Globalize for OS ops
	if FileAccess.file_exists(real_path):
		OS.move_to_trash(global_real_path)  # Updated: Use globalized path (fixes error 124)
	config.save(real_path)
	Globals._load_settings()
	assert_float(Globals.difficulty).is_equal(1.5)

func after_test() -> void:
	var real_path: = "user://settings.cfg"
	var global_real_path: = ProjectSettings.globalize_path(real_path)  # New: Globalize
	if FileAccess.file_exists(real_path):
		OS.move_to_trash(global_real_path)  # Updated: Fixes error
