# New: Register as global class for testing and reuse
class_name VolumeSlider

extends HSlider

@export var bus_name: String
var bus_index: int

# New: Debounce timer for saving settings
var save_debounce_timer: Timer


func _ready() -> void:
	# Get bus id by name
	bus_index = AudioServer.get_bus_index(bus_name)

	# Set current bus volume value first (without triggering signal yet)
	value = db_to_linear(AudioServer.get_bus_volume_db(bus_index))

	# Now connect signal for future changes
	value_changed.connect(_on_value_changed)

	# New: Initialize debounce timer (0.5s delay, one-shot)
	save_debounce_timer = Timer.new()
	save_debounce_timer.wait_time = 0.5
	save_debounce_timer.one_shot = true
	save_debounce_timer.timeout.connect(_on_debounce_timeout)
	add_child(save_debounce_timer)  # Add to scene tree for auto-processing


# change bus value/volume
func _on_value_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))

	if bus_name == "Master":
		Globals.master_volume = value
		Globals.log_message(
			str(bus_name) + " volume level changed: " + str(value), Globals.LogLevel.DEBUG
		)
		Globals.log_message(
			"Master Volume Level in Globals: " + str(Globals.master_volume), Globals.LogLevel.DEBUG
		)

	if bus_name == "Music":
		Globals.music_volume = value
		Globals.log_message(
			str(bus_name) + " volume level changed: " + str(value), Globals.LogLevel.DEBUG
		)
		Globals.log_message(
			"Music Volume Level in Globals: " + str(Globals.music_volume), Globals.LogLevel.DEBUG
		)

	if bus_name == "SFX":
		Globals.sfx_volume = value
		Globals.log_message(
			str(bus_name) + " volume level changed: " + str(value), Globals.LogLevel.DEBUG
		)
		Globals.log_message(
			"SFX Volume Level in Globals: " + str(Globals.sfx_volume), Globals.LogLevel.DEBUG
		)
	
	if bus_name == "SFX_Rotors":
		Globals.rotors_volume = value
		Globals.log_message(
			str(bus_name) + " volume level changed: " + str(value), Globals.LogLevel.DEBUG
		)
		Globals.log_message(
			"Rotors Volume Level in Globals: " + str(Globals.rotors_volume), Globals.LogLevel.DEBUG
		)

	# New: Start/restart debounce timer instead of immediate save
	if save_debounce_timer.is_stopped():
		save_debounce_timer.start()
	else:
		save_debounce_timer.stop()
		save_debounce_timer.start()


# New: Called on timer timeout—perform the batched save
func _on_debounce_timeout() -> void:
	Globals._save_settings()
	Globals.log_message("Debounced settings save triggered.", Globals.LogLevel.DEBUG)
