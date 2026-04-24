## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## volume_slider.gd
##
## Handles the volume control slider UI component.
## Sends volume updates to AudioManager and handles debounced saving.
## Plays rate-limited SFX exclusively on manual user interactions,
## safely ignoring programmatic volume changes to prevent audio spam.

class_name VolumeSlider
extends HSlider

## The cooldown in milliseconds to prevent audio spam during rapid slider drags.
const SFX_COOLDOWN_MS: int = 60

## The name of the audio bus this slider controls (e.g., "Master", "Music").
@export var bus_name: String

## The internal index of the audio bus, resolved at runtime.
var bus_index: int

## Debounce timer for saving settings to avoid disk I/O spam during continuous sliding.
var save_debounce_timer: Timer

# --- SFX Rate Limiting and State ---

## Timestamp of the last played SFX to enforce the cooldown.
var _last_sfx_time: int = 0

## Tracks the previous value to ensure SFX only plays on actual deltas.
var _previous_value: float = -1.0

## Tracks whether the user is actively holding the mouse button down over the slider.
var _is_dragging: bool = false

## Guard flag to explicitly mute SFX and prevent saves during programmatic value updates.
var _is_programmatic_change: bool = false


## Initializes the slider, resolves the bus index, syncs the initial value without
## triggering signals, and sets up the debounce timer.
## :rtype: void
func _ready() -> void:
	# Get bus id by name
	bus_index = AudioServer.get_bus_index(bus_name)

	# Set current bus volume value first (without triggering signal yet)
	var initial_val: float = db_to_linear(AudioServer.get_bus_volume_db(bus_index))
	_previous_value = initial_val
	value = initial_val

	# Now connect signal for future changes
	value_changed.connect(_on_value_changed)

	# Safely track input without overriding the base _gui_input virtual method
	gui_input.connect(_on_gui_input)

	# Initialize debounce timer (0.5s delay, one-shot)
	save_debounce_timer = Timer.new()
	save_debounce_timer.wait_time = 0.5
	save_debounce_timer.one_shot = true
	save_debounce_timer.timeout.connect(_on_debounce_timeout)
	add_child(save_debounce_timer)


## Safe method for external scripts to update the slider without triggering SFX or saves.
## Use this instead of modifying `value` directly when restoring settings.
## :param new_value: The target volume (0.0 to 1.0).
## :type new_value: float
## :rtype: void
func set_value_programmatically(new_value: float) -> void:
	_is_programmatic_change = true
	value = new_value
	_is_programmatic_change = false


## Tracks mouse drag state for accurate interaction gating, even if the cursor
## leaves the slider's bounding box while dragging.
## :param event: The input event passed by the UI system.
## :type event: InputEvent
## :rtype: void
func _on_gui_input(event: InputEvent) -> void:
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

	# Prevent disk I/O spam during programmatic updates (like initial load or presets)
	if not _is_programmatic_change:
		# Godot automatically restarts an active timer when start() is called
		save_debounce_timer.start()


## Guards SFX playback against programmatic changes, redundant values, and rapid spam.
## Ensures sound only plays during legitimate, rate-limited user interactions.
## :param new_value: The updated slider value.
## :type new_value: float
## :rtype: void
func _handle_slider_sfx(new_value: float) -> void:
	# Guard 0: Ignore explicitly marked programmatic changes (e.g. from UI syncs)
	if _is_programmatic_change:
		return

	# Guard 1: Only play if the value actually changed (float-safe delta check)
	if is_equal_approx(new_value, _previous_value):
		return

	# Guard 2: Only play if user is actively interacting (Mouse Drag or Keyboard Focus)
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

	# NO MORE MAGIC STRINGS!
	AudioManager.play_sfx(AudioConstants.SFX_SLIDER)


## Called on timer timeout—performs the batched disk save.
## :rtype: void
func _on_debounce_timeout() -> void:
	AudioManager.save_volumes()
	Globals.log_message("Debounced settings save triggered.", Globals.LogLevel.DEBUG)
