extends Control

func _ready():
	$CenterContainer/VBoxContainer/StartGameButton.pressed.connect(_on_start_game_pressed)
	# Connect others if added: $CenterContainer/VBoxContainer/OptionsButton.pressed.connect(_on_options_pressed)
	# $CenterContainer/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)

func _on_start_game_pressed():
	get_tree().change_scene_to_file("res://scenes/game_level.tscn")  # Placeholder for your main game scene

func _on_options_pressed():
	print("Options menu coming soon!")  # Stub; later change to load options scene

func _on_quit_pressed():
	get_tree().quit()  # Works in desktop; in web, it may pause or need JavaScript interopextends Control
