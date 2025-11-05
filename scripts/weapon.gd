extends Node2D

@export var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
@export var fire_rate: float = 0.5  # Seconds between shots
@export var muzzle_offset: Vector2 = Vector2(0, -25)  # Fixed up; adjust based on plane size

var can_fire: bool = true
var timer: Timer


func _ready() -> void:
	timer = Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(_on_can_fire)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("fire") and can_fire:
		_fire()


func _fire() -> void:
	can_fire = false
	# New: Scale cooldown with difficulty (longer wait if >1.0)
	var scaled_rate: float = fire_rate * Globals.difficulty
	timer.start(scaled_rate)
	Globals.log_message("Firing with scaled cooldown: " + str(scaled_rate), Globals.LogLevel.DEBUG)

	var bullet := bullet_scene.instantiate()
	bullet.add_to_group("bullets")
	# Updated: Use root instead of current_scene for reliability in tests/CI
	get_tree().root.add_child(bullet)
	bullet.global_position = global_position + muzzle_offset  # Fixed offset, no rotate
	bullet.global_rotation = -PI / 2  # Point bullet up if sprite needs it
	bullet.shot_sfx.play()
	Globals.log_message(
		"Firing bullet from weapon global: " + str(global_position), Globals.LogLevel.DEBUG
	)


func _on_can_fire() -> void:
	can_fire = true
