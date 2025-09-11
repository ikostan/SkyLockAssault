extends GutTest

var menu_scene = load("res://scenes/main_menu.tscn")

func test_start_button_exists():
	var menu = menu_scene.instantiate()
	add_child_autoqfree(menu)  # Adds to tree for testing
	var start_button = menu.get_node("CenterContainer/VBoxContainer/StartGameButton")
	assert_not_null(start_button, "Start button should exist")
	assert_eq(start_button.text, "Start Game", "Button text should match")

func test_start_button_signal():
	var menu = menu_scene.instantiate()
	add_child_autoqfree(menu)
	watch_signals(menu)  # GUT helper to monitor signals
	var start_button = menu.get_node("CenterContainer/VBoxContainer/StartGameButton")
	start_button.emit_signal("pressed")
	assert_signal_emitted(menu, "start_game_pressed", "Should emit on press")  # Assuming you rename to a custom signal if needed
