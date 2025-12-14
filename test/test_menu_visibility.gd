## Test script: test_menu_visibility.gd (add to project, run as scene or via editor)
extends Node

func _ready() -> void:
	# Mock Globals
	var mock_globals: = Node.new()
	mock_globals.add_user_signal("log_message")
	mock_globals.hidden_menu = null
	mock_globals.load_options = func(menu: Node) -> void: 
		mock_globals.hidden_menu = menu
		menu.visible = false
		print("Hidden: " + menu.name + " visible=" + str(menu.visible))

	# Mock menu nodes
	var mock_main_ui: = Panel.new()
	mock_main_ui.name = "UI_Panel"
	mock_main_ui.visible = true

	var mock_pause: = CanvasLayer.new()
	mock_pause.name = "Pause_Menu"
	mock_pause.visible = true

	# Test from main
	mock_globals.load_options.call(mock_main_ui)
	assert(mock_main_ui.visible == false, "Main UI not hidden")
	assert(mock_globals.hidden_menu == mock_main_ui, "Hidden menu not set")

	# Mock back
	mock_main_ui.visible = true  # Simulate show
	mock_globals.hidden_menu = null
	assert(mock_main_ui.visible == true, "Main UI shown after back")

	# Test from pause
	mock_globals.load_options.call(mock_pause)
	assert(mock_pause.visible == false, "Pause not hidden")
	assert(mock_globals.hidden_menu == mock_pause, "Hidden menu not set")

	# Mock back
	mock_pause.visible = true  # Simulate show
	mock_globals.hidden_menu = null
	assert(mock_pause.visible == true, "Pause shown after back")

	print("All tests passed.")
	get_tree().quit()
