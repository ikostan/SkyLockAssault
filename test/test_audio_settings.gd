## test_audio_settings.gd
## Unit tests for audio_settings.gd functionality.
##
## Covers initialization, back handling, and unexpected exits.
##
## Uses GdUnitTestSuite for assertions and hooks.

extends GdUnitTestSuite

var audio_menu: Control
var mock_globals: Node  # Mock for Globals


func before() -> void:
	## Global setup: Mock Globals and instantiate menu.
	##
	## :rtype: void
	mock_globals = auto_free(Node.new())
	mock_globals.hidden_menus = []
	mock_globals.log_message = func(msg: String, lvl: int) -> void: pass  # Mock log
	mock_globals.LogLevel = {DEBUG = 0, WARNING = 1}  # Mock enum
	add_child(mock_globals)  # For tree context
	# Replace Globals with mock in script (via preload or injection if needed; here assume accessible)
	# For simplicity, test without full replacement—focus on calls


func before_test() -> void:
	## Per-test setup: Instantiate fresh menu.
	##
	## :rtype: void
	audio_menu = auto_free(load("res://scenes/audio_settings.tscn").instantiate())
	add_child(audio_menu)  # Enter tree to trigger _ready


func after_test() -> void:
	## Per-test cleanup: Free menu.
	##
	## :rtype: void
	if is_instance_valid(audio_menu):
		audio_menu.queue_free()


func test_ready_connects_signals() -> void:
	## Tests _ready connects signals and sets mode.
	##
	## :rtype: void
	assert_bool(audio_menu.audio_back_button.pressed.is_connected(audio_menu._on_audio_back_button_pressed)).is_true()
	assert_bool(audio_menu.tree_exited.is_connected(audio_menu._on_tree_exited)).is_true()
	assert_int(audio_menu.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
# Mock web feature for full coverage (requires spy/mock on OS/JavaScriptBridge)


func test_back_button_pops_and_frees() -> void:
	## Tests back handler pops menu, shows prev, frees.
	##
	## :rtype: void
	var mock_prev: Node = auto_free(Node.new())
	mock_prev.visible = false
	mock_globals.hidden_menus.push_back(mock_prev)
	
	audio_menu._on_audio_back_button_pressed()
	
	assert_bool(mock_globals.hidden_menus.is_empty()).is_true()
	assert_bool(mock_prev.visible).is_true()
	# Assert queue_free called (via spy or check freed post-await)
	await await_idle_frame()
	assert_bool(not is_instance_valid(audio_menu)).is_true()  # Freed


func test_tree_exited_restores_if_stuck() -> void:
	## Tests unexpected exit restores menu.
	##
	## :rtype: void
	var mock_prev: Node = auto_free(Node.new())
	mock_prev.visible = false
	mock_globals.hidden_menus.push_back(mock_prev)
	
	audio_menu.queue_free()
	await await_idle_frame()
	
	assert_bool(mock_globals.hidden_menus.is_empty()).is_true()
	assert_bool(mock_prev.visible).is_true()
