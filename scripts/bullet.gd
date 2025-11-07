# bullet.gd - FIXED for Web SFX Volume Control
extends Node2D

@export var fire_rate: float = 0.15
@export var muzzle_offset: Vector2 = Vector2(0, -25)
@export var projectile_speed: float = 400.0
@export var projectile_lifetime: float = 5.0
@export var damage: int = 10
@export var projectile_texture: Texture2D
@export var shot_sound: AudioStream  # Assign in Inspector

var can_fire: bool = true
var timer: Timer


# NO @onready for ShotSFX — we’ll create players dynamically
func _ready() -> void:
	Globals.log_message("BulletFirer _ready: Script loaded.", Globals.LogLevel.DEBUG)

	if not projectile_texture:
		projectile_texture = preload("res://icon.svg")
		push_warning(name + ": No texture; using fallback.")
	if not shot_sound:
		shot_sound = preload("res://files/sounds/sfx/retro-laser-1-236669.mp3")
		push_warning(name + ": No sound; using fallback.")

	timer = Timer.new()
	timer.one_shot = true
	timer.name = "CooldownTimer"
	add_child(timer)
	timer.timeout.connect(_reset_can_fire)


func _reset_can_fire() -> void:
	can_fire = true


func fire() -> void:
	if not can_fire:
		return
	can_fire = false

	var scaled_cooldown: float = fire_rate * Globals.difficulty
	timer.start(scaled_cooldown)

	# LOG
	Globals.log_message(
		"Firing with scaled cooldown: " + str(scaled_cooldown), Globals.LogLevel.DEBUG
	)

	spawn_projectile()
	play_sfx_with_volume()


# NEW: Play SFX with correct bus + volume scaling
func play_sfx_with_volume() -> void:
	if not shot_sound:
		return

	var sfx_player := AudioStreamPlayer2D.new()
	sfx_player.stream = shot_sound
	sfx_player.bus = "SFX"  # Critical: assign to SFX bus
	sfx_player.volume_db = 0.0  # Base volume (will be scaled by bus)

	# Add to root to avoid being freed with bullet
	get_tree().root.add_child(sfx_player)

	# Play and auto-cleanup
	sfx_player.play()
	sfx_player.finished.connect(func() -> void: sfx_player.queue_free())

	Globals.log_message("SFX played on Web with bus volume control.", Globals.LogLevel.DEBUG)


func spawn_projectile() -> void:
	var proj: RigidBody2D = RigidBody2D.new()  # Projectile body – physics for movement/collision
	proj.name = "BulletProjectile"
	proj.gravity_scale = 0.0  # No gravity – top-down space flight
	proj.linear_velocity = Vector2(0, -projectile_speed)  # Up velocity (negative y = up in Godot 2D)
	proj.global_position = global_position + muzzle_offset  # Spawn at muzzle
	proj.global_rotation = -PI / 2  # Rotate sprite up if needed

	# Collision detection – Area2D for hit events (learning: lighter than RigidBody collisions)
	var area: Area2D = Area2D.new()
	proj.add_child(area)
	area.area_entered.connect(
		func(body: Node2D) -> void:
			Globals.log_message("Projectile hit: " + body.name, Globals.LogLevel.DEBUG)
			if body.has_method("take_damage"):
				body.take_damage(damage)  # Apply damage to enemy
			proj.queue_free()  # Destroy on hit
	)

	# Sprite for visuals – drag texture in Inspector
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = projectile_texture
	sprite.scale = Vector2(0.5, 1.0)  # Scale for bullet size – tweak
	proj.add_child(sprite)

	# Collision shape – rectangle for bullet hitbox (learning: match sprite size)
	var collision: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(4, 12)  # Thin/tall – adjust for accuracy
	collision.shape = shape
	area.add_child(collision)

	get_tree().root.add_child(proj)  # Add to root – global for bullets
	proj.add_to_group("bullets")  # Group for cleanup/query (e.g., count bullets)

	# Timer destroy – prevents off-screen leaks (learning: memory management)
	get_tree().create_timer(projectile_lifetime).timeout.connect(func() -> void: proj.queue_free())
