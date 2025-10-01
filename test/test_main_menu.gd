extends GdUnitTestSuite

@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

var runner: GdUnitSceneRunner

# Optional: Setup before all tests (e.g., mock globals)
func before() -> void:
	pass


# Optional: Teardown after all tests
func after() -> void:
	pass


# Test: Start button loads the game scene
func test_start_btn_present() -> void:  # Timeout in ms for async test
	# Load and run the scene
	runner = scene_runner("res://scenes/main_menu.tscn")
	# Find the button and ensure it's ready
	var start_btn: Button = runner.find_child("StartButton") as Button
	assert_object(start_btn).is_not_null()
	assert_object(start_btn).is_instanceof(Button)
	assert_bool(start_btn.visible).is_true()  # Check post-fade
	var label: String = start_btn.text
	assert_str(label).is_equal("{START=GAME}")


# Test: Options button loads the game scene
func test_options_btn_present() -> void:  # Timeout in ms for async test
	# Load and run the scene
	runner = scene_runner("res://scenes/main_menu.tscn")
	# Find the button and ensure it's ready
	var options_btn: Button = runner.find_child("OptionsButton") as Button
	assert_object(options_btn).is_not_null()
	assert_object(options_btn).is_instanceof(Button)
	assert_bool(options_btn.visible).is_true()  # Check post-fade
	var label: String = options_btn.text
	assert_str(label).is_equal("{OPTIONS}")


# Test: Quit button loads the game scene
func test_quit_btn_present() -> void:  # Timeout in ms for async test
	# Load and run the scene
	runner = scene_runner("res://scenes/main_menu.tscn")
	# Find the button and ensure it's ready
	var quit_btn: Button = runner.find_child("QuitButton") as Button
	assert_object(quit_btn).is_not_null()
	assert_object(quit_btn).is_instanceof(Button)
	assert_bool(quit_btn.visible).is_true()  # Check post-fade
	var label: String = quit_btn.text
	assert_str(label).is_equal("{QUIT}")


func test_quit_dialog_is_null() -> void:  # Timeout in ms for async test
	# Load and run the scene
	runner = scene_runner("res://scenes/main_menu.tscn")
	# Find the button and ensure it's ready
	var quit_dialog: Button = runner.find_child("QuitDialog") as Button
	assert_object(quit_dialog).is_null()
