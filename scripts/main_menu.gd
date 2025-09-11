extends Control

func _ready():
	$CenterContainer/VBoxContainer/StartButton.pressed.connect(_on_start_pressed)
	$CenterContainer/VBoxContainer/ResumeButton.pressed.connect(_on_resume_pressed)
	$CenterContainer/VBoxContainer/OptionsButton.pressed.connect(_on_options_pressed)
	$CenterContainer/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)

func _on_start_pressed():
	print("Start menu coming soon!")  # Stub; later change to load options scene

func _on_resume_pressed():
	print("Resume menu coming soon!")  # Stub; later change to load options scene

func _on_options_pressed():
	print("Options menu coming soon!")  # Stub; later change to load options scene

func _on_quit_pressed():
	get_tree().quit()  # Works in desktop; in web, it may pause or need JavaScript interopextends Control
