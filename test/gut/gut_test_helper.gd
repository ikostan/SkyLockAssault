## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## gut_test_helper.gd
## Shared helper functions and mock builders for GUT unit tests.
extends RefCounted

const PLAYER_SCRIPT_PATH: String = GamePaths.PLAYER


## Helper to safely hard-free a node without causing engine crashes.
## Asserts the node is valid and safe to instantly destroy.
static func safe_hard_free(node: Node) -> void:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	
	if node.is_inside_tree():
		node.get_parent().remove_child(node)
	
	node.free()


## Dynamically constructs the node hierarchy required by player.gd.
## :rtype: Node
static func build_mock_player_scene() -> Node:
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
	
	# Assign the extracted hud.gd script directly to the mock panel
	var hud_script := load(GamePaths.HUD)
	if hud_script:
		panel.set_script(hud_script)
		
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
		
		# Godot 4 automatically adds a "default" animation when you instantiate SpriteFrames.
		var frames: SpriteFrames = SpriteFrames.new()
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
