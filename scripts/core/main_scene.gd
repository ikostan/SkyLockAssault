## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## main_scene.gd
## Main scene script for SkyLockAssault.
## Handles player positioning, stats visibility, and parallax background setup.
## NOTE: Legacy Player-to-parallax signal coupling and compatibility shims are completely removed.

class_name MainScene
extends Node2D

enum MessageType { CRITICAL_UNBOUND, KEY_PRESS_UNBOUND }

## How long [method show_message] keeps a message on screen, in seconds.
const MESSAGE_DURATION: float = 4.0
## Cardinal rotations, in degrees, that decor sprites pick from.
const DECOR_ROTATIONS: Array[float] = [0.0, 90.0, 180.0, -90.0]

# At the top of main_scene.gd
@export var parallax_screens_tall: float = 8.0

var web_telemetry_adapter: WebTelemetryAdapter
var _showing_unbound_warning: bool = false
var _showing_unbound_key_message: bool = false
# Increased by every show_message() call. A message's timer hides the label only if no newer
# message was shown in the meantime, so an older timer can't hide a newer message early.
var _message_generation: int = 0
# Set when bindings or the device changed while this scene was paused (Key Mapping is opened
# from the pause menu). The check runs on NOTIFICATION_UNPAUSED, so the warning is shown when
# the player is back in the game, as the old per-frame check in _process did.
var _unbound_check_pending: bool = false

@onready var player: Player = $Player
@onready var stats_panel: Panel = $PlayerStatsPanel
@onready var background: ParallaxBackground = $Background
@onready var bushes_layer: ParallaxLayer = $Background/Bushes  # Reference to the bushes layer
@onready var decor_layer: ParallaxLayer = $Background/Decor  # Reference to the decor layer
@onready var texture_preloader: ResourcePreloader = $ResourcePreloader  # Reference to preloader
@onready var hud: CanvasLayer = $HUD
@onready var message_label: Label = $HUD/MessageLabel
## Level-owned container for projectiles, so they're freed with this level (#1140).
@onready var projectiles: Node2D = $Projectiles


func _ready() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	Globals.log_message("Viewport size: " + str(viewport_size), Globals.LogLevel.DEBUG)
	# Same fraction the player uses for its vertical bounds, so both move together.
	player.position = Vector2(
		viewport_size.x / 2, viewport_size.y * _get_player_stats().spawn_y_fraction
	)
	stats_panel.visible = true
	Globals.log_message("Initializing main scene...", Globals.LogLevel.DEBUG)

	# Projectiles belong to this level, so leaving it frees them at once (#1140).
	player.weapon.set_projectile_parent(projectiles)

	# =========================================================
	# DEPENDENCY INJECTION: HUD Data Layer
	# Extracts raw telemetry data resources directly from the player
	# hierarchy and passes them into the HUD.
	# =========================================================
	if stats_panel.has_method("setup_hud"):
		stats_panel.setup_hud(
			player.fuel_resource, player.speed_resource, player.weapon.weapon_resource
		)
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
	# Safely extract settings once to use for both injection and priming.
	# The is_instance_valid(Globals) guard prevents hard crashes during
	# isolated GUT tests where Autoloads may not be fully initialized.
	# Also guard against a null or freed Globals.settings so background.setup
	# only ever receives a valid GameSettingsResource or null.
	var settings_res: GameSettingsResource = (
		Globals.settings
		if (
			is_instance_valid(Globals)
			and Globals.settings != null
			and is_instance_valid(Globals.settings)
		)
		else null
	)

	if background.has_method("setup"):
		# Inject all required resources into the newly refactored ParallaxManager
		background.setup(player.speed_resource, player.fuel_resource, settings_res)
	else:
		push_warning(
			"Parallax background is missing the `setup` method. Resource injection failed."
		)

	# =========================================================
	# FLOAT DEGRADATION SAFEGUARD
	# =========================================================
	# Delegate wrap period calculation entirely to the ParallaxManager.
	# This preserves encapsulation so main_scene doesn't need to know layer specifics.
	if background.has_method("auto_calculate_wrap_period"):
		background.auto_calculate_wrap_period()

	# 1. Instantiate the adapter
	web_telemetry_adapter = WebTelemetryAdapter.new()

	# 2. Add it to the Scene Tree so _ready() fires (allowing it to self-destruct if not on web)
	add_child(web_telemetry_adapter)

	# 3. Inject the active resource from the player
	if OS.has_feature("web"):
		web_telemetry_adapter.setup(player.fuel_resource)

	# First check at level start; later checks run on the Settings signals (see _enter_tree).
	_check_unbound_controls()


## Connects to the Settings signals. Bindings and the input device change only through
## Settings, which announces both, so the unbound-controls check runs on those signals instead
## of every frame (#1102).
func _enter_tree() -> void:
	if not Settings.bindings_changed.is_connected(_on_bindings_changed):
		Settings.bindings_changed.connect(_on_bindings_changed)
	if not Settings.input_device_changed.is_connected(_on_input_device_changed):
		Settings.input_device_changed.connect(_on_input_device_changed)


## Disconnects from the Settings autoload, which outlives this scene.
func _exit_tree() -> void:
	if Settings.bindings_changed.is_connected(_on_bindings_changed):
		Settings.bindings_changed.disconnect(_on_bindings_changed)
	if Settings.input_device_changed.is_connected(_on_input_device_changed):
		Settings.input_device_changed.disconnect(_on_input_device_changed)


## Runs an unbound-controls check that was deferred while the scene was paused.
func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED and _unbound_check_pending:
		_unbound_check_pending = false
		_check_unbound_controls()


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
	# Settings owns the threshold, so gameplay and the remap buttons
	# share one value without gameplay depending on a UI class.
	# ────────────────────────────────────────────────────────────────
	if event is InputEventJoypadMotion and abs(event.axis_value) < Settings.AXIS_DEADZONE_THRESHOLD:
		return

	# Player pressed a completely unbound key/button/axis
	if not Settings.is_event_bound(event) and not _showing_unbound_key_message:
		_showing_unbound_key_message = true
		var device_type: String = InputEventCodec.get_event_device_type(event)
		var pause_label: String = Settings.get_pause_binding_label_for_device(device_type)
		show_message(
			"{UNBOUND=KEY=PRESSED}\n{PRESS='" + pause_label + "'=AND=GO=TO='CONTROLS'=TO=FIX}",
			MessageType.KEY_PRESS_UNBOUND  # explicit
		)


## Sets up a parallax layer for tiling and mirroring.
##
## Configures region settings and motion mirroring on the parent ParallaxLayer.
##
## [param sprite]: The target Sprite2D node to configure for tiling and mirroring.
## [param viewport]: The size of the viewport used to calculate the required tile count.
## [param buffer_mult]: Multiplier for the vertical buffer size.
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


## Clears existing children and repopulates the bushes layer with randomly
## positioned, scaled, and textured sprites from the texture preloader
## (resources whose IDs begin with "bush_").
##
## [param viewport]: Viewport size in pixels. [code]x[/code] bounds horizontal placement;
## [code]y[/code] multiplied by [member parallax_screens_tall] sets the layer height and
## vertical mirroring interval.
func setup_bushes_layer(viewport: Vector2) -> void:
	_populate_sprite_layer(bushes_layer, "bush_", viewport, Callable())


## Clears existing children and repopulates the decor layer with sprites from the
## texture preloader (resources whose IDs begin with "decor_").
##
## Each element gets a random position, scale, texture, cardinal rotation, and
## horizontal/vertical flip.
##
## [param viewport]: Viewport size in pixels. [code]x[/code] bounds horizontal placement;
## [code]y[/code] multiplied by [member parallax_screens_tall] sets the layer height and
## vertical mirroring interval.
func setup_decor_layer(viewport: Vector2) -> void:
	_populate_sprite_layer(decor_layer, "decor_", viewport, _configure_decor_sprite)


## Shared setup for the bushes and decor layers.
##
## Frees the layer's children, then adds two sprites per texture whose preloader ID starts
## with [param id_prefix]. Each sprite gets a random texture from that set, a random uniform
## scale from 0.5 to 1.5, and a random position that keeps it inside the viewport width and
## the layer height. The layer height is [code]viewport.y[/code] times
## [member parallax_screens_tall]; the layer mirrors vertically at that height and scrolls at
## [code]motion_scale = (1, 0.5)[/code]. A layer with no matching textures stays empty and
## keeps its motion settings.
##
## [param layer]: The layer to rebuild. Does nothing when null.
## [param id_prefix]: Preloader ID prefix that selects the textures, such as
## [code]"bush_"[/code].
## [param viewport]: Viewport size in pixels.
## [param configure]: Optional [code]func(sprite: Sprite2D) -> void[/code] for anything
## specific to one layer, such as decor rotation and flips. It runs after the scale is set
## and before the position is chosen. Pass an empty [Callable] for none.
func _populate_sprite_layer(
	layer: ParallaxLayer, id_prefix: String, viewport: Vector2, configure: Callable
) -> void:
	if not layer:
		return

	# Clear existing children (Safely detach first, then instantly destroy)
	for child in layer.get_children():
		layer.remove_child(child)
		child.free()

	var ids: Array = Array(texture_preloader.get_resource_list()).filter(
		func(id: String) -> bool: return id.begins_with(id_prefix)
	)

	if ids.is_empty():
		return

	# THE GOLDILOCKS ZONE:
	# 8 screens is the sweet spot for infinite illusion vs CPU overhead
	var layer_height: float = viewport.y * parallax_screens_tall

	# Two sprites per texture
	var sprite_count: int = ids.size() * 2

	for i in range(sprite_count):
		var sprite: Sprite2D = Sprite2D.new()
		var id: String = ids[randi_range(0, ids.size() - 1)]
		sprite.texture = texture_preloader.get_resource(id)
		sprite.centered = false

		var scale_factor: float = randf_range(0.5, 1.5)
		sprite.scale = Vector2(scale_factor, scale_factor)

		if configure.is_valid():
			configure.call(sprite)

		sprite.position.x = randf_range(0, viewport.x - (sprite.texture.get_width() * scale_factor))
		sprite.position.y = randf_range(
			0, layer_height - (sprite.texture.get_height() * scale_factor)
		)

		layer.add_child(sprite)

	layer.motion_scale = Vector2(1, 0.5)
	layer.motion_mirroring = Vector2(0, layer_height)


## Decor-only sprite setup for [method _populate_sprite_layer]: random horizontal and
## vertical flips, and a random cardinal rotation (0, 90, 180 or -90 degrees).
## [param decor]: The decor sprite to configure.
func _configure_decor_sprite(decor: Sprite2D) -> void:
	decor.flip_h = randf() < 0.5
	decor.flip_v = randf() < 0.5
	var degrees: float = DECOR_ROTATIONS.pick_random()
	decor.rotation = deg_to_rad(degrees)


## Shows the critical unbound-controls warning, once, if a critical action has no binding for
## the current device.
##
## The warning shows once per session: [member _showing_unbound_warning] stays set until the
## bindings change ([method _on_bindings_changed]), so it doesn't repeat every 4 seconds.
func _check_unbound_controls() -> void:
	if _showing_unbound_warning:
		return
	if not Settings.has_unbound_critical_actions_for_current_device():
		return
	_showing_unbound_warning = true
	var pause_key: String = Settings.get_pause_binding_label()
	show_message(
		"{SOME=CONTROLS=ARE=UNBOUND}\n{PRESS='" + pause_key + "'=AND=GO=TO='CONTROLS'=TO=FIX}",
		MessageType.CRITICAL_UNBOUND  # explicit
	)


## Runs [method _check_unbound_controls] now, or on unpause if the scene is paused.
func _request_unbound_check() -> void:
	if not is_inside_tree():
		return
	if can_process():
		_check_unbound_controls()
	else:
		_unbound_check_pending = true


## Reacts to [signal Settings.bindings_changed]: the player rebound or reset controls, so the
## warning may show again, then re-checks.
func _on_bindings_changed() -> void:
	_showing_unbound_warning = false
	_request_unbound_check()


## Reacts to [signal Settings.input_device_changed]: the other device may have unbound critical
## actions. Doesn't reset the once-per-session flag.
## [param _device]: The new device; the check reads it from Settings.
func _on_input_device_changed(_device: String) -> void:
	_request_unbound_check()


## Shows a temporary on-screen message non-blocking and centralizes flags.
##
## Displays the specified text on the message label for [constant MESSAGE_DURATION]
## seconds. Each call starts a new message generation. When a message's time is up, the
## label is hidden only if no newer message was shown since, so an older timer can't hide a
## newer message early.
##
## The KEY_PRESS_UNBOUND flag resets when its own message expires, even if a newer message
## is still showing, so that warning can appear again. The CRITICAL_UNBOUND flag stays set
## so the warning shows once per session, until [signal Settings.bindings_changed] clears it.
##
## [param text]: The message text to display on the label.
## [param type]: The message type; KEY_PRESS_UNBOUND resets its flag on expiry.
func show_message(text: String, type: MessageType = MessageType.CRITICAL_UNBOUND) -> void:
	if not is_instance_valid(message_label):
		return

	_message_generation += 1
	var generation: int = _message_generation
	message_label.text = text
	message_label.visible = true

	await get_tree().create_timer(MESSAGE_DURATION).timeout

	# Hide only if this is still the newest message
	if generation == _message_generation and is_instance_valid(message_label):
		message_label.visible = false

	# Reset the right flag based on message type
	match type:
		MessageType.KEY_PRESS_UNBOUND:
			_showing_unbound_key_message = false


## Returns the player's stats, or the shipped defaults when the player has none yet. The
## player assigns its defaults in its own _ready(), which runs before this scene's.
func _get_player_stats() -> PlayerStatsResource:
	if player.stats != null:
		return player.stats
	return Player.DEFAULT_PLAYER_STATS
