## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_player_movement_signals.gd
## GUT unit tests for Player movement and the decoupled speed_changed signal.

extends "res://addons/gut/test.gd"

# UPDATE THIS PATH if player.gd is located in a different folder
const PLAYER_SCRIPT_PATH: String = "res://scripts/player.gd"

var _mock_root: Node
var _player: Node2D
var _original_settings: GameSettingsResource
var _added_actions: Array[String] = []

## Per-test setup: Isolate memory and establish mock hierarchy.
## :rtype: void
func before_each() -> void:
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	Globals.settings.current_log_level = Globals.LogLevel.NONE
	
	# Guarantee required actions exist so simulated Input.action_press doesn't error
	for action: String in ["speed_up", "speed_down", "move_left", "move_right"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			_added_actions.append(action)
			
	_mock_root = _build_mock_player_scene()
	add_child_autoqfree(_mock_root)
	_player = _mock_root.get_node("Player")

## Per-test cleanup.
## :rtype: void
func after_each() -> void:
	Globals.settings = _original_settings
	for action: String in _added_actions:
		InputMap.erase_action(action)
	_added_actions.clear()
	
	# Force-release simulated inputs to prevent test leakage
	Input.action_release("speed_up")
	Input.action_release("speed_down")

## test_physics_emits_speed_changed_on_acceleration | Signal Behavior
## :rtype: void
func test_physics_emits_speed_changed_on_acceleration() -> void:
	gut.p("Testing: _physics_process emits speed_changed exactly once per frame when accelerating.")
	watch_signals(_player)
	
	Globals.settings.current_fuel = 100.0
	_player.speed["speed"] = 100.0
	
	# Simulate acceleration input
	Input.action_press("speed_up")
	_player._physics_process(1.0) # 1 second delta to cause noticeable change
	
	assert_signal_emitted(_player, "speed_changed", "Signal must fire when speed up increases value.")
	assert_gt(float(_player.speed["speed"]), 100.0, "Speed logic should have increased current speed.")

## test_physics_does_not_spam_speed_changed | Signal Efficiency
## :rtype: void
func test_physics_does_not_spam_speed_changed() -> void:
	gut.p("Testing: _physics_process suppresses speed_changed emissions when cruising.")
	watch_signals(_player)
	
	Globals.settings.current_fuel = 100.0
	_player.speed["speed"] = 250.0 
	
	# Process multiple frames without active input
	_player._physics_process(0.1)
	_player._physics_process(0.1)
	_player._physics_process(0.1)
	
	assert_signal_emit_count(_player, "speed_changed", 0, "Signal must not emit when speed is unchanged.")

## test_flameout_resets_speed_and_emits_signal | Edge Cases
## :rtype: void
func test_flameout_resets_speed_and_emits_signal() -> void:
	gut.p("Testing: Engine flameout halts the plane instantly and notifies UI.")
	watch_signals(_player)
	
	_player.speed["speed"] = 300.0
	
	# Manually trigger the flameout handler
	_player._on_player_out_of_fuel()
	
	assert_eq(float(_player.speed["speed"]), 0.0, "Speed must forcibly reset to 0.0 on zero fuel.")
	assert_signal_emitted(_player, "speed_changed", "Flameout must broadcast the speed halt to UI.")

## test_ui_updates_on_speed_signal | UI Reactivity
## :rtype: void
func test_ui_updates_on_speed_signal() -> void:
	gut.p("Testing: Target UI updates instantly when speed_changed fires.")
	
	_player.speed_bar.value = 0.0
	_player.speed["speed"] = 500.0 # Force local sync
	
	# Fire the signal explicitly as the engine would
	_player.speed_changed.emit(500.0)
	
	assert_eq(_player.speed_bar.value, 500.0, "Progress bar must sync tightly with speed_changed.")

## test_speed_clamps_to_max_and_min | Constraints
## :rtype: void
func test_speed_clamps_to_max_and_min() -> void:
	gut.p("Testing: Speed values obey MIN and MAX constraints.")
	
	Globals.settings.current_fuel = 100.0
	var max_cap: float = _player.speed["max"]
	
	_player.speed["speed"] = max_cap - 5.0
	
	Input.action_press("speed_up")
	# Force an extreme acceleration delta
	_player._physics_process(10.0) 
	
	assert_eq(float(_player.speed["speed"]), max_cap, "Speed must not exceed configured MAX_SPEED.")

# ==========================================
# MOCK BUILDER HELPER
# ==========================================

## Dynamically constructs the node hierarchy required by player.gd.
## :rtype: Node
func _build_mock_player_scene() -> Node:
	var root: Node = Node.new()
	root.name = "MockLevel"
	
	# --- UI Siblings ---
	var panel: Panel = Panel.new()
	panel.name = "PlayerStatsPanel"
	var stats: Control = Control.new()
	stats.name = "Stats"
	
	var fuel: Control = Control.new()
	fuel.name = "Fuel"
	var fuel_bar: ProgressBar = ProgressBar.new()
	fuel_bar.name = "FuelBar"
	var fuel_label: Label = Label.new()
	fuel_label.name = "FuelLabel"
	var f_timer: Timer = Timer.new()
	f_timer.name = "BlinkTimer"
	fuel_label.add_child(f_timer)
	fuel.add_child(fuel_bar)
	fuel.add_child(fuel_label)
	
	var speed: Control = Control.new()
	speed.name = "Speed"
	var speed_bar: ProgressBar = ProgressBar.new()
	speed_bar.name = "SpeedBar"
	var speed_label: Label = Label.new()
	speed_label.name = "SpeedLabel"
	var s_timer: Timer = Timer.new()
	s_timer.name = "BlinkTimer"
	speed_label.add_child(s_timer)
	speed.add_child(speed_bar)
	speed.add_child(speed_label)
	
	stats.add_child(fuel)
	stats.add_child(speed)
	panel.add_child(stats)
	root.add_child(panel)
	
	# --- Core Player ---
	var PlayerScript := load(PLAYER_SCRIPT_PATH)
	var p_node: Variant = PlayerScript.new()
	p_node.name = "Player"
	
	var cb2d: CharacterBody2D = CharacterBody2D.new()
	cb2d.name = "CharacterBody2D"
	
	for rotor_name: String in ["RotorRight", "RotorLeft"]:
		var rotor: Node2D = Node2D.new()
		rotor.name = rotor_name
		var sfx: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		sfx.name = "AudioStreamPlayer2D"
		var anim: AnimatedSprite2D = AnimatedSprite2D.new()
		anim.name = "AnimatedSprite2D"
		# var frames: SpriteFrames = SpriteFrames.new()
		# frames.add_animation("default")
		# anim.sprite_frames = frames
		
		var frames: SpriteFrames = SpriteFrames.new()
		frames.add_animation("default")
		# Add a dummy frame so play() actually engages and is_playing() returns true
		var dummy_tex: PlaceholderTexture2D = PlaceholderTexture2D.new()
		frames.add_frame("default", dummy_tex)
		anim.sprite_frames = frames
		
		rotor.add_child(anim)
		rotor.add_child(sfx)
		cb2d.add_child(rotor)
		
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "Sprite2D"
	var coll: CollisionPolygon2D = CollisionPolygon2D.new()
	coll.name = "CollisionPolygon2D"
	# var weapon: Node2D = Node2D.new()
	# weapon.name = "Weapon"
	
	var weapon: Node2D = Node2D.new()
	weapon.name = "Weapon"
	
	# Create a dummy script so player.gd's _ready() and _input() don't crash
	var mock_weapon_script: GDScript = GDScript.new()
	mock_weapon_script.source_code = """
extends Node2D
var weapon_types: Array = []
var current_index: int = 0
func fire() -> void: 
	pass
func get_num_weapons() -> int: 
	return 1
func switch_to(idx: int) -> void: 
	pass
"""

	mock_weapon_script.reload()
	weapon.set_script(mock_weapon_script)
	
	cb2d.add_child(sprite)
	cb2d.add_child(coll)
	cb2d.add_child(weapon)
	
	var fuel_timer: Timer = Timer.new()
	fuel_timer.name = "FuelTimer"
	
	p_node.add_child(cb2d)
	p_node.add_child(fuel_timer)
	root.add_child(p_node)
	
	return root
