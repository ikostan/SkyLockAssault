## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## main_scene.gd
## Main scene script for SkyLockAssault.
## Handles player positioning, stats visibility, and parallax background setup.

extends Node2D

var _showing_unbound_warning: bool = false
var _showing_unbound_key_message: bool = false
enum MessageType { CRITICAL_UNBOUND, KEY_PRESS_UNBOUND }

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

	# Setup ground layer with tiling
	setup_parallax_layer($Background/Sand/Sprite2D, viewport_size, 2.0)  # Sand layer

	# Setup bushes layer with random instances
	setup_bushes_layer(viewport_size)

	# Setup decor layer with random instances
	setup_decor_layer(viewport_size)


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

	# Clear existing children
	for child in bushes_layer.get_children():
		bushes_layer.remove_child(child)
		child.queue_free()

	# Get bush IDs from preloader (Array[String])
	var bush_ids: Array = Array(texture_preloader.get_resource_list()).filter(
		func(id: String) -> bool: return id.begins_with("bush_")
	)
	print("Loaded ", bush_ids.size(), " bush textures")

	if bush_ids.is_empty():
		return

	var num_bushes: int = bush_ids.size()
	var layer_height: float = viewport.y * 4

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


## Sets up the decor layer with random X positions, sizes, and textures.
## @param viewport: Vector2 - The viewport size.
## @return: void
func setup_decor_layer(viewport: Vector2) -> void:
	if not decor_layer:
		return

	# Clear existing children
	for child in decor_layer.get_children():
		decor_layer.remove_child(child)
		child.queue_free()

	# Get decor IDs from preloader (Array[String])
	var decor_ids: Array = Array(texture_preloader.get_resource_list()).filter(
		func(id: String) -> bool: return id.begins_with("decor_")
	)
	print("Loaded ", decor_ids.size(), " decor textures")

	if decor_ids.is_empty():
		return

	var num_decors: int = decor_ids.size()
	var layer_height: float = viewport.y * 4

	for i in range(num_decors):
		var decor: Sprite2D = Sprite2D.new()
		var random_index: int = randi_range(0, decor_ids.size() - 1)
		var id: String = decor_ids[random_index]
		decor.texture = texture_preloader.get_resource(id)
		decor.centered = false

		var scale_factor: float = randf_range(0.5, 1.0)
		decor.scale = Vector2(scale_factor, scale_factor)

		decor.position.x = randf_range(0, viewport.x - (decor.texture.get_width() * scale_factor))
		decor.position.y = randf_range(
			0, layer_height - (decor.texture.get_height() * scale_factor)
		)

		decor_layer.add_child(decor)

	decor_layer.motion_scale = Vector2(1, 0.5)
	decor_layer.motion_mirroring = Vector2(0, layer_height)


func _process(delta: float) -> void:
	var scroll_speed: float = player.speed["speed"] * delta * Globals.difficulty * 0.8
	background.scroll_offset.y += scroll_speed
	if player.fuel["fuel"] <= 0:
		background.scroll_offset = Vector2(0, 0)

	# 1. Critical unbound controls warning (shown once per session)
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
		MessageType.CRITICAL_UNBOUND:
			_showing_unbound_warning = false
		MessageType.KEY_PRESS_UNBOUND:
			_showing_unbound_key_message = false
