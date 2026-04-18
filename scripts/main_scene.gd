## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## main_scene.gd
## Main scene script for SkyLockAssault.
## Handles player positioning, stats visibility, and parallax background setup.

class_name MainScene
extends Node2D

enum MessageType { CRITICAL_UNBOUND, KEY_PRESS_UNBOUND }

# At the top of main_scene.gd
@export var parallax_screens_tall: float = 8.0

var _showing_unbound_warning: bool = false
var _showing_unbound_key_message: bool = false

@onready var player: Node2D = $Player
@onready var stats_panel: Panel = $PlayerStatsPanel
@onready var background: ParallaxBackground = $Background
@onready var bushes_layer: ParallaxLayer = $Background/Bushes  # Reference to the bushes layer
@onready var decor_layer: ParallaxLayer = $Background/Decor  # Reference to the decor layer
@onready var texture_preloader: ResourcePreloader = $ResourcePreloader  # Reference to preloader
@onready var hud: CanvasLayer = $HUD
@onready var message_label: Label = $HUD/MessageLabel


func _ready() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	print("Viewport size: ", viewport_size)  # Debug output
	player.position = Vector2(viewport_size.x / 2, viewport_size.y / 1.2)
	stats_panel.visible = true
	Globals.log_message("Initializing main scene...", Globals.LogLevel.DEBUG)

	# =========================================================
	# THIS IS THE MISSING LINK THAT WAKES UP YOUR HUD!
	# It passes the Player directly to the HUD script so the bars work.
	# =========================================================
	if stats_panel.has_method("setup_hud"):
		stats_panel.setup_hud(player)
	else:
		push_error(
			"HUD Script is missing! Make sure 'hud.gd' is attached to the 'PlayerStatsPanel' node."
		)

	# Setup ground layer with tiling
	setup_parallax_layer($Background/Sand/Sprite2D, viewport_size, 2.0)  # Sand layer

	# Setup bushes layer with random instances
	setup_bushes_layer(viewport_size)

	# Setup decor layer with random instances
	setup_decor_layer(viewport_size)

	# =========================================================
	# DEPENDENCY INJECTION: Parallax Background
	# =========================================================
	# Wire up the signal architecture for the parallax background
	# Safely extract settings once to use for both injection and priming
	# Note: Because background.setup(settings_res) already has its own internal
	# if not is_instance_valid(settings): return check, this is perfectly safe
	var settings_res: GameSettingsResource = Globals.settings

	if background.has_method("setup"):
		background.setup(settings_res)
	else:
		push_warning(
			"Parallax background is missing the `setup` method. Settings injection failed."
		)

	# Wire up the signal architecture for the parallax background
	if player.has_signal("speed_changed") and background.has_method("_on_player_speed_changed"):
		# 1. Guard against duplicate connections
		if not player.speed_changed.is_connected(background._on_player_speed_changed):
			player.speed_changed.connect(background._on_player_speed_changed)

		# 2. Prime the background securely via a public method
		if background.has_method("prime_speed"):
			background.prime_speed(player.speed["speed"])
		else:
			push_warning("Parallax background is missing the `prime_speed` method.")

	elif not player.has_signal("speed_changed"):
		push_warning(
			(
				"Parallax background not wired: player is missing the `speed_changed` signal. "
				+ "Verify that the Player node defines and emits `speed_changed`."
			)
		)
	elif not background.has_method("_on_player_speed_changed"):
		push_warning(
			(
				"Parallax background not wired: background is missing"
				+ " `_on_player_speed_changed` method. "
				+ "Ensure the background script implements "
				+ " `_on_player_speed_changed(speed: float, delta: float)`."
			)
		)


# 2. Detect when player presses a key/button that has NO binding at all
# Only significant inputs (axes above deadzone) are checked to prevent
# false positives from stick jitter.
func _input(event: InputEvent) -> void:
	if event.is_echo():
		return

	if not (
		event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion
	):
		return

	# ────────────────────────────────────────────────────────────────
	# Ignore tiny axis movements (perpendicular stick noise when
	# you use split-stick mapping, e.g. Left Stick X + Right Stick Y).
	# We use the exact same threshold that the remap buttons use.
	# Matches AXIS_DEADZONE_THRESHOLD from input_remap_button.gd.
	# ────────────────────────────────────────────────────────────────
	if (
		event is InputEventJoypadMotion
		and abs(event.axis_value) < InputRemapButton.AXIS_DEADZONE_THRESHOLD
	):
		return

	# Player pressed a completely unbound key/button/axis
	if not Settings.is_event_bound(event) and not _showing_unbound_key_message:
		_showing_unbound_key_message = true
		var device_type: String = Settings.get_event_device_type(event)
		var pause_label: String = Settings.get_pause_binding_label_for_device(device_type)
		show_message(
			"{UNBOUND=KEY=PRESSED}\n{PRESS='" + pause_label + "'=AND=GO=TO='CONTROLS'=TO=FIX}",
			MessageType.KEY_PRESS_UNBOUND  # explicit
		)


## Sets up a parallax layer for tiling and mirroring.
## @param sprite: Sprite2D - The Sprite2D to configure.
## @param viewport: Vector2 - The viewport size.
## @param buffer_mult: float - Multiplier for vertical buffer.
## @return: void
func setup_parallax_layer(sprite: Sprite2D, viewport: Vector2, buffer_mult: float = 1.0) -> void:
	if not sprite or not sprite.texture:
		return

	var tex_size: Vector2 = sprite.texture.get_size()
	var tiles_x: int = ceil(viewport.x / tex_size.x)
	var tiles_y: int = ceil(viewport.y / tex_size.y) * int(buffer_mult)

	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, tiles_x * tex_size.x, tiles_y * tex_size.y)
	sprite.centered = false
	sprite.position = Vector2(0, 0)

	var layer: ParallaxLayer = sprite.get_parent()
	layer.motion_scale = Vector2(1, 0.5)
	layer.motion_mirroring = Vector2(0, tiles_y * tex_size.y)


## Sets up the bushes layer with random X positions, sizes, and textures.
## @param viewport: Vector2 - The viewport size.
## @return: void
func setup_bushes_layer(viewport: Vector2) -> void:
	if not bushes_layer:
		return

	# Clear existing children (Safely detach first, then instantly destroy)
	for child in bushes_layer.get_children():
		bushes_layer.remove_child(child)
		child.free()

	# Get bush IDs from preloader (Array[String])
	var bush_ids: Array = Array(texture_preloader.get_resource_list()).filter(
		func(id: String) -> bool: return id.begins_with("bush_")
	)

	if bush_ids.is_empty():
		return

	# THE GOLDILOCKS ZONE:
	# 8 screens is the sweet spot for infinite illusion vs CPU overhead
	var layer_height: float = viewport.y * parallax_screens_tall

	# Drop density multiplier to match
	var num_bushes: int = bush_ids.size() * 2

	for i in range(num_bushes):
		var bush: Sprite2D = Sprite2D.new()
		var random_index: int = randi_range(0, bush_ids.size() - 1)
		var id: String = bush_ids[random_index]
		bush.texture = texture_preloader.get_resource(id)
		bush.centered = false

		var scale_factor: float = randf_range(0.5, 1.5)
		bush.scale = Vector2(scale_factor, scale_factor)

		bush.position.x = randf_range(0, viewport.x - (bush.texture.get_width() * scale_factor))
		bush.position.y = randf_range(0, layer_height - (bush.texture.get_height() * scale_factor))

		bushes_layer.add_child(bush)

	bushes_layer.motion_scale = Vector2(1, 0.5)
	bushes_layer.motion_mirroring = Vector2(0, layer_height)


## Sets up the decor layer with random X positions, sizes, textures, rotations, and flips.
## @param viewport: Vector2 - The viewport size.
## @return: void
func setup_decor_layer(viewport: Vector2) -> void:
	if not decor_layer:
		return

	# Clear existing children (Safely detach first, then instantly destroy)
	for child in decor_layer.get_children():
		decor_layer.remove_child(child)
		child.free()

	# Get decor IDs from preloader (Array[String])
	var decor_ids: Array = Array(texture_preloader.get_resource_list()).filter(
		func(id: String) -> bool: return id.begins_with("decor_")
	)

	if decor_ids.is_empty():
		return

	# THE GOLDILOCKS ZONE:
	# Match the bushes layer height
	var layer_height: float = viewport.y * parallax_screens_tall

	# Drop density multiplier to match
	var num_decors: int = decor_ids.size() * 2

	# Define strict rotation angles (0, 90, 180, -90 degrees)
	var allowed_rotations: Array[float] = [0.0, 90.0, 180.0, -90.0]

	for i in range(num_decors):
		var decor: Sprite2D = Sprite2D.new()
		var random_index: int = randi_range(0, decor_ids.size() - 1)
		var id: String = decor_ids[random_index]
		decor.texture = texture_preloader.get_resource(id)
		decor.centered = false

		# SCALING TRICK 1: Wider scale range (0.5 to 1.5) for more size variance
		var scale_factor: float = randf_range(0.5, 1.5)
		decor.scale = Vector2(scale_factor, scale_factor)

		# SCALING TRICK 2: Randomly mirror the sprite horizontally and/or vertically
		decor.flip_h = randf() < 0.5
		decor.flip_v = randf() < 0.5

		# Apply random cardinal rotation to ALL decor sprites
		var random_degrees: float = allowed_rotations.pick_random()
		decor.rotation = deg_to_rad(random_degrees)

		decor.position.x = randf_range(0, viewport.x - (decor.texture.get_width() * scale_factor))
		decor.position.y = randf_range(
			0, layer_height - (decor.texture.get_height() * scale_factor)
		)

		decor_layer.add_child(decor)

	decor_layer.motion_scale = Vector2(1, 0.5)
	decor_layer.motion_mirroring = Vector2(0, layer_height)


func _process(_delta: float) -> void:
	# Safely grab the settings resource and guard against null crashes
	# during scene transitions, engine shutdown, or isolated GUT tests.
	var settings_res: GameSettingsResource = Globals.settings

	if not is_instance_valid(settings_res):
		return

	# 1. Critical unbound controls warning (shown ONCE per session)
	# Flag stays true until player fixes bindings (e.g., in key_mapping.gd after remap).
	# Do NOT reset here — that would make it repeat every 4s (bug fixed).
	if Settings.has_unbound_critical_actions_for_current_device() and not _showing_unbound_warning:
		_showing_unbound_warning = true
		var pause_key: String = Settings.get_pause_binding_label()
		show_message(
			"{SOME=CONTROLS=ARE=UNBOUND}\n{PRESS='" + pause_key + "'=AND=GO=TO='CONTROLS'=TO=FIX}",
			MessageType.CRITICAL_UNBOUND  # explicit
		)


## Shows a temporary on-screen message (non-blocking).
## Centralizes timer + flag reset to prevent races.
## :param text: Message to display.
## :param type: Which flag to manage (defaults to CRITICAL for backward compat).
## :type type: MessageType
## :rtype: void
func show_message(text: String, type: MessageType = MessageType.CRITICAL_UNBOUND) -> void:
	if not is_instance_valid(message_label):
		return

	message_label.text = text
	message_label.visible = true

	# Auto-hide after 4 seconds and reset the *correct* flag
	await get_tree().create_timer(4.0).timeout
	if is_instance_valid(message_label):
		message_label.visible = false

	# Reset the right flag based on message type
	match type:
		MessageType.KEY_PRESS_UNBOUND:
			_showing_unbound_key_message = false


## Public: Clears the unbound warning flag after fixes.
func clear_unbound_warning() -> void:
	_showing_unbound_warning = false
