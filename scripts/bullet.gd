# bullet.gd - UPDATED: Extra debug for script load + fire confirm
extends Node2D

# Seconds between shots – adjust for balance (learning: lower = faster fire)
@export var fire_rate: float = 0.15
# Spawn offset from plane – tweak for visuals
@export var muzzle_offset: Vector2 = Vector2(0, -25)
@export var projectile_speed: float = 400.0  # Bullet speed – higher = faster travel
@export var projectile_lifetime: float = 5.0  # Auto-destroy time – prevents memory leak
@export var damage: int = 10  # Damage on hit – for enemy take_damage()
@export var projectile_texture: Texture2D  # Drag PNG in Inspector – fallback icon if empty
@export var shot_sound: AudioStream  # Drag MP3/OGG – fallback retro-laser

var can_fire: bool = true
var timer: Timer
# Child node for sound – must exist in scene
@onready var shot_sfx: AudioStreamPlayer2D = $ShotSFX


func _ready() -> void:
	Globals.log_message(
		"*** BulletFirer _ready: Script LOADED! Name: " + name + " ShotSFX: " + str(shot_sfx),
		Globals.LogLevel.DEBUG
	)  # NEW: Confirm script runs on instantiate
	if not projectile_texture:
		# Godot icon fallback – visible small dot for testing
		projectile_texture = preload("res://icon.svg")
		push_warning(name + ": No texture; using fallback.")
	if not shot_sound:
		# Fallback sound – download free SFX if missing
		shot_sound = preload("res://files/sounds/sfx/retro-laser-1-236669.mp3")
		push_warning(name + ": Default sound.")

	# Polyphonic sound – allows overlaps for rapid fire (Godot learning: prevents audio cutoff)
	var poly: AudioStreamPolyphonic = AudioStreamPolyphonic.new()
	poly.polyphony = 12  # Max simultaneous sounds – adjust for performance
	if shot_sfx:
		shot_sfx.stream = poly
		# NEW: Start the player to activate polyphonic playback
		shot_sfx.play()
	else:
		push_error("ShotSFX missing! Add AudioStreamPlayer2D child named 'ShotSFX' in bullet.tscn.")

	timer = Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.name = "CooldownTimer"  # NEW: Named for tests (no perf hit)
	timer.timeout.connect(func() -> void: can_fire = true)  # Cooldown reset


func fire() -> void:
	Globals.log_message(
		"*** BulletFirer.fire(): Called! can_fire: " + str(can_fire), Globals.LogLevel.DEBUG
	)  # NEW: Confirm method exists/runs
	if not can_fire:
		return
	can_fire = false
	timer.start(fire_rate * Globals.difficulty)

	spawn_projectile()  # Spawns bullet – programmatic (no extra scene = efficient)

	if shot_sfx:
		var playback: AudioStreamPlaybackPolyphonic = shot_sfx.get_stream_playback()
		if playback:
			playback.play_stream(shot_sound)
			Globals.log_message(
				"Bullet weapon fired (sound: " + shot_sound.resource_path.get_file() + ")",
				Globals.LogLevel.DEBUG
			)
		else:
			push_warning("Polyphonic playback null—ensure shot_sfx.play() was called!")


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
