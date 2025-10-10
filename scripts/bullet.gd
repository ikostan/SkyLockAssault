extends RigidBody2D

@export var speed: float = 800.0
@export var lifetime: float = 5.0
@export var damage: int = 10

@onready var area: Area2D = $Area2D  # Reference to the Area2D node

func _ready() -> void:
	linear_velocity = Vector2(speed, 0).rotated(global_rotation)  # Fire in weapon's direction
	if area:
		area.connect("area_entered", _on_hit)  # Connect signal only if Area2D exists
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _on_hit(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
