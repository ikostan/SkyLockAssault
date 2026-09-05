class_name FPSCounter
extends Label

## The central settings resource to listen to for visibility changes.
## Assign this in the Inspector, or load it dynamically in _ready().
@export var settings: GameSettingsResource


func _ready() -> void:
	if not settings:
		# Use the global singleton so it shares state with advanced_settings.gd
		settings = Globals.settings
		
	if settings:
		# 1. Set the initial visibility state on load
		_update_visibility(settings.show_fps)
		
		# 2. Connect to the global signal for mid-game toggles
		settings.setting_changed.connect(_on_setting_changed)
	else:
		push_warning("FPSCounter: GameSettingsResource not assigned or found!")


func _process(_delta: float) -> void:
	# Update text with current framerate. 
	# This function will stop running when the node is hidden.
	text = "FPS: %d" % Engine.get_frames_per_second()


func _on_setting_changed(setting_name: String, new_value: Variant) -> void:
	# Only react if the specific setting changed was 'show_fps'
	if setting_name == "show_fps":
		_update_visibility(new_value as bool)


func _update_visibility(is_visible: bool) -> void:
	visible = is_visible
	# PERFORMANCE OPTIMIZATION: 
	# Only run the _process string formatting loop if the UI is actually visible.
	set_process(is_visible)
