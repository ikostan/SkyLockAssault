## test_audio_unexpected_exit.gd
## Unit test for audio menu unexpected exit flow on web.
##
## Simulates opening options, then audio, then unexpected removal.
## Verifies callback restoration and menu visibility.
##
## Mocks web environment for editor testing.
## Uses GdUnitTestSuite for assertions.

extends GdUnitTestSuite

var options_scene: PackedScene = preload("res://scenes/options_menu.tscn")
var audio_scene: PackedScene = preload("res://scenes/audio_settings.tscn")
var options_instance: CanvasLayer
var audio_instance: Control
var mock_js_bridge: Variant  # GdUnit mock
var mock_js_window: Dictionary  # Mock dict for JS window
var mock_os: Variant  # GdUnit mock
var options_cb_called: bool = false
var options_cb: Callable  # Mock options callback


func before_test() -> void:
	## Per-test setup: Mock web, instantiate menus, reset Globals.
	##
	## :rtype: void
	# Mock OS.has_feature("web") to true
	mock_os = mock("OS")
	do_return(true).on(mock_os).has_feature("web")

	# Mock JavaScriptBridge
	mock_js_bridge = mock("JavaScriptBridge")
	mock_js_window = {"backPressed": null}  # Initial mock window
	do_return(mock_js_window).on(mock_js_bridge).get_interface("window")
	do_return(null).on(mock_js_bridge).eval(GdUnitArgumentMatchers.any(), GdUnitArgumentMatchers.any())  # No-op for eval
	do_return(func(cb: Callable) -> Callable: return cb).on(mock_js_bridge).create_callback(GdUnitArgumentMatchers.any())  # Return callable as "JSObject"

	# Reset Globals
	Globals.hidden_menus = []
	Globals.options_open = false
	Globals.options_instance = null

	# Instantiate options
	options_instance = auto_free(options_scene.instantiate())
	add_child(options_instance)
	Globals.options_open = true
	Globals.options_instance = options_instance
	Globals.hidden_menus = []  # Ensure empty

	# Simulate options setting its callback
	options_cb = Callable(self, "_mock_options_back_cb")
	mock_js_window["backPressed"] = options_cb
	Globals.log_message("Initial backPressed set to options_cb.", Globals.LogLevel.DEBUG)


func after_test() -> void:
	## Per-test cleanup: Free instances, reset mocks.
	##
	## :rtype: void
	if is_instance_valid(options_instance):
		options_instance.queue_free()
	if is_instance_valid(audio_instance):
		audio_instance.queue_free()
	Globals.hidden_menus = []
	reset(mock_os)
	reset(mock_js_bridge)


func test_unexpected_audio_exit_restores_callback() -> void:
	## Tests unexpected audio removal restores callback and menu.
	##
	## :rtype: void
	Globals.log_message("Starting unexpected exit test.", Globals.LogLevel.DEBUG)

	# Log initial callback
	Globals.log_message("Initial backPressed: " + str(mock_js_window["backPressed"]), Globals.LogLevel.DEBUG)

	# Instantiate audio (simulates opening from options)
	audio_instance = auto_free(audio_scene.instantiate())
	add_child(audio_instance)
	Globals.hidden_menus.push_back(options_instance)
	options_instance.visible = false

	# Log after audio _ready, backPressed should be audio's cb
	Globals.log_message("After audio _ready, backPressed: " + str(mock_js_window["backPressed"]), Globals.LogLevel.DEBUG)
	assert_that(mock_js_window["backPressed"]).is_not_equal(options_cb)  # Overwritten by audio

	# Simulate unexpected exit
	audio_instance.queue_free()
	await get_tree().process_frame  # Wait for tree exit

	# Verify restoration
	assert_that(mock_js_window["backPressed"]).is_equal(options_cb)
	Globals.log_message("After exit, backPressed: " + str(mock_js_window["backPressed"]), Globals.LogLevel.DEBUG)

	# Verify menu visibility and stack
	assert_bool(options_instance.visible).is_true()
	assert_bool(Globals.hidden_menus.is_empty()).is_true()

	# Simulate call to verify correct callback is restored and functional
	options_cb_called = false  # Reset flag
	mock_js_window["backPressed"].call([])
	assert_bool(options_cb_called).is_true()  # Verify it was called


func _mock_options_back_cb(args: Array) -> void:
	## Mock callback for options back press.
	##
	## :param args: Unused JS args.
	## :type args: Array
	## :rtype: void
	options_cb_called = true
	Globals.log_message("Mock options back callback called.", Globals.LogLevel.DEBUG)
