## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## volume_slider.gd
##
## Handles the volume control slider UI component.
## Sends volume updates to AudioManager and handles debounced saving.
## Plays rate-limited SFX exclusively on manual user interactions.

class_name VolumeSlider
extends HSlider

@export var bus_name: String
var bus_index: int

## Debounce timer for saving settings to avoid disk I/O spam
var save_debounce_timer: Timer

# --- SFX Rate Limiting and State ---
var _last_sfx_time: int = 0
const SFX_COOLDOWN_MS: int = 60
var _previous_value: float = -1.0
var _is_dragging: bool = false


func _ready() -> void:
	# Get bus id by name
	bus_index = AudioServer.get_bus_index(bus_name)

	# Set current bus volume value first (without triggering signal yet)
	var initial_val: float = db_to_linear(AudioServer.get_bus_volume_db(bus_index))
	_previous_value = initial_val
	value = initial_val

	# Now connect signal for future changes
	value_changed.connect(_on_value_changed)

	# Initialize debounce timer (0.5s delay, one-shot)
	save_debounce_timer = Timer.new()
	save_debounce_timer.wait_time = 0.5
	save_debounce_timer.one_shot = true
	save_debounce_timer.timeout.connect(_on_debounce_timeout)
	add_child(save_debounce_timer)  # Add to scene tree for auto-processing


## Tracks mouse drag state for accurate interaction gating, even if the cursor
## leaves the slider's bounding box while dragging.
## :param event: The input event passed by the UI system.
## :type event: InputEvent
## :rtype: void
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_is_dragging = event.pressed


## Signal listener for when the slider value changes (manual or programmatic).
## :param new_value: The new volume level from the slider (0.0 to 1.0).
## :type new_value: float
## :rtype: void
func _on_value_changed(new_value: float) -> void:
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(new_value))
	AudioManager.set_volume(bus_name, new_value)
	
	# Attempt to play interaction feedback
	_handle_slider_sfx(new_value)
	
	# Godot automatically restarts an active timer when start() is called
	save_debounce_timer.start()


## Guards SFX playback against programmatic changes, redundant values, and rapid spam.
## Ensures sound only plays during legitimate, rate-limited user interactions.
## :param new_value: The updated slider value.
## :type new_value: float
## :rtype: void
func _handle_slider_sfx(new_value: float) -> void:
	# Guard 1: Only play if the value actually changed (float-safe delta check)
	if is_equal_approx(new_value, _previous_value):
		return
	
	# Guard 2: Only play if user is actively interacting
	var is_mouse_active: bool = _is_dragging
	var is_keyboard_active: bool = has_focus()
	
	if not (is_mouse_active or is_keyboard_active):
		return
		
	# Guard 3: Rate limit to prevent audio spam during rapid drags
	var current_time: int = Time.get_ticks_msec()
	if current_time - _last_sfx_time < SFX_COOLDOWN_MS:
		return
		
	# Commit state only after all guards pass
	_last_sfx_time = current_time
	_previous_value = new_value
	
	AudioManager.play_sfx("slider")


## Called on timer timeout—performs the batched disk save.
## :rtype: void
func _on_debounce_timeout() -> void:
	AudioManager.save_volumes()
	Globals.log_message("Debounced settings save triggered.", Globals.LogLevel.DEBUG)
