extends Node2D  # Assuming Node2D root; change if different

@onready var player: Node2D = $Player

func _ready() -> void:
	# Get viewport dimensions (dynamic for web/resizes)
	var viewport_size: Vector2 = get_viewport_rect().size
	
	# Example: Place at center
	player.position = Vector2(viewport_size.x / 2, viewport_size.y / 1.2)
	
	# Alternative: Bottom-center (e.g., starting position for top-down assault)
	# player.position = Vector2(viewport_size.x / 2, viewport_size.y - 100)  # 100px from bottom
	
	# Alternative: Specific spot, like bottom-left with offset
	# player.position = Vector2(100, viewport_size.y - 100)  # 100px from bottom-left
	
	Globals.log_message("Player positioned at: " + str(player.position), Globals.LogLevel.DEBUG)
