## Test script: test_menu_visibility.gd
##
## GDUnit test suite for menu visibility logic in Globals.load_options and back behavior.
## Tests hiding and showing of mock menus from main and pause contexts.
## Run via GDUnit inspector or command line.

extends GdUnitTestSuite

# Mock Globals as Dictionary (lightweight, no Node overhead; reusable in tests)
var mock_globals: Dictionary = {
	"hidden_menu": null,
	"load_options": func(menu: Node) -> void:
		mock_globals["hidden_menu"] = menu
		menu.visible = false
}

# Setup before each test (reset mocks)
func before_test() -> void:
	mock_globals["hidden_menu"] = null  # Reset per test

# Test hiding and showing from main UI (Panel)
func test_main_ui_hide_and_show() -> void:
	var mock_main_ui: Panel = auto_free(Panel.new())
	mock_main_ui.name = "UI_Panel"
	mock_main_ui.visible = true
	
	mock_globals["load_options"].call(mock_main_ui)
	assert_bool(mock_main_ui.visible).is_false()
	assert_object(mock_globals["hidden_menu"]).is_same(mock_main_ui)
	
	# Mock back: Show and clear
	mock_main_ui.visible = true
	mock_globals["hidden_menu"] = null
	assert_bool(mock_main_ui.visible).is_true()

# Test hiding and showing from pause menu (CanvasLayer)
func test_pause_hide_and_show() -> void:
	var mock_pause: CanvasLayer = auto_free(CanvasLayer.new())
	mock_pause.name = "Pause_Menu"
	mock_pause.visible = true
	
	mock_globals["load_options"].call(mock_pause)
	assert_bool(mock_pause.visible).is_false()
	assert_object(mock_globals["hidden_menu"]).is_same(mock_pause)
	
	# Mock back: Show and clear
	mock_pause.visible = true
	mock_globals["hidden_menu"] = null
	assert_bool(mock_pause.visible).is_true()
