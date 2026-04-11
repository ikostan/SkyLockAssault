## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## player.gd
extends Node2D

## Player controller for P-38 Lightning in SkyLockAssault.
## Manages movement, fuel, bounds, rotors (anim/sound), weapons.

## Emitted when the player's forward speed changes.
signal speed_changed(new_speed: float)

# Bounds hitbox scale (quarter texture = tight margin for top-down plane)
const HITBOX_SCALE: float = 0.25

# Speed
const MAX_SPEED: float = 713.0  # mph
const MIN_SPEED: float = 95.0  # mph

# Speed threshold fractions (kept in one place to avoid divergence)
const HIGH_YELLOW_FRACTION: float = 0.80
const HIGH_RED_FRACTION: float = 0.90
const LOW_YELLOW_FRACTION: float = 0.10

# Gameplay / UI thresholds derived from fractions
const OVER_SPEED_THRESHOLD: float = MAX_SPEED * HIGH_RED_FRACTION
const HIGH_YELLOW_THRESHOLD: float = MAX_SPEED * HIGH_YELLOW_FRACTION

# UI high red warning intentionally matches over-speed gameplay threshold
const HIGH_RED_THRESHOLD: float = OVER_SPEED_THRESHOLD
const LOW_YELLOW_THRESHOLD: float = MIN_SPEED + (MAX_SPEED - MIN_SPEED) * LOW_YELLOW_FRACTION
const LOW_RED_THRESHOLD: float = MIN_SPEED
const DARK_RED: Color = Color(0.5, 0.0, 0.0)
const BLINK_INTERVAL: float = 0.5  # Seconds between blinks

# Exported vars first (for Inspector editing)
@export var lateral_speed: float = 250.0
@export var acceleration: float = 200.0
@export var deceleration: float = 100.0

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
var corner_radius: int = 10
var fuel: Dictionary
var speed: Dictionary

# Cache the global settings to avoid singleton lookups in hot paths
var _settings: GameSettingsResource = null

# Onreadys next
@onready var rotor_right: Node2D = $CharacterBody2D/RotorRight
@onready var rotor_left: Node2D = $CharacterBody2D/RotorLeft
@onready var player: CharacterBody2D = $CharacterBody2D
@onready var player_sprite: Sprite2D = $CharacterBody2D/Sprite2D
@onready var collision_shape: CollisionPolygon2D = $CharacterBody2D/CollisionPolygon2D
@onready var fuel_bar: ProgressBar = $"../PlayerStatsPanel/Stats/Fuel/FuelBar"
@onready var fuel_bar_fill_style: StyleBoxFlat = fuel_bar.get_theme_stylebox("fill")
@onready var fuel_label: Label = $"../PlayerStatsPanel/Stats/Fuel/FuelLabel"
@onready var fuel_label_blink_timer: Timer = $"../PlayerStatsPanel/Stats/Fuel/FuelLabel/BlinkTimer"
@onready var fuel_timer: Timer = $FuelTimer
@onready
var speed_label_blink_timer: Timer = $"../PlayerStatsPanel/Stats/Speed/SpeedLabel/BlinkTimer"
@onready var speed_label: Label = $"../PlayerStatsPanel/Stats/Speed/SpeedLabel"
# Get the fill style
@onready var speed_bar: ProgressBar = $"../PlayerStatsPanel/Stats/Speed/SpeedBar"
@onready var speed_bar_fill_style: StyleBoxFlat = speed_bar.get_theme_stylebox("fill")
@onready var weapon: Node2D = $CharacterBody2D/Weapon  # Path to your WeaponManager node


func _ready() -> void:
	# Safely cache the settings resource
	_settings = Globals.settings if is_instance_valid(Globals) else null

	if not is_instance_valid(_settings):
		# NEW: Log the error, but generate a fallback resource so the player
		# fully initializes and doesn't become a game-crashing "zombie" node.
		push_error("Player couldn't find Globals.settings! Using fallback defaults.")
		_settings = GameSettingsResource.new()
		# NEW: Fix the "Split Brain" problem!
		# If the Globals singleton exists, give it our new fallback resource
		# so the rest of the game (like main_scene) shares the exact same data.
		if is_instance_valid(Globals):
			Globals.settings = _settings

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
	# NEW: Using cached _settings as single source of truth
	fuel_bar.max_value = _settings.max_fuel

	# NEW: Restored the unconditional fuel reset. Since the game doesn't use mid-run resumes,
	# the player MUST spawn with a full tank to prevent infinite death loops from
	# previous 0-fuel saves.
	_settings.current_fuel = _settings.max_fuel

	# Initialize speed bar style and value
	speed_bar_fill_style = StyleBoxFlat.new()
	set_bar_fill_style(speed_bar, speed_bar_fill_style)
	speed_bar.max_value = MAX_SPEED

	# Initialize fuel bar style and value
	fuel_timer.timeout.connect(_on_fuel_timer_timeout)
	fuel_timer.start()

	# NEW: Connect to the global fuel_depleted signal to handle engine failure.
	_settings.fuel_depleted.connect(_on_player_out_of_fuel)
	# NEW: Connect to the global setting_changed signal so the UI
	# reacts to refuels/drains automatically.
	_settings.setting_changed.connect(_on_setting_changed)

	# Initialize speed dictionary
	# (Speed is still local to the player's physics, so it keeps its state here)
	speed = {
		"speed": 250.0,
		"lateral_speed": lateral_speed,
		"acceleration": acceleration,
		"deceleration": deceleration,
		"factor": 0.0,
		"timer": speed_label_blink_timer,
		"label": speed_label,
		"max": MAX_SPEED,
		"min": MIN_SPEED,
		"bar": speed_bar,
		"bar style": speed_bar_fill_style,
		"blinking": false,
	}

	# Initialize fuel dictionary
	# (Fuel state now lives in _settings. This dict is ONLY for UI.)
	fuel = {
		"factor": 0.0,
		"timer": fuel_label_blink_timer,
		"label": fuel_label,
		"bar": fuel_bar,
		"bar style": fuel_bar_fill_style,
		"blinking": false,
	}

	# Base and warning colors per stat
	fuel["base_color"] = get_label_text_color(fuel["label"])
	fuel["warning_color"] = Color.RED.lerp(Color(0.5, 0, 0), 1.0)
	speed["base_color"] = get_label_text_color(speed["label"])
	speed["warning_color"] = Color.RED.lerp(Color(0.5, 0, 0), 1.0)

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
	
	# Connect speed signal
	speed_changed.connect(_on_speed_changed)

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


func _on_speed_changed(_new_speed: float) -> void:
	update_speed_bar()
	check_speed_warning()


# NEW: Defensive cleanup to prevent dangling signal connections
# when the player is removed from the scene tree or reloaded.
func _exit_tree() -> void:
	if is_instance_valid(_settings):
		if _settings.setting_changed.is_connected(_on_setting_changed):
			_settings.setting_changed.disconnect(_on_setting_changed)

		if _settings.fuel_depleted.is_connected(_on_player_out_of_fuel):
			_settings.fuel_depleted.disconnect(_on_player_out_of_fuel)
			
		if speed_changed.is_connected(_on_speed_changed):
			speed_changed.disconnect(_on_speed_changed)


# NEW: Observer pattern handler to react when GameSettingsResource
# properties (like fuel) are updated externally.
func _on_setting_changed(setting_name: String, new_value: Variant) -> void:
	if not is_instance_valid(_settings):
		return

	if setting_name == "current_fuel":
		# NEW: Check if the engine was previously dead (timer stopped) and we just got refueled
		if float(new_value) > 0.0 and fuel_timer.is_stopped():
			# Reignite the engine: restart the consumption timer and spin up the rotors!
			fuel_timer.start()
			rotor_start(rotor_right, rotor_right_sfx)
			rotor_start(rotor_left, rotor_left_sfx)
			Globals.log_message(
				"Engine reignited! Rotors and fuel consumption resumed.", Globals.LogLevel.INFO
			)

		update_fuel_bar()
		check_fuel_warning()

	elif (
		setting_name
		in [
			"max_fuel",
			"high_fuel_threshold",
			"medium_fuel_threshold",
			"low_fuel_threshold",
			"no_fuel_threshold"
		]
	):
		fuel_bar.max_value = _settings.max_fuel
		update_fuel_bar()
		check_fuel_warning()


# NEW: Handler for engine failure triggered by the global fuel_depleted signal from the resource.
func _on_player_out_of_fuel() -> void:
	Globals.log_message("Player is out of fuel! Engine flameout.", Globals.LogLevel.WARNING)

	# NEW: Migrated the speed reset to ensure the plane actually stops flying when fuel hits 0
	var old_speed: float = speed["speed"]
	speed["speed"] = 0.0
	
	if old_speed != speed["speed"]:
		speed_changed.emit(speed["speed"])

	rotor_stop(rotor_right, rotor_right_sfx)
	rotor_stop(rotor_left, rotor_left_sfx)
	fuel_timer.stop()


## Retrieves the effective text color of a Label, considering theme overrides.
## @param label: The Label node to query.
## @return: The effective font color.
func get_label_text_color(label: Label) -> Color:
	if label.has_theme_color_override("font_color"):
		return label.get("theme_override_colors/font_color")
	return label.get_theme_color("font_color", "Label")


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
	# Fire weapon
	if event.is_action_pressed("fire"):
		if weapon and weapon.has_method("fire"):
			weapon.fire()
		get_viewport().set_input_as_handled()
	# Change weapon
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
	if rotor.has_node("AnimatedSprite2D"):
		var anim_sprite: AnimatedSprite2D = rotor.get_node("AnimatedSprite2D") as AnimatedSprite2D
		anim_sprite.play("default")
	else:
		Globals.log_message(
			"AnimatedSprite2D not found in rotor: " + rotor.name, Globals.LogLevel.WARNING
		)
	if rotor_sfx != null:
		rotor_sfx.play()


## Stops rotor animation and SFX if available.
## @param rotor: The rotor Node2D to stop.
## @param rotor_sfx: The optional AudioStreamPlayer2D for sound.
## @return: void
func rotor_stop(rotor: Node2D, rotor_sfx: AudioStreamPlayer2D) -> void:
	if rotor.has_node("AnimatedSprite2D"):
		var anim_sprite: AnimatedSprite2D = rotor.get_node("AnimatedSprite2D") as AnimatedSprite2D
		anim_sprite.stop()
	else:
		Globals.log_message(
			"AnimatedSprite2D not found in rotor: " + rotor.name, Globals.LogLevel.WARNING
		)
	if rotor_sfx != null:
		rotor_sfx.stop()


func update_fuel_bar() -> void:
	if not is_instance_valid(_settings):
		return

	# Explicitly read current and max fuel from the global settings resource.
	var cur_fuel: float = _settings.current_fuel
	var m_fuel: float = _settings.max_fuel

	fuel["bar"].value = cur_fuel
	var fuel_percent: float = 0.0 if m_fuel <= 0.0 else (cur_fuel / m_fuel) * 100.0

	# Cache thresholds locally to keep the logic clean and readable
	var high: float = _settings.high_fuel_threshold
	var medium: float = _settings.medium_fuel_threshold
	var low: float = _settings.low_fuel_threshold
	var no_fuel: float = _settings.no_fuel_threshold

	if fuel_percent > high:
		fuel["factor"] = 0.0  # Reset for consistency
		fuel["bar style"].bg_color = Color.GREEN

	elif fuel_percent >= medium:
		var span: float = high - medium
		# Guard against division by zero or negative spans
		fuel["factor"] = 1.0 if span <= 0.0 else clamp((high - fuel_percent) / span, 0.0, 1.0)
		fuel["bar style"].bg_color = Color.GREEN.lerp(Color.YELLOW, fuel["factor"])

	elif fuel_percent >= low:
		var span: float = medium - low
		fuel["factor"] = 1.0 if span <= 0.0 else clamp((medium - fuel_percent) / span, 0.0, 1.0)
		fuel["bar style"].bg_color = Color.YELLOW.lerp(Color.RED, fuel["factor"])

	elif fuel_percent >= no_fuel:
		var span: float = low - no_fuel
		fuel["factor"] = 1.0 if span <= 0.0 else clamp((low - fuel_percent) / span, 0.0, 1.0)
		fuel["bar style"].bg_color = Color.RED.lerp(Color(0.5, 0, 0), fuel["factor"])

	else:
		fuel["factor"] = 1.0  # Explicitly set to max lerp (full dark red)
		fuel["bar style"].bg_color = Color.RED.lerp(Color(0.5, 0, 0), fuel["factor"])


## Updates the speed bar value and color based on current speed.
## Colors: green normal, yellow approaching limits, red/dark red at limits.
## Factor is always updated to represent normalized proximity to limits (0.0 safe, 1.0 danger).
## @return: void
func update_speed_bar() -> void:
	speed["bar"].value = speed["speed"]
	var speed_val: float = speed["speed"]
	var factor: float = 0.0  # Always reset to safe/default

	if speed_val >= HIGH_RED_THRESHOLD:
		# Proximity to high red limit, clamped into [0.0, 1.0]
		factor = clamp(
			(speed_val - HIGH_RED_THRESHOLD) / (MAX_SPEED - HIGH_RED_THRESHOLD), 0.0, 1.0
		)
		speed["bar style"].bg_color = Color.YELLOW.lerp(DARK_RED, factor)
	elif speed_val >= HIGH_YELLOW_THRESHOLD:
		# Proximity to high yellow limit, clamped into [0.0, 1.0]
		factor = clamp(
			(speed_val - HIGH_YELLOW_THRESHOLD) / (HIGH_RED_THRESHOLD - HIGH_YELLOW_THRESHOLD),
			0.0,
			1.0
		)
		speed["bar style"].bg_color = Color.GREEN.lerp(Color.YELLOW, factor)
	elif speed_val <= LOW_RED_THRESHOLD:
		# Full danger at/under low red limit
		factor = 1.0
		speed["bar style"].bg_color = DARK_RED
	elif speed_val <= LOW_YELLOW_THRESHOLD:
		# Proximity to low yellow limit (inverted), clamped into [0.0, 1.0]
		factor = clamp(
			(LOW_YELLOW_THRESHOLD - speed_val) / (LOW_YELLOW_THRESHOLD - LOW_RED_THRESHOLD),
			0.0,
			1.0
		)
		speed["bar style"].bg_color = Color.GREEN.lerp(Color.YELLOW, factor)
	else:
		# Safe/green: explicit safe value
		factor = 0.0
		speed["bar style"].bg_color = Color.GREEN

	speed["factor"] = factor  # Always store the updated value


# Connect Timer's timeout signal
func _on_fuel_timer_timeout() -> void:
	if not is_instance_valid(_settings):
		return

	# NEW: Calculate depletion based on Global settings and update the resource directly.
	# NEW: Game over logic is now handled by _on_player_out_of_fuel via the fuel_depleted signal.
	# NEW: UI updates are handled automatically via the setting_changed signal.
	var normalized_speed: float = clamp(speed["speed"] / MAX_SPEED, 0.0, 1.0)
	var consumption: float = (
		_settings.base_consumption_rate * normalized_speed * _settings.difficulty
	)
	_settings.current_fuel -= consumption
	# Keep Globals.log_message since it is a static utility, not the state object itself
	# Globals.log_message("Fuel left: " + str(_settings.current_fuel), Globals.LogLevel.DEBUG)


func check_fuel_warning() -> void:
	if not is_instance_valid(_settings):
		return

	# NEW: Calculate the fuel percentage first to ensure consistency with the UI bar colors
	var cur_fuel: float = _settings.current_fuel
	var m_fuel: float = _settings.max_fuel
	var fuel_percent: float = 0.0 if m_fuel <= 0.0 else (cur_fuel / m_fuel) * 100.0

	# NEW: Compare the calculated percentage against the threshold
	if fuel_percent <= _settings.low_fuel_threshold and not fuel["blinking"]:
		start_blinking(fuel)
	# NEW: Compare the calculated percentage against the threshold
	elif fuel_percent > _settings.low_fuel_threshold and fuel["blinking"]:
		stop_blinking(fuel)


## Checks speed and starts/stops label blinking if approaching or exceeding limits.
## Blinking activates in yellow/red zones for low/high speeds.
## @return: void
func check_speed_warning() -> void:
	if (
		(speed["speed"] < LOW_YELLOW_THRESHOLD or speed["speed"] > HIGH_YELLOW_THRESHOLD)
		and not speed["blinking"]
	):
		start_blinking(speed)
	elif (
		LOW_YELLOW_THRESHOLD <= speed["speed"]
		and speed["speed"] <= HIGH_YELLOW_THRESHOLD
		and speed["blinking"]
	):
		stop_blinking(speed)


func start_blinking(param: Dictionary) -> void:
	if param["label"] and param["timer"]:
		param["blinking"] = true
		param["timer"].start()
		_toggle_label(param)  # Immediate first toggle


func stop_blinking(param: Dictionary) -> void:
	if param["label"] and param["timer"]:
		param["blinking"] = false
		param["timer"].stop()
		set_label_text_color(param["label"], param["base_color"])


func _on_fuel_blink_timer_timeout() -> void:
	if fuel["blinking"] and fuel["label"]:
		_toggle_label(fuel)


func _on_speed_blink_timer_timeout() -> void:
	if speed["blinking"] and speed["label"]:
		_toggle_label(speed)


func _toggle_label(param: Dictionary) -> void:
	if get_label_text_color(param["label"]) == param["base_color"]:
		set_label_text_color(param["label"], param["warning_color"])
	else:
		set_label_text_color(param["label"], param["base_color"])


func _physics_process(_delta: float) -> void:
	# NEW: Guard against null references during teardown or tests
	if not is_instance_valid(_settings):
		return
	
	# Track speed to emit signal on change
	var old_speed: float = speed["speed"]

	# Speed changes allowed only if fuel > 0
	if Input.is_action_pressed("speed_up") and _settings.current_fuel > 0:
		speed["speed"] += speed["acceleration"] * _delta

	if Input.is_action_pressed("speed_down") and _settings.current_fuel > 0:
		speed["speed"] -= speed["deceleration"] * _delta

	# Clamp current_speed between MIN_SPEED and MAX_SPEED
	if _settings.current_fuel == 0:
		# No fuel left, airplane can't fly
		speed["speed"] = clamp(speed["speed"], 0, speed["max"])
	else:
		speed["speed"] = clamp(speed["speed"], speed["min"], speed["max"])
		
	# Emit signal if speed actually changed
	if old_speed != speed["speed"]:
		speed_changed.emit(speed["speed"])

	# Left/Right movement
	var lateral_input: float = Input.get_axis("move_left", "move_right")

	# Left/Right movement, only allowed when fuel > 0 and the player is moving
	if lateral_input and _settings.current_fuel > 0 and speed["speed"] > 0:
		player.velocity.x = lateral_input * speed["lateral_speed"]
	# Reset lateral velocity if no input
	else:
		player.velocity.x = 0.0

	# Clamp player position within allowed ranged of coords
	player.position.x = clamp(player.position.x, player_x_min, player_x_max)
	player.position.y = clamp(player.position.y, player_y_min, player_y_max)

	# Update UI
	update_speed_bar()
	check_speed_warning()

	# Perform player movement
	player.move_and_slide()
