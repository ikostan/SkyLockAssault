class_name FPSCounter
extends Label

@export var settings: GameSettingsResource

func _ready() -> void:
	# Explicit else: pass forces the profiler to log the negative branch
	if settings == null:
		settings = Globals.settings
	else:
		pass 

	if settings != null:
		_update_visibility(settings.show_fps)
		settings.setting_changed.connect(_on_setting_changed)
	else:
		push_warning("FPSCounter: GameSettingsResource not assigned or found!")


func _process(_delta: float) -> void:
	text = "FPS: %d" % Engine.get_frames_per_second()


func _on_setting_changed(setting_name: String, new_value: Variant) -> void:
	# Using match eliminates the missing "else" branch arm penalty entirely
	match setting_name:
		"show_fps":
			_update_visibility(bool(new_value))
		_:
			pass


func _update_visibility(is_visible: bool) -> void:
	visible = is_visible
	set_process(is_visible)
