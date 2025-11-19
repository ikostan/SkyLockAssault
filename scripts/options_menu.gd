extends CanvasLayer

# Explicit mapping from display names to enum values
var log_level_display_to_enum := {
	"DEBUG": Globals.LogLevel.DEBUG,
	"INFO": Globals.LogLevel.INFO,
	"WARNING": Globals.LogLevel.WARNING,
	"ERROR": Globals.LogLevel.ERROR,
	"NONE": Globals.LogLevel.NONE
}

@onready var log_lvl_option: OptionButton = get_node(
	"Panel/OptionsVBoxContainer/LogLevelContainer/LogLevelOptionButton"
)
@onready var back_button: Button = $Panel/OptionsVBoxContainer/BackButton
@onready var difficulty_slider: HSlider = get_node(
	"Panel/OptionsVBoxContainer/DifficultyLevelContainer/DifficultyHSlider"
)
@onready var difficulty_label: Label = get_node(
	"Panel/OptionsVBoxContainer/DifficultyLevelContainer/DifficultyValueLabel"
)


func _input(event: InputEvent) -> void:  # Add type hints
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = event.position  # Explicitly type as Vector2
		Globals.log_message("Clicked at: (%s, %s)" % [pos.x, pos.y], Globals.LogLevel.DEBUG)


func _ready() -> void:
	# Populate OptionButton with all LogLevel enum values
	# In _ready() (replace population and add "None")
	for level: String in Globals.LogLevel.keys():
		if level != "NONE":  # Skip auto-add NONE; add manually as "None"
			log_lvl_option.add_item(level)  # "Debug", "Info", etc.
	log_lvl_option.add_item("NONE")  # Manual for title case

	# Set to current log level (find index by enum value)
	var current_value: int = Globals.current_log_level
	var index: int = Globals.LogLevel.values().find(current_value)
	if index != -1:
		log_lvl_option.selected = index
	else:
		log_lvl_option.selected = 1  # Fallback to INFO (index 1)
		Globals.log_message("Invalid saved log level—reset to INFO.", Globals.LogLevel.WARNING)

	# Connect signals
	log_lvl_option.item_selected.connect(_on_log_selected)
	back_button.pressed.connect(_on_back_pressed)

	# Difficulty level setup
	if difficulty_slider:
		difficulty_slider.min_value = 0.5  # Easy
		difficulty_slider.max_value = 2.0  # Hard
		difficulty_slider.step = 0.1
		difficulty_slider.value = Globals.difficulty  # Load current

		if !difficulty_label:
			Globals.log_message(
				"Difficulty label node not found! Using fallback label.", Globals.LogLevel.WARNING
			)
			difficulty_label = Label.new()
			difficulty_label.text = "N/A"
		else:
			difficulty_label.text = "{" + str(Globals.difficulty) + "}"

		difficulty_slider.value_changed.connect(_on_difficulty_changed)
	else:
		Globals.log_message(
			"Warning: DifficultySlider not found in options menu.", Globals.LogLevel.WARNING
		)

	# In options_menu.gd (_ready()—add at end)
	process_mode = Node.PROCESS_MODE_ALWAYS  # Ignores pause for this node/tree
	Globals.log_message(
		"Set options_menu process_mode to ALWAYS for pause ignoring.", Globals.LogLevel.DEBUG
	)
	(
		JavaScriptBridge
		. eval(
			"""
        var difficultySlider = document.createElement('input');
        difficultySlider.id = 'difficulty-slider';
        difficultySlider.type = 'range';
        difficultySlider.min = '1.0';
        difficultySlider.max = '3.0';
        difficultySlider.step = '0.1';
        difficultySlider.value = godot.call('get_difficulty');
        difficultySlider.style.position = 'absolute';
        difficultySlider.style.left = '50%';
        difficultySlider.style.top = '30%';  # Adjust from screenshot
        difficultySlider.style.transform = 'translate(-50%, -50%)';
        document.body.appendChild(difficultySlider);
        difficultySlider.onchange = function() {godot.call('_on_difficulty_changed', this.value);};

		var logLvlSelect = document.createElement('select');
        logLvlSelect.id = 'log-lvl-select';
        logLvlSelect.style.position = 'absolute';
        logLvlSelect.style.left = '50%';
        logLvlSelect.style.top = '35%';  # Adjust from screenshot
        logLvlSelect.style.transform = 'translate(-50%, -50%)';
        var options = ['DEBUG', 'INFO', 'WARNING', 'ERROR', 'NONE'];
        for (var i = 0; i < options.length; i++) {
            var opt = document.createElement('option');
            opt.value = options[i];
            opt.text = options[i];
            logLvlSelect.add(opt);
        }
        logLvlSelect.value = godot.call('get_current_log_level_name');
        document.body.appendChild(logLvlSelect);
        logLvlSelect.onchange = function() { godot.call('_on_log_selected', this.selectedIndex); };

        var backButton = document.createElement('button');
        backButton.id = 'back-button';
        backButton.style.position = 'absolute';
        backButton.style.left = '50%';
        backButton.style.top = '90%';  # Bottom from screenshot
        backButton.style.transform = 'translate(-50%, -50%)';
        backButton.innerText = 'BACK';
        document.body.appendChild(backButton);
        backButton.onclick = function() { godot.call('_on_back_pressed'); };
	"""
		)
	)
	Globals.log_message("Options menu loaded.", Globals.LogLevel.DEBUG)


func get_log_level_index() -> int:
	return Globals.LogLevel.values().find(Globals.current_log_level)


# New function for slider change
func _on_difficulty_changed(value: float) -> void:
	Globals.difficulty = value
	difficulty_label.text = "{" + str(value) + "}"
	Globals.log_message("Difficulty changed to: " + str(value), Globals.LogLevel.DEBUG)
	Globals._save_settings()


# Handles log level selection change
func _on_log_selected(index: int) -> void:
	var selected_name: String = log_lvl_option.get_item_text(index)
	var selected_enum: Globals.LogLevel = log_level_display_to_enum.get(
		selected_name, Globals.LogLevel.INFO
	)
	Globals.current_log_level = selected_enum
	# May skip if new level high
	Globals.log_message("Log level changed to: " + selected_name, Globals.LogLevel.DEBUG)
	Globals._save_settings()


# Handles Back button: Return to main menu
# In options_menu.gd (_on_back_pressed())
func _on_back_pressed() -> void:
	get_tree().paused = false  # Unpause if was paused (safe call)
	Globals.log_message("Back button pressed.", Globals.LogLevel.DEBUG)
	queue_free()  # Remove self from tree (returns to underlying scene)
