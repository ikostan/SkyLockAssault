extends RigidBody2D

@export var speed: float = 400.0
@export var lifetime: float = 50.0
@export var damage: int = 10

@onready var area: Area2D = $Area2D

func _ready() -> void:
	gravity_scale = 0.0  # No gravity—constant upward speed
	linear_velocity = Vector2(0, -speed)
	if area:
		area.connect("area_entered", _on_hit)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	


func _on_hit(body: Node2D) -> void:
	Globals.log_message("Bullet hit: " + str(body.name), Globals.LogLevel.DEBUG)
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
