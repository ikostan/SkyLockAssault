## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## player.gd
extends Node2D

## Player controller for P-38 Lightning in SkyLockAssault.
## Manages movement, fuel consumption, bounds, rotors, and weapons.
## Completely decoupled from UI logic via Observer Patterns.

## Emitted when the player's forward speed changes.
signal speed_changed(new_speed: float, max_speed: float)
## Emitted when speed falls below the safe threshold.
signal speed_low(threshold: float)
## Emitted when the plane hits maximum velocity.
signal speed_maxed

# Bounds hitbox scale (quarter texture = tight margin for top-down plane)
const HITBOX_SCALE: float = 0.25

var screen_size: Vector2
var player_x_min: float = 0.0
var player_x_max: float = 0.0
var player_y_min: float = 0.0
var player_y_max: float = 0.0

var rotor_left_sfx: AudioStreamPlayer2D
var rotor_right_sfx: AudioStreamPlayer2D

# Local state container for physics
var speed_resource: SpeedResource = SpeedResource.new()
var fuel_resource: FuelResource = FuelResource.new()

## The player's current forward speed.
## Acts as a transparent compatibility bridge for main_scene.gd and HUD.
var current_speed: float:
	get:
		return speed_resource.current_speed
	set(value):
		speed_resource.current_speed = value

# Cache the global settings to avoid singleton lookups in hot paths
var _settings: GameSettingsResource = null

# Core Node References
@onready var rotor_right: Node2D = $CharacterBody2D/RotorRight
@onready var rotor_left: Node2D = $CharacterBody2D/RotorLeft
@onready var player: CharacterBody2D = $CharacterBody2D
@onready var player_sprite: Sprite2D = $CharacterBody2D/Sprite2D
@onready var collision_shape: CollisionPolygon2D = $CharacterBody2D/CollisionPolygon2D
@onready var fuel_timer: Timer = $FuelTimer
@onready var weapon: Node2D = $CharacterBody2D/Weapon


## Called when the node enters the scene tree for the first time.
## Initializes the player state, calculates screen boundaries, binds inputs,
## and connects core signals for the fuel system.
## @return: void
func _ready() -> void:
	# Safely cache the settings resource
	_settings = Globals.settings if is_instance_valid(Globals) else null

	if not is_instance_valid(_settings):
		push_error("Player couldn't find Globals.settings! Using fallback defaults.")
		_settings = GameSettingsResource.new()
		if is_instance_valid(Globals):
			Globals.settings = _settings

	# Auto-start rotors
	rotor_left_sfx = rotor_left.get_node_or_null("AudioStreamPlayer2D")
	rotor_right_sfx = rotor_right.get_node_or_null("AudioStreamPlayer2D")

	if rotor_left_sfx:
		rotor_left_sfx.bus = "SFX_Rotor_Left"
	if rotor_right_sfx:
		rotor_right_sfx.bus = "SFX_Rotor_Right"

	rotor_start(rotor_right, rotor_right_sfx)
	rotor_start(rotor_left, rotor_left_sfx)
	Globals.log_message("Rotors AUTO-STARTED at 24 FPS!", Globals.LogLevel.DEBUG)

	# Set screen boundaries
	screen_size = get_viewport_rect().size

	var sprite_size: Vector2 = Vector2(174.0, 132.0)
	if player_sprite.texture != null:
		sprite_size = player_sprite.texture.get_size()
	else:
		push_warning("Player sprite texture missing! Using fallback size.")

	# --- RESTORED BOUNDARY CALCULATIONS ---
	player_x_min = (screen_size.x * -0.5) + (sprite_size[0] * HITBOX_SCALE)
	player_x_max = (screen_size.x * 0.5) - (sprite_size[0] * HITBOX_SCALE)
	player_y_min = (screen_size.y * -0.83) + (sprite_size[1] * HITBOX_SCALE)
	player_y_max = (screen_size.y / 6) - (sprite_size[1] * HITBOX_SCALE)

	# Ensure the player always spawns with a full tank and default properties
	fuel_resource.max_fuel = _settings.max_fuel

	# Setup speed boundaries and tuning properties from global settings
	speed_resource.max_speed = _settings.max_speed
	speed_resource.min_speed = _settings.min_speed
	speed_resource.acceleration = _settings.acceleration
	speed_resource.deceleration = _settings.deceleration
	speed_resource.lateral_speed = _settings.lateral_speed
	speed_resource.high_yellow_fraction = _settings.high_yellow_fraction
	speed_resource.low_yellow_fraction = _settings.low_yellow_fraction
	speed_resource.current_speed = 250.0

	# Initialize timers and observers
	fuel_timer.timeout.connect(_on_fuel_timer_timeout)
	fuel_timer.start()

	# --- Compatibility Bridges ---
	speed_resource.speed_updated.connect(
		func(spd: float): speed_changed.emit(spd, speed_resource.max_speed)
	)

	speed_resource.speed_low.connect(
		func():
			var threshold: float = (
				speed_resource.min_speed
				+ (
					(speed_resource.max_speed - speed_resource.min_speed)
					* speed_resource.low_yellow_fraction
				)
			)
			speed_low.emit(threshold)
	)

	speed_resource.speed_maxed.connect(func(): speed_maxed.emit())

	fuel_resource.fuel_depleted.connect(_on_player_out_of_fuel)
	fuel_resource.fuel_changed.connect(_on_fuel_changed)

	# Guarded reverse-compatibility listener
	if not _settings.setting_changed.is_connected(_on_setting_changed):
		_settings.setting_changed.connect(_on_setting_changed)

	if weapon:
		Globals.log_message("Player ready. Weapons loaded.", Globals.LogLevel.DEBUG)
	else:
		push_error("Weapon node not found! Check player.tscn scene tree.")


## Lifecycle callback triggered right before the node is removed from the tree.
## Safely disconnects global resource signals to prevent dangling references and memory leaks.
## @return: void
func _exit_tree() -> void:
	if fuel_resource.fuel_depleted.is_connected(_on_player_out_of_fuel):
		fuel_resource.fuel_depleted.disconnect(_on_player_out_of_fuel)
	if fuel_resource.fuel_changed.is_connected(_on_fuel_changed):
		fuel_resource.fuel_changed.disconnect(_on_fuel_changed)
	if is_instance_valid(_settings) and _settings.setting_changed.is_connected(_on_setting_changed):
		_settings.setting_changed.disconnect(_on_setting_changed)


## Observer pattern callback to react to updates from the local fuel resource.
## Re-ignites engines if refueled.
## @param new_fuel: The updated value of the property.
## @return: void
func _on_fuel_changed(new_fuel: float) -> void:
	# --- EXPLICIT COMPATIBILITY BRIDGE ---
	# Safely sync fuel drops back to Globals.settings so legacy UI/Parallax consumers
	# remain accurate until they are fully migrated.
	if is_instance_valid(_settings) and _settings.current_fuel != new_fuel:
		_settings.current_fuel = new_fuel

	# Reignite the engine if previously dead and we just got refueled
	if new_fuel > 0.0 and fuel_timer.is_stopped():
		fuel_timer.start()
		rotor_start(rotor_right, rotor_right_sfx)
		rotor_start(rotor_left, rotor_left_sfx)
		Globals.log_message(
			"Engine reignited! Rotors and fuel consumption resumed.", Globals.LogLevel.INFO
		)


## NEW: Centralized helper to clamp speed and emit state changes.
## Resolves PR duplication feedback.
func _set_speed(target_speed: float) -> void:
	# If out of fuel, drop min_speed so the setter allows clamping to 0.0
	if fuel_resource.current_fuel <= 0.0:
		speed_resource.min_speed = 0.0
	elif is_instance_valid(_settings):
		# Restore standard min_speed when fueled
		speed_resource.min_speed = _settings.min_speed

	# Assignment automatically triggers clamping and observers inside SpeedResource
	speed_resource.current_speed = target_speed


## Signal handler for engine failure triggered by the global fuel_depleted signal.
## Stops the plane, halts rotors, and broadcasts the flameout state.
## @return: void
func _on_player_out_of_fuel() -> void:
	Globals.log_message("Player is out of fuel! Engine flameout.", Globals.LogLevel.WARNING)

	_set_speed(0.0)

	rotor_stop(rotor_right, rotor_right_sfx)
	rotor_stop(rotor_left, rotor_left_sfx)
	fuel_timer.stop()


## Captures core input events for the player, specifically weapon firing and swapping.
## @param event: The input event detected by the engine.
## @return: void
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("fire"):
		if weapon and weapon.has_method("fire"):
			weapon.fire()
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("next_weapon"):
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
	if rotor_sfx != null:
		rotor_sfx.stop()


## Timer callback triggered every tick of the fuel timer.
## Calculates dynamic fuel consumption based on current speed and game difficulty.
## @return: void
func _on_fuel_timer_timeout() -> void:
	if not is_instance_valid(_settings):
		return

	var normalized_speed: float = clamp(
		speed_resource.current_speed / speed_resource.max_speed, 0.0, 1.0
	)
	var consumption: float = (
		fuel_resource.base_consumption_rate * normalized_speed * _settings.difficulty
	)
	fuel_resource.current_fuel -= consumption


## The main physics loop for the player.
## Handles forward acceleration/deceleration, lateral movement, boundary constraints,
## and broadcasts speed state changes to external observers.
## @param _delta: The time elapsed since the last physics frame.
## @return: void
func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_settings):
		return

	var target_speed: float = speed_resource.current_speed

	# Speed changes allowed only if fuel > 0
	if Input.is_action_pressed("speed_up") and fuel_resource.current_fuel > 0:
		target_speed += speed_resource.acceleration * _delta

	if Input.is_action_pressed("speed_down") and fuel_resource.current_fuel > 0:
		target_speed -= speed_resource.deceleration * _delta

	# Let the helper handle clamping and signal emission
	_set_speed(target_speed)

	# Left/Right movement
	var lateral_input: float = Input.get_axis("move_left", "move_right")

	if lateral_input and fuel_resource.current_fuel > 0 and speed_resource.current_speed > 0:
		player.velocity.x = lateral_input * speed_resource.lateral_speed
	else:
		player.velocity.x = 0.0

	# Clamp player position within boundaries
	player.position.x = clamp(player.position.x, player_x_min, player_x_max)
	player.position.y = clamp(player.position.y, player_y_min, player_y_max)

	player.move_and_slide()


## Guarded compatibility listener for legacy external fuel mutations.
## Ensures that if legacy code or tests modify Globals.settings directly,
## the authoritative FuelResource stays in sync.
## @param setting_name: The name of the modified setting.
## @param new_value: The updated value.
## @return: void
func _on_setting_changed(setting_name: String, new_value: Variant) -> void:
	if setting_name == "current_fuel" and fuel_resource.current_fuel != float(new_value):
		fuel_resource.current_fuel = float(new_value)
