extends Node2D

@onready var player: CharacterBody2D = $CharacterBody2D
@export var speed: float = 300.0

# Add these for boundary offsets (adjust based on your sprite/collision size)
@onready var collision_shape: CollisionShape2D = $CharacterBody2D/CollisionShape2D
@onready var screen_size: Vector2 = get_viewport_rect().size
@export var player_size: float = 0.0
@export var player_x_min: float = 0.0
@export var player_x_max: float = 0.0
@export var player_y_min: float = 0.0
@export var player_y_max: float = 0.0


func _ready() -> void:
	# Set screen boundaries for the player movement
	player_size = collision_shape.shape.extents.x * abs(collision_shape.scale.x)
	player_x_min = ((screen_size.x * -1) / 2) + player_size + 6
	player_x_max = (screen_size.x / 2) - player_size - 8
	player_y_min = (screen_size.y * -0.83) + player_size
	player_y_max = screen_size.y / 7


func _physics_process(delta: float) -> void:
	var direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_backward", "move_forward"
	)
	if direction != Vector2.ZERO:
		player.velocity = direction * speed
	else:
		player.velocity = Vector2.ZERO
	player.move_and_slide()

	# Clamp position to screen boundaries after movement
	player.position.x = clamp(player.position.x, player_x_min, player_x_max)
	player.position.y = clamp(player.position.y, player_y_min, player_y_max)
	Globals.log_message("Player positioned at: " + str(player.position), Globals.LogLevel.DEBUG)
