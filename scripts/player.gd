extends Node2D

# Exported vars first (for Inspector editing)
@export var speed: float = 300.0
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
var progress_bar_bg_color: Color

# Onreadys next
@onready var player: CharacterBody2D = $CharacterBody2D
@onready var collision_shape: CollisionShape2D = $CharacterBody2D/CollisionShape2D
@onready
var fuel_bar: ProgressBar = $"../PlayerStatsPanel/VBoxContainer/HBoxContainer/FuelProgressBar"
@onready var fuel_timer: Timer = $FuelTimer
# Get the fill style (assume it's StyleBoxFlat; if not, create one first in _ready)
@onready var fill_style: StyleBoxFlat = fuel_bar.get_theme_stylebox("fill") as StyleBoxFlat


func _ready() -> void:
	# Dynamically calculate half-sizes (use both extents for width/height; assumes RectangleShape2D)
	if collision_shape.shape is RectangleShape2D:
		player_half_width = collision_shape.shape.extents.x * abs(collision_shape.scale.x)
		player_half_height = collision_shape.shape.extents.y * abs(collision_shape.scale.y)
	else:
		print("Warning: Using fallback size—check collision shape type.")
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

	progress_bar_bg_color = fill_style.bg_color
	current_fuel = max_fuel
	fuel_bar.value = current_fuel
	fuel_timer.timeout.connect(_on_fuel_timer_timeout)
	fuel_timer.start()


# Connect Timer's timeout signal
func _on_fuel_timer_timeout() -> void:
	current_fuel -= 0.5
	fuel_bar.value = current_fuel
	lerp_factor = 1.0 - (current_fuel / 100.0)  # 0=full (green), 1=empty (red)

	if current_fuel >= 80.0:
		fill_style.bg_color = progress_bar_bg_color.lerp(Color.GREEN, lerp_factor)
	elif 60.0 <= current_fuel and current_fuel < 80.0:
		fill_style.bg_color = Color.GREEN.lerp(Color.YELLOW, lerp_factor)  # Medium-high: green
	elif current_fuel >= 30.0 and current_fuel < 60.0:
		fill_style.bg_color = Color.YELLOW.lerp(Color.RED, lerp_factor)  # Medium-low: yellow
	elif current_fuel < 30.0:
		fill_style.bg_color = Color.RED  # Low: red

	if current_fuel <= 0:
		speed = 0.0  # Or game over logic
		fuel_timer.stop()
	Globals.log_message("Fuel left: " + str(current_fuel), Globals.LogLevel.DEBUG)


# warning-ignore:unused_parameter
func _physics_process(_delta: float) -> void:
	var direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_backward", "move_forward"
	)
	if direction != Vector2.ZERO:
		player.velocity = direction * speed
		# Optional: Add rotation for facing (uncomment for top-down airplane feel)
		# player.rotation = direction.angle()
	else:
		player.velocity = Vector2.ZERO
	player.move_and_slide()

	# Get fresh screen_size each frame (handles resizes)
	var screen_size: Vector2 = get_viewport_rect().size

	# Clamp position (recompute mins/maxes if screen_size changes, or keep as-is for performance)
	player.position.x = clamp(player.position.x, player_x_min, player_x_max)
	player.position.y = clamp(player.position.y, player_y_min, player_y_max)

	# Optional per-frame log (comment out unless debugging; it's spammy)
	# Globals.log_message("Player positioned at: " + str(player.position), Globals.LogLevel.DEBUG)
