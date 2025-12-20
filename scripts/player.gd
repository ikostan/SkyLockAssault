extends Node2D

## Player controller for P-38 Lightning in SkyLockAssault.
## Manages movement, fuel, bounds, rotors (anim/sound), weapons.

# Fuel color thresholds (percentages)
const HIGH_FUEL_THRESHOLD: float = 90.0  # Starts green lerp
const MEDIUM_FUEL_THRESHOLD: float = 50.0  # Switches to yellow lerp
const LOW_FUEL_THRESHOLD: float = 30.0  # Switches to red lerp
const NO_FUEL_THRESHOLD: float = 15.0  # Fully Red Color
# Bounds hitbox scale (quarter texture = tight margin for top-down plane)
const HITBOX_SCALE: float = 0.25

# Exported vars first (for Inspector editing)
@export var speed: float = 250.0
@export var max_fuel: float = 100.0
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

# Onreadys next
@onready var rotor_right: Node2D = $CharacterBody2D/RotorRight
@onready var rotor_left: Node2D = $CharacterBody2D/RotorLeft
@onready var player: CharacterBody2D = $CharacterBody2D
@onready var player_sprite: Sprite2D = $CharacterBody2D/Sprite2D
@onready var collision_shape: CollisionPolygon2D = $CharacterBody2D/CollisionPolygon2D
@onready
var fuel_bar: ProgressBar = $"../PlayerStatsPanel/VBoxContainer/HBoxContainer/FuelProgressBar"
@onready var fuel_timer: Timer = $FuelTimer
# Get the fill style
@onready var fill_style: StyleBoxFlat = fuel_bar.get_theme_stylebox("fill")
# In plane.gd (or main player script) - central input
@onready var weapon: Node2D = $CharacterBody2D/Weapon  # Path to your WeaponManager node


func _ready() -> void:
	# Auto-start rotors (overrides editor if needed)
	rotor_right.get_node("AnimatedSprite2D").play("default")
	rotor_left.get_node("AnimatedSprite2D").play("default")
	Globals.log_message("Rotors AUTO-STARTED at 24 FPS!", Globals.LogLevel.DEBUG)

	rotor_left_sfx = rotor_left.get_node("AudioStreamPlayer2D")
	rotor_right_sfx = rotor_right.get_node("AudioStreamPlayer2D")

	if rotor_left_sfx:
		rotor_left_sfx.bus = "SFX_Rotor_Left"
		rotor_left_sfx.play()
		Globals.log_message("Twin rotors: LEFT stereo PAN active!", Globals.LogLevel.DEBUG)
	else:
		Globals.log_message("No left rotor SFX found", Globals.LogLevel.DEBUG)

	if rotor_right_sfx:
		rotor_right_sfx.bus = "SFX_Rotor_Right"
		rotor_right_sfx.play()
		Globals.log_message("Twin rotors: RIGHT stereo PAN active!", Globals.LogLevel.DEBUG)
	else:
		Globals.log_message("No right rotor SFX found", Globals.LogLevel.DEBUG)

	# Set screen boundaries (safe null check + fallback)
	screen_size = get_viewport_rect().size  # Dynamic for web/resizes

	var sprite_size: Vector2 = Vector2(174.0, 132.0)  # Fallback if texture missing
	if player_sprite.texture != null:
		sprite_size = player_sprite.texture.get_size()
		Globals.log_message("Player sprite size: " + str(sprite_size), Globals.LogLevel.DEBUG)
	else:
		push_warning("Player sprite texture missing! Using fallback size: " + str(sprite_size))

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

	# Initialize fuel
	current_fuel = max_fuel
	fuel_bar.max_value = max_fuel
	update_fuel_bar()  # Set initial UI and color
	fuel_timer.timeout.connect(_on_fuel_timer_timeout)
	fuel_timer.start()

	# Null-safe weapon log
	if weapon:
		Globals.log_message(
			"Player ready. Weapons loaded: " + str(weapon.weapon_types.size()),
			Globals.LogLevel.DEBUG
		)
	else:
		push_error("Weapon node not found! Check player.tscn scene tree for $Weapon child.")


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


func update_fuel_bar() -> void:
	fuel_bar.value = current_fuel
	var fuel_percent: float = (current_fuel / max_fuel) * 100.0

	if fuel_percent > HIGH_FUEL_THRESHOLD:
		fill_style.bg_color = Color.GREEN  # Full green for high fuel
	elif fuel_percent >= MEDIUM_FUEL_THRESHOLD:
		# Lerp green to yellow (factor 0 at 90%, 1 at 50%)
		var section_factor: float = (
			(HIGH_FUEL_THRESHOLD - fuel_percent) / (HIGH_FUEL_THRESHOLD - MEDIUM_FUEL_THRESHOLD)
		)
		fill_style.bg_color = Color.GREEN.lerp(Color.YELLOW, section_factor)
	elif fuel_percent >= LOW_FUEL_THRESHOLD:
		# Lerp yellow to red
		var section_factor: float = (
			(MEDIUM_FUEL_THRESHOLD - fuel_percent) / (MEDIUM_FUEL_THRESHOLD - LOW_FUEL_THRESHOLD)
		)
		fill_style.bg_color = Color.YELLOW.lerp(Color.RED, section_factor)
	elif fuel_percent > NO_FUEL_THRESHOLD:
		# Lerp red to darker or full red
		var section_factor: float = (
			(LOW_FUEL_THRESHOLD - fuel_percent) / (LOW_FUEL_THRESHOLD - NO_FUEL_THRESHOLD)
		)
		fill_style.bg_color = Color.RED.lerp(Color(0.5, 0, 0), section_factor)  # Example to dark red
	else:
		fill_style.bg_color = Color.RED  # Full red


# Connect Timer's timeout signal
func _on_fuel_timer_timeout() -> void:
	# Scale base rate
	var fuel_left: float = current_fuel - (0.5 * Globals.difficulty)
	# Clamp and update current_fuel first
	current_fuel = clamp(fuel_left, 0, max_fuel)
	# Update UI from the clamped value
	update_fuel_bar()

	if current_fuel <= 0:
		speed = 0.0  # Or game over logic
		fuel_timer.stop()
	Globals.log_message("Fuel left: " + str(current_fuel), Globals.LogLevel.DEBUG)


func _physics_process(_delta: float) -> void:
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "speed_up", "speed_down")
	if direction != Vector2.ZERO:
		player.velocity = direction * speed
	else:
		player.velocity = Vector2.ZERO
	player.move_and_slide()

	player.position.x = clamp(player.position.x, player_x_min, player_x_max)
	player.position.y = clamp(player.position.y, player_y_min, player_y_max)
