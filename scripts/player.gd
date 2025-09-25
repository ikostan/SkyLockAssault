extends Node2D

# Exported vars first (for Inspector editing)
@export var speed: float = 300.0

# Regular vars for computed boundaries (no export needed if set in code)
var player_half_width: float = 0.0
var player_half_height: float = 0.0
var player_x_min: float = 0.0
var player_x_max: float = 0.0
var player_y_min: float = 0.0
var player_y_max: float = 0.0

# Onreadys next
@onready var player: CharacterBody2D = $CharacterBody2D
@onready var collision_shape: CollisionShape2D = $CharacterBody2D/CollisionShape2D


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
	Globals.log_message("Player positioned at: " + str(player.position), Globals.LogLevel.DEBUG)
