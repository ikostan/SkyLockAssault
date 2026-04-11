## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_player_fuel_logic.gd
## GUT unit tests for Player fuel consumption, engine states, and UI Reactivity.
extends "res://addons/gut/test.gd"

const PLAYER_SCRIPT_PATH: String = "res://scripts/player.gd"

var _mock_root: Node
var _player: Variant # CHANGED: Use Variant to allow dynamic property access to player.gd variables
var _original_settings: GameSettingsResource
var _added_actions: Array[String] = []

## Per-test setup.
## :rtype: void
func before_each() -> void:
	_original_settings = Globals.settings
	Globals.settings = GameSettingsResource.new()
	Globals.settings.current_log_level = Globals.LogLevel.NONE
	
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
	Input.action_release("move_left")

## test_ui_updates_automatically_on_resource_change | Observer Pattern
## :rtype: void
func test_ui_updates_automatically_on_resource_change() -> void:
	gut.p("Testing: Player UI responds seamlessly to external fuel updates.")
	
	var fuel_bar: ProgressBar = _player.fuel_bar
	
	Globals.settings.max_fuel = 200.0
	# Because of the resource setter, current_fuel modification fires 'setting_changed' automatically
	Globals.settings.current_fuel = 150.0 
	
	assert_eq(fuel_bar.max_value, 200.0, "Fuel Bar max_value must sync with Resource max.")
	assert_eq(fuel_bar.value, 150.0, "Fuel Bar value must sync automatically.")

## test_engine_stops_on_zero_fuel | Component State
## :rtype: void
func test_engine_stops_on_zero_fuel() -> void:
	gut.p("Testing: Zero fuel stops timers and rotor animations immediately.")
	
	_player.fuel_timer.start()
	var anim_r: AnimatedSprite2D = _player.rotor_right.get_node("AnimatedSprite2D")
	anim_r.play("default")
	
	_player._on_player_out_of_fuel()
	
	assert_true(_player.fuel_timer.is_stopped(), "Fuel timer must stop running on flameout.")
	assert_false(anim_r.is_playing(), "Rotors must stop animating when fuel is empty.")

## test_engine_reignites_on_refuel | Component State
## :rtype: void
func test_engine_reignites_on_refuel() -> void:
	gut.p("Testing: Refueling from an empty tank restarts rotors and timers.")
	
	# Simulate dead engine
	_player.fuel_timer.stop()
	var anim_l: AnimatedSprite2D = _player.rotor_left.get_node("AnimatedSprite2D")
	anim_l.stop()
	
	# Trigger the global setting change to simulate refuel logic
	Globals.settings.current_fuel = 50.0 
	
	assert_false(_player.fuel_timer.is_stopped(), "Fuel timer must reignite on refuel.")
	assert_true(anim_l.is_playing(), "Rotors must automatically resume spinning.")

## test_lateral_movement_blocked_without_fuel | Movement Constraints
## :rtype: void
func test_lateral_movement_blocked_without_fuel() -> void:
	gut.p("Testing: Lateral turning is disabled if fuel is completely empty.")
	
	Globals.settings.current_fuel = 0.0
	_player.speed["speed"] = 150.0 
	_player.player.velocity.x = 0.0
	
	Input.action_press("move_left")
	_player._physics_process(0.1)
	
	assert_eq(float(_player.player.velocity.x), 0.0, "Plane must not turn without fuel, ignoring inputs.")

# ==========================================
# MOCK BUILDER HELPER
# ==========================================
# Note: You can optionally extract this into a shared res://tests/test_helpers.gd base class later!
## Dynamically constructs the node hierarchy required by player.gd.
## :rtype: Node
func _build_mock_player_scene() -> Node:
	var root: Node = Node.new()
	root.name = "MockLevel"
	
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
	#var weapon: Node2D = Node2D.new()
	#weapon.name = "Weapon"
	
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
