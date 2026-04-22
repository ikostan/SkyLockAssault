## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_gameplay_settings_js.gd
##
## GS-JS: Defensive regression suite for JavaScriptBridge communication.
## Focuses on payload shapes, malformed input safety, and primitive regressions.

extends "res://addons/gut/test.gd"

const GameplaySettings = preload("res://scripts/ui/menus/gameplay_settings.gd")
var gameplay_menu: Control

func before_each() -> void:
	# Fresh resource to isolate state
	Globals.settings = GameSettingsResource.new()
	gameplay_menu = load("res://scenes/gameplay_settings.tscn").instantiate()
	# Inject mock wrapper to simulate web environment
	gameplay_menu.os_wrapper = OSWrapper.new() 
	add_child_autofree(gameplay_menu)
	await get_tree().process_frame


# --- SECTION 6.1: SUPPORTED PAYLOAD SHAPES (GS-JS-01 to 05) ---

## GS-JS-01/02 | Valid nested array extraction
func test_gs_js_01_02_nested_array_success() -> void:
	# Standard JS Bridge format: [ [value] ]
	gameplay_menu._on_change_difficulty_js([[1.5]])
	assert_eq(Globals.settings.difficulty, 1.5, "Should extract 1.5 from nested array")
	
	gameplay_menu._on_change_difficulty_js([[0.8]])
	assert_eq(Globals.settings.difficulty, 0.8, "Should extract 0.8 from nested array")


## GS-JS-03 | Nested numeric string coercion
func test_gs_js_03_numeric_string_coercion() -> void:
	# Test if "1.5" is correctly cast to float 1.5
	gameplay_menu._on_change_difficulty_js([["1.5"]])
	assert_eq(Globals.settings.difficulty, 1.5, "Should coerce numeric string to float")


## GS-JS-04/05 | JS-originated values are clamped by resource
func test_gs_js_04_05_out_of_range_clamping() -> void:
	gameplay_menu._on_change_difficulty_js([[5.0]])
	assert_eq(Globals.settings.difficulty, 2.0, "Input 5.0 should be clamped to max 2.0")
	
	gameplay_menu._on_change_difficulty_js([[0.1]])
	assert_eq(Globals.settings.difficulty, 0.5, "Input 0.1 should be clamped to min 0.5")


# --- SECTION 6.2 & 6.3: MALFORMED INPUT & PRIMITIVE SAFETY (GS-JS-10 to 25) ---

## GS-JS-10/11 | Handle empty arrays safely
func test_gs_js_10_11_empty_array_safety() -> void:
	var initial_val: float = Globals.settings.difficulty
	gameplay_menu._on_change_difficulty_js([])
	gameplay_menu._on_change_difficulty_js([[]])
	assert_eq(Globals.settings.difficulty, initial_val, "Empty arrays should not change state or crash")


## GS-JS-12/14 | Handle non-numeric and whitespace strings
func test_gs_js_12_14_malformed_string_safety() -> void:
	var initial_val: float = Globals.settings.difficulty
	gameplay_menu._on_change_difficulty_js([["abc"]])
	gameplay_menu._on_change_difficulty_js([["   "]])
	assert_eq(Globals.settings.difficulty, initial_val, "Malformed strings should be rejected safely")


## GS-JS-20/21 | SCALAR REGRESSION - CRITICAL FIX FOR ISSUE #471
func test_gs_js_20_21_scalar_safety() -> void:
	var initial_val: float = Globals.settings.difficulty
	gameplay_menu._on_change_difficulty_js([1.5]) 
	# Precise Assertion: The value should be accepted, not just "not crash"
	assert_eq(Globals.settings.difficulty, 1.5, "Scalar float should be accepted")

	gameplay_menu._on_change_difficulty_js(["invalid"])
	# Precise Assertion: Malformed scalar should be rejected, leaving value at 1.5
	assert_eq(Globals.settings.difficulty, 1.5, "Malformed scalar string should be rejected")


## GS-JS-22/25 | Unsupported primitives and objects
func test_gs_js_22_25_unsupported_type_safety() -> void:
	var initial_val: float = Globals.settings.difficulty
	gameplay_menu._on_change_difficulty_js([null])
	gameplay_menu._on_change_difficulty_js([true])
	# Precise Assertion: Ensure the state is untouched
	assert_eq(Globals.settings.difficulty, initial_val, "Unsupported types should not modify state")


# --- SECTION 6.4: MISSING NODE SAFETY (GS-JS-30 to 32) ---

## GS-JS-30 | JS callback handles missing slider node
func test_gs_js_30_missing_node_safety() -> void:
	# Force the slider to be null to simulate a late callback during teardown
	gameplay_menu.difficulty_slider.free() 
	
	# Function should check 'is_instance_valid' before accessing slider properties
	gameplay_menu._on_change_difficulty_js([[1.2]])
	# assert_true(true, "Handled missing node reference safely without crash")
	assert_eq(
		Globals.settings.difficulty,
		1.2,
		"When slider is missing, callback should still update resource via fallback path"
	)
