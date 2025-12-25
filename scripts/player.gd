extends Node2D

## Player controller for P-38 Lightning in SkyLockAssault.
## Manages movement, fuel, bounds, rotors (anim/sound), weapons.

# Fuel color thresholds (percentages)
const HIGH_FUEL_THRESHOLD: float = 90.0  # Starts green lerp
const MEDIUM_FUEL_THRESHOLD: float = 50.0  # Switches to yellow lerp
const MAX_FUEL: float = 100.0  # Fully Red Color
const LOW_FUEL_THRESHOLD: float = 30.0  # Switches to red lerp
const NO_FUEL_THRESHOLD: float = 15.0  # Fully Red Color
# Bounds hitbox scale (quarter texture = tight margin for top-down plane)
const HITBOX_SCALE: float = 0.25
const MAX_SPEED: float = 713.0
const LOW_SPEED_THRESHOLD: float = MAX_SPEED * 10.0 / 100.0
const OVER_SPEED_THRESHOLD: float = MAX_SPEED * 90.0 / 100.0
const BLINK_INTERVAL: float = 0.5  # Seconds between blinks

# Exported vars first (for Inspector editing)
@export var current_speed: float = 250.0
var current_fuel: float

# Regular vars for computed boundaries (no export needed if set in code)
var screen_size: Vector2
var player_x_min: float = 0.0
var player_x_max: float = 0.0
var player_y_min: float = 0.0
var player_y_max: float = 0.0
# Weapon system
var weapons: Array[Node] = []  # Fill in editor or _ready
var current_weapon: int = 0
var rotor_left_sfx: AudioStreamPlayer2D
var rotor_right_sfx: AudioStreamPlayer2D
var fuel_section_factor: float
var speed_section_factor: float
var corner_radius: int = 10
var label_color: Color
var label_warning_color: Color
var fuel: Dictionary
var speed: Dictionary

# Onreadys next
@onready var rotor_right: Node2D = $CharacterBody2D/RotorRight
@onready var rotor_left: Node2D = $CharacterBody2D/RotorLeft
@onready var player: CharacterBody2D = $CharacterBody2D
@onready var player_sprite: Sprite2D = $CharacterBody2D/Sprite2D
@onready var collision_shape: CollisionPolygon2D = $CharacterBody2D/CollisionPolygon2D
@onready var fuel_bar: ProgressBar = $"../PlayerStatsPanel/Stats/Fuel/FuelBar"
@onready var fuel_label: Label = $"../PlayerStatsPanel/Stats/Fuel/FuelLabel"
@onready var fuel_label_blink_timer: Timer = $"../PlayerStatsPanel/Stats/Fuel/FuelLabel/BlinkTimer"
@onready var fuel_timer: Timer = $FuelTimer
@onready
var speed_label_blink_timer: Timer = $"../PlayerStatsPanel/Stats/Speed/SpeedLabel/BlinkTimer"
@onready var speed_label: Label = $"../PlayerStatsPanel/Stats/Speed/SpeedLabel"
# Get the fill style
@onready var fuel_bar_fill_style: StyleBoxFlat = fuel_bar.get_theme_stylebox("fill")
@onready var speed_bar: ProgressBar = $"../PlayerStatsPanel/Stats/Speed/SpeedBar"
@onready var speed_bar_fill_style: StyleBoxFlat = speed_bar.get_theme_stylebox("fill")
# In plane.gd (or main player script) - central input
@onready var weapon: Node2D = $CharacterBody2D/Weapon  # Path to your WeaponManager node


func _ready() -> void:
	# Auto-start rotors (overrides editor if needed)
	rotor_left_sfx = rotor_left.get_node("AudioStreamPlayer2D")
	rotor_right_sfx = rotor_right.get_node("AudioStreamPlayer2D")

	if rotor_left_sfx:
		rotor_left_sfx.bus = "SFX_Rotor_Left"
		Globals.log_message("Twin rotors: LEFT stereo PAN active!", Globals.LogLevel.DEBUG)
	else:
		Globals.log_message("No left rotor SFX found", Globals.LogLevel.DEBUG)

	if rotor_right_sfx:
		rotor_right_sfx.bus = "SFX_Rotor_Right"
		Globals.log_message("Twin rotors: RIGHT stereo PAN active!", Globals.LogLevel.DEBUG)
	else:
		Globals.log_message("No right rotor SFX found", Globals.LogLevel.DEBUG)

	rotor_start(rotor_right, rotor_right_sfx)
	rotor_start(rotor_left, rotor_left_sfx)
	Globals.log_message("Rotors AUTO-STARTED at 24 FPS!", Globals.LogLevel.DEBUG)

	# Set screen boundaries (safe null check + fallback)
	screen_size = get_viewport_rect().size  # Dynamic for web/resizes

	var sprite_size: Vector2 = Vector2(174.0, 132.0)  # Fallback if texture missing
	if player_sprite.texture != null:
		sprite_size = player_sprite.texture.get_size()
		Globals.log_message("Player sprite size: " + str(sprite_size), Globals.LogLevel.DEBUG)
	else:
		var warning_msg: String = (
			"Player sprite texture missing! Using fallback size: " + str(sprite_size)
		)
		Globals.log_message(warning_msg, Globals.LogLevel.WARNING)
		push_warning(warning_msg)

	player_x_min = (screen_size.x * -0.5) + (sprite_size[0] * HITBOX_SCALE)
	player_x_max = (screen_size.x * 0.5) - (sprite_size[0] * HITBOX_SCALE)
	player_y_min = (screen_size.y * -0.83) + (sprite_size[1] * HITBOX_SCALE)
	player_y_max = (screen_size.y / 6) - (sprite_size[1] * HITBOX_SCALE)

	# After player_half_width/height calc
	Globals.log_message(
		(
			"Boundaries: x("
			+ str(player_x_min)
			+ "-"
			+ str(player_x_max)
			+ ") y("
			+ str(player_y_min)
			+ "-"
			+ str(player_y_max)
			+ ")"
		),
		Globals.LogLevel.DEBUG
	)

	# Initialize fuel bar style
	fuel_bar_fill_style = StyleBoxFlat.new()
	set_bar_fill_style(fuel_bar, fuel_bar_fill_style)
	fuel_bar.max_value = MAX_FUEL

	# Initialize speed bar style and value
	speed_bar_fill_style = StyleBoxFlat.new()
	set_bar_fill_style(speed_bar, speed_bar_fill_style)
	speed_bar.max_value = MAX_SPEED
	label_color = get_label_text_color(fuel_label)

	# Initialize fuel bar style and value
	current_fuel = MAX_FUEL
	fuel_timer.timeout.connect(_on_fuel_timer_timeout)
	fuel_timer.start()

	speed = {
		"speed": current_speed,
		"factor": speed_section_factor,
		"timer": speed_label_blink_timer,
		"label": speed_label,
		"max": MAX_SPEED,
		"bar": speed_bar,
		"bar style": speed_bar_fill_style,
		"blinking": false,
	}

	fuel = {
		"fuel": current_fuel,
		"factor": fuel_section_factor,
		"timer": fuel_label_blink_timer,
		"label": fuel_label,
		"max": MAX_FUEL,
		"bar": fuel_bar,
		"bar style": fuel_bar_fill_style,
		"blinking": false,
	}

	# Initialize fuel blink timer
	if fuel["timer"]:
		fuel["timer"].wait_time = BLINK_INTERVAL
		fuel["timer"].one_shot = false  # Repeat indefinitely
		fuel["timer"].timeout.connect(_on_fuel_blink_timer_timeout)

	# Initialize speed blink timer
	if speed["timer"]:
		speed["timer"].wait_time = BLINK_INTERVAL
		speed["timer"].one_shot = false  # Repeat indefinitely
		speed["timer"].timeout.connect(_on_speed_blink_timer_timeout)

	# Init speed bar
	speed["bar"].max_value = speed["max"]  # Set max speed value
	update_speed_bar()  # Ensure the bar updates with the initial speed
	update_fuel_bar()  # Set initial UI and color

	# Null-safe weapon log
	if weapon:
		Globals.log_message(
			"Player ready. Weapons loaded: " + str(weapon.weapon_types.size()),
			Globals.LogLevel.DEBUG
		)
	else:
		push_error("Weapon node not found! Check player.tscn scene tree for $Weapon child.")


func get_label_text_color(label: Label) -> Color:
	# Try to get the theme color first
	var color: Color = label.get_theme_color("font_color", "Label")
	if color.is_equal_approx(Color(0, 0, 0, 0)):  # Default color might be invalid
		# Fall back to checking override if theme color is not set
		if label.has_theme_color_override("font_color"):
			color = label.get_theme_color("font_color", "Label")
	return color


func set_label_text_color(label: Label, new_color: Color) -> void:
	if label:
		# Apply the color as a theme override
		label.add_theme_color_override("font_color", new_color)
		Globals.log_message("Label text color set to: " + str(new_color), Globals.LogLevel.DEBUG)


func set_bar_fill_style(bar: ProgressBar, bar_fill_style: StyleBoxFlat) -> void:
	bar_fill_style.corner_radius_bottom_left = corner_radius
	bar_fill_style.corner_radius_top_left = corner_radius
	bar_fill_style.corner_radius_bottom_right = corner_radius
	bar_fill_style.corner_radius_top_right = corner_radius
	bar.add_theme_stylebox_override("fill", bar_fill_style)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("fire"):
		# Globals.log_message("Fire input pressed → calling weapon.fire()", Globals.LogLevel.DEBUG)
		if weapon and weapon.has_method("fire"):
			weapon.fire()
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("next_weapon"):
		Globals.log_message("Next weapon input pressed", Globals.LogLevel.DEBUG)
		if weapon and weapon.has_method("switch_to") and weapon.get_num_weapons() > 1:
			var next: int = (weapon.current_index + 1) % weapon.get_num_weapons()
			weapon.switch_to(next)
		get_viewport().set_input_as_handled()


## Starts rotor animation and SFX if available.
## @param rotor: The rotor Node2D to animate.
## @param rotor_sfx: The optional AudioStreamPlayer2D for sound.
## @return: void
func rotor_start(rotor: Node2D, rotor_sfx: AudioStreamPlayer2D) -> void:
	rotor.get_node("AnimatedSprite2D").play("default")
	if rotor_sfx != null:
		rotor_sfx.play()


## Stops rotor animation and SFX if available.
## @param rotor: The rotor Node2D to stop.
## @param rotor_sfx: The optional AudioStreamPlayer2D for sound.
## @return: void
func rotor_stop(rotor: Node2D, rotor_sfx: AudioStreamPlayer2D) -> void:
	rotor.get_node("AnimatedSprite2D").stop()
	if rotor_sfx != null:
		rotor_sfx.stop()


func update_fuel_bar() -> void:
	fuel["bar"].value = fuel["fuel"]
	var fuel_percent: float = (fuel["fuel"] / fuel["max"]) * 100.0

	if fuel_percent > HIGH_FUEL_THRESHOLD:
		fuel["bar style"].bg_color = Color.GREEN  # Full green for high fuel
	elif fuel_percent >= MEDIUM_FUEL_THRESHOLD:
		# Lerp green to yellow (factor 0 at 90%, 1 at 50%)
		fuel["factor"] = (
			(HIGH_FUEL_THRESHOLD - fuel_percent) / (HIGH_FUEL_THRESHOLD - MEDIUM_FUEL_THRESHOLD)
		)
		fuel["bar style"].bg_color = Color.GREEN.lerp(Color.YELLOW, fuel["factor"])
	elif fuel_percent >= LOW_FUEL_THRESHOLD:
		# Lerp yellow to red
		fuel["factor"] = (
			(MEDIUM_FUEL_THRESHOLD - fuel_percent) / (MEDIUM_FUEL_THRESHOLD - LOW_FUEL_THRESHOLD)
		)
		fuel["bar style"].bg_color = Color.YELLOW.lerp(Color.RED, fuel["factor"])
	elif fuel_percent >= NO_FUEL_THRESHOLD:
		# Lerp red to darker or full red
		fuel["factor"] = (
			(LOW_FUEL_THRESHOLD - fuel_percent) / (LOW_FUEL_THRESHOLD - NO_FUEL_THRESHOLD)
		)
		fuel["bar style"].bg_color = Color.RED.lerp(Color(0.5, 0, 0), fuel["factor"])
	else:
		fuel["bar style"].bg_color = Color.RED.lerp(Color(0.5, 0, 0), fuel["factor"])


func update_speed_bar() -> void:
	speed["bar"].value = speed["speed"]
	speed["factor"] = speed["speed"] / MAX_SPEED  # Speed lerp factor is a 0–1 range
	speed["bar style"].bg_color = Color.CORAL.lerp(Color.DARK_ORANGE, speed["factor"])


# Connect Timer's timeout signal
func _on_fuel_timer_timeout() -> void:
	# Scale base rate
	var fuel_left: float = fuel["fuel"] - (0.5 * Globals.difficulty)
	# Clamp and update current_fuel first
	fuel["fuel"] = clamp(fuel_left, 0, fuel["max"])
	# Update UI from the clamped value
	update_fuel_bar()
	# Check fuel level and start/stop blinking
	check_fuel_warning()

	if fuel["fuel"] <= 0:
		speed["speed"] = 0.0  # Or game over logic
		fuel_timer.stop()
		rotor_stop(rotor_right, rotor_right_sfx)
		rotor_stop(rotor_left, rotor_left_sfx)
		update_speed_bar()
	Globals.log_message("Fuel left: " + str(fuel["fuel"]), Globals.LogLevel.DEBUG)


func check_fuel_warning() -> void:
	if fuel["fuel"] <= LOW_FUEL_THRESHOLD and not fuel["blinking"]:
		start_blinking(fuel)
	elif fuel["fuel"] > LOW_FUEL_THRESHOLD and fuel["blinking"]:
		stop_blinking(fuel)


func check_speed_warning() -> void:
	if speed["speed"] <= LOW_SPEED_THRESHOLD and not speed["blinking"]:
		start_blinking(speed)
	elif speed["speed"] >= OVER_SPEED_THRESHOLD and not speed["blinking"]:
		start_blinking(speed)
	elif (
		OVER_SPEED_THRESHOLD > speed["speed"]
		and speed["speed"] > LOW_SPEED_THRESHOLD
		and speed["blinking"]
	):
		stop_blinking(speed)


func start_blinking(param: Dictionary) -> void:
	if param["label"] and param["timer"]:
		label_warning_color = Color.RED.lerp(Color(0.5, 0, 0), 1.0)
		param["blinking"] = true
		param["timer"].start()
		_toggle_label(param["label"])  # Immediate first toggle


func stop_blinking(param: Dictionary) -> void:
	if param["label"] and param["timer"]:
		param["blinking"] = false
		param["timer"].stop()
		set_label_text_color(param["label"], label_color)


func _on_fuel_blink_timer_timeout() -> void:
	if fuel["blinking"] and fuel["label"]:
		_toggle_label(fuel["label"])


func _on_speed_blink_timer_timeout() -> void:
	if speed["blinking"] and speed["label"]:
		_toggle_label(speed["label"])


func _toggle_label(label: Label) -> void:
	if get_label_text_color(label) == label_color:
		set_label_text_color(label, label_warning_color)
	else:
		set_label_text_color(label, label_color)


func _physics_process(_delta: float) -> void:
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "speed_up", "speed_down")
	if direction != Vector2.ZERO:
		player.velocity = direction * speed["speed"]
	else:
		player.velocity = Vector2.ZERO
	player.move_and_slide()

	player.position.x = clamp(player.position.x, player_x_min, player_x_max)
	player.position.y = clamp(player.position.y, player_y_min, player_y_max)
	update_speed_bar()
	check_speed_warning()
