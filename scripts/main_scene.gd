extends Node2D  # Assuming Node2D root; change if different

@onready var player: Node2D = $Player
@onready var stats_panel: Panel = $PlayerStatsPanel


func _ready() -> void:
	# Get viewport dimensions (dynamic for web/resizes)
	var viewport_size: Vector2 = get_viewport_rect().size
	# Example: Place at center-bottom
	player.position = Vector2(viewport_size.x / 2, viewport_size.y / 1.2)
	stats_panel.visible = true
	Globals.log_message("Initializing main scene...", Globals.LogLevel.INFO)
