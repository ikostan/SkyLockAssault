extends Node2D

# Fuel color thresholds (percentages)
const HIGH_FUEL_THRESHOLD: float = 90.0  # Starts green lerp
const MEDIUM_FUEL_THRESHOLD: float = 50.0  # Switches to yellow lerp
const LOW_FUEL_THRESHOLD: float = 30.0  # Switches to red lerp
const NO_FUEL_THRESHOLD: float = 15.0  # Fully Red Color

# Exported vars first (for Inspector editing)
@export var speed: float = 250.0
@export var max_fuel: float = 100.0
var current_fuel: float

# Regular vars for computed boundaries (no export needed if set in code)
var player_half_width: float = 0.0
var player_half_height: float = 0.0
var player_x_min: float = 0.0
var player_x_max: float = 0.0
var player_y_min: float = 0.0
var player_y_max: float = 0.0
# For gradual colors shifts (e.g., green to red as fuel drops), use Color.lerp
var lerp_factor: float

# Weapon system
var weapons: Array[Node] = []  # Fill in editor or _ready
var current_weapon: int = 0

# Onreadys next
@onready var player: CharacterBody2D = $CharacterBody2D
@onready var collision_shape: CollisionShape2D = $CharacterBody2D/CollisionShape2D
@onready
var fuel_bar: ProgressBar = $"../PlayerStatsPanel/VBoxContainer/HBoxContainer/FuelProgressBar"
@onready var fuel_timer: Timer = $FuelTimer
# Get the fill style
@onready var fill_style: StyleBoxFlat = fuel_bar.get_theme_stylebox("fill")
# Cached initial fill color
@onready var progress_bar_bg_color: Color = fill_style.bg_color


func _ready() -> void:
	# Dynamically calculate half-sizes (use both extents for width/height; assumes RectangleShape2D)
	if collision_shape.shape is RectangleShape2D:
		player_half_width = collision_shape.shape.extents.x * abs(collision_shape.scale.x)
		player_half_height = collision_shape.shape.extents.y * abs(collision_shape.scale.y)
	else:
		Globals.log_message(
			"Warning: Using fallback size—check collision shape type.", Globals.LogLevel.WARNING
		)
		player_half_width = 12.0  # Default guess; adjust based on your sprite
		player_half_height = 12.0

	# Set screen boundaries (assuming centered origin; tweak if top-left)
	var screen_size: Vector2 = get_viewport_rect().size
	player_x_min = (screen_size.x * -0.5) + (player_half_width * 2)
	player_x_max = (screen_size.x * 0.5) - (player_half_width * 2)
	player_y_min = (screen_size.y * -0.83) + player_half_height
	player_y_max = screen_size.y / 7

	# One-time debug log (avoid per-frame spam)
	Globals.log_message(
		(
			"Player boundaries set: x("
			+ str(player_x_min)
			+ ", "
			+ str(player_x_max)
			+ "), y("
			+ str(player_y_min)
			+ ", "
			+ str(player_y_max)
			+ ")"
		),
		Globals.LogLevel.DEBUG
	)

	current_fuel = max_fuel
	fuel_bar.value = current_fuel
	fuel_timer.timeout.connect(_on_fuel_timer_timeout)
	fuel_timer.start()
	# Assumes child named "Weapon"; use get_node("Path/To/Weapon") if nested
	weapons.append($CharacterBody2D/Weapon)


# Choose a diferent weapon
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("next_weapon"):
		current_weapon = (current_weapon + 1) % weapons.size()
		for i in range(weapons.size()):
			weapons[i].visible = (i == current_weapon)


# Connect Timer's timeout signal
func _on_fuel_timer_timeout() -> void:
	var fuel_left: float = current_fuel - (0.5 * Globals.difficulty)  # Scale base rate
	# Add a clamp so current_fuel never drops below zero
	# to prevent negative values and any unintended behavior in the fuel bar.
	current_fuel = clamp(fuel_left, 0, max_fuel)
	fuel_bar.value = current_fuel
	lerp_factor = 1.0 - (current_fuel / max_fuel)  # 0=full (green), 1=empty (red)
	progress_bar_bg_color = fill_style.bg_color

	if current_fuel >= MEDIUM_FUEL_THRESHOLD and current_fuel <= HIGH_FUEL_THRESHOLD:
		fill_style.bg_color = progress_bar_bg_color.lerp(Color.GREEN, lerp_factor)
	elif LOW_FUEL_THRESHOLD <= current_fuel and current_fuel < MEDIUM_FUEL_THRESHOLD:
		fill_style.bg_color = progress_bar_bg_color.lerp(Color.YELLOW, lerp_factor)  # Medium-high: green
	elif current_fuel > NO_FUEL_THRESHOLD and current_fuel < LOW_FUEL_THRESHOLD:
		fill_style.bg_color = progress_bar_bg_color.lerp(Color.RED, lerp_factor)  # Medium-low: yellow
	elif current_fuel <= NO_FUEL_THRESHOLD:
		fill_style.bg_color = Color.RED  # Low: red

	if current_fuel <= 0:
		speed = 0.0  # Or game over logic
		fuel_timer.stop()
	Globals.log_message("Fuel left: " + str(current_fuel), Globals.LogLevel.INFO)


# warning-ignore:unused_parameter
func _physics_process(_delta: float) -> void:
	var direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_backward", "move_forward"
	)
	if direction != Vector2.ZERO:
		player.velocity = direction * speed
	else:
		player.velocity = Vector2.ZERO
	player.move_and_slide()

	# Get fresh screen_size each frame (handles resizes)
	var screen_size: Vector2 = get_viewport_rect().size

	# Clamp position (recompute mins/maxes if screen_size changes, or keep as-is for performance)
	player.position.x = clamp(player.position.x, player_x_min, player_x_max)
	player.position.y = clamp(player.position.y, player_y_min, player_y_max)

	# Optional per-frame log (comment out unless debugging; it's spammy)
	#Globals.log_message("Player positioned at: " + str(player.position), Globals.LogLevel.DEBUG)
	Globals.log_message(
		"Root global: " + str(global_position) + ", Child global: " + str(player.global_position),
		Globals.LogLevel.DEBUG
	)
