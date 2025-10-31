extends HSlider

@export var bus_name: String
@export var bus_index: int


func _ready() -> void:
	# get bus id by name
	bus_index = AudioServer.get_bus_index(bus_name)
	# connect signal
	value_changed.connect(_on_value_changed)
	# get current bus volium value
	value = db_to_linear(AudioServer.get_bus_volume_db(bus_index))

# change bus value/volium
func _on_value_changed(value: float) -> void:
	
	AudioServer.set_bus_volume_db(
		bus_index,
		linear_to_db(value)
	)
	
	if bus_name == "Master":
		Globals.master_volume = value
		Globals.log_message(str(bus_name) + " volune level changed: " + str(value), Globals.LogLevel.DEBUG)
		Globals.log_message("Master Volune Level in Globals: " + str(Globals.master_volume), Globals.LogLevel.DEBUG)

	if bus_name == "Music":
		Globals.music_volume = value
		Globals.log_message(str(bus_name) + " volune level changed: " + str(value), Globals.LogLevel.DEBUG)
		Globals.log_message("Music Volune Level in Globals: " + str(Globals.music_volume), Globals.LogLevel.DEBUG)

	if bus_name == "SFX":
		Globals.sfx_volume = value
		Globals.log_message(str(bus_name) + " volune level changed: " + str(value), Globals.LogLevel.DEBUG)
		Globals.log_message("SFX Volune Level in Globals: " + str(Globals.sfx_volume), Globals.LogLevel.DEBUG)

	Globals._save_settings()
