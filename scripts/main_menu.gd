extends Control

@onready var quit_dialog: ConfirmationDialog

# Custom logging function with timestamp
func log_message(message: String) -> void:
	var timestamp: String = Time.get_datetime_string_from_system()
	print("[%s] %s" % [timestamp, message])


func _ready() -> void:
	log_message("Initializing main menu...")
	$CenterContainer/VBoxContainer/StartButton.pressed.connect(_on_start_pressed)
	$CenterContainer/VBoxContainer/ResumeButton.pressed.connect(_on_resume_pressed)
	$CenterContainer/VBoxContainer/OptionsButton.pressed.connect(_on_options_pressed)
	$CenterContainer/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)

	# Connect dialog signals (can also do this in editor; add null check)
	quit_dialog = $CenterContainer/VBoxContainer/QuitDialog

	if quit_dialog:
		# Add signals
		log_message("QuitDialog found via get_node (using scene node).")
		if not quit_dialog.confirmed.is_connected(_on_quit_dialog_confirmed):
			quit_dialog.confirmed.connect(_on_quit_dialog_confirmed)
		if not quit_dialog.get_cancel_button().pressed.is_connected(_on_quit_dialog_canceled):
			quit_dialog.get_cancel_button().pressed.connect(_on_quit_dialog_canceled)
	else:
		var message: String = "Warning: QuitDialog node not found! Add it to the scene."
		log_message(message)


func _on_start_pressed() -> void:
	# Stub; later: get_tree().change_scene_to_file("res://game_scene.tscn")
	var message: String = "Start menu coming soon!"
	log_message(message)


func _on_resume_pressed() -> void:
	# Stub; later: load save and change scene
	var message: String = "Resume menu coming soon!"
	log_message(message)


func _on_options_pressed() -> void:
	# Stub; later: get_tree().change_scene_to_file("res://options_scene.tscn")
	var message: String = "Options menu coming soon!"
	log_message(message)


func _on_quit_pressed() -> void:
	# Show confirmation dialog
	if is_instance_valid(quit_dialog):
		$CenterContainer/VBoxContainer/QuitDialog.visible = true
		log_message("Attempting to show QuitDialog.")
		quit_dialog.popup_centered()
	else:
		var message: String = "No quit_dialog found."
		log_message(message)


func _on_quit_dialog_confirmed() -> void:
	# User confirmed: Execute platform-specific quit
	if OS.get_name() == "Web":
		# Web export: Redirect to itch.io game page (clean exit, no freeze)
		JavaScriptBridge.eval("window.location.href = 'https://ikostan.itch.io/sky-lock-assault';")
	else:
		# Desktop/editor: Standard quit
		get_tree().quit()
	var message: String = "Quit confirmed and executed!"
	log_message(message)


func _on_quit_dialog_canceled() -> void:
	# Optional: Handle cancel (e.g., play sound or log)
	$CenterContainer/VBoxContainer/QuitDialog.visible = false
	var message: String = "Quit canceled—back to skies!"
	log_message(message)
	# Dialog auto-hides on cancel, no extra code needed
