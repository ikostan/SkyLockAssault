## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_globals_button_hooks.gd
##
## Architectural test suite verifying the automatic stream connection guards
## inside the global Node instantiation tracking track.
extends "res://addons/gut/test.gd"


func before_each() -> void:
	AudioManager.stop_all_sfx()


func after_each() -> void:
	AudioManager.stop_all_sfx()
	await _wait_for_registration()


# ==========================================================================
# 1. TIMING, LIFECYCLE & STRUCTURAL HELPERS
# ==========================================================================

## Shared helper to handle multi-frame deferral windows safely.
func _wait_for_registration() -> void:
	await wait_process_frames(2)


## Counts how many times the global audio hook is connected to a specific button.
## Optionally validates that the connection strictly uses the CONNECT_DEFERRED flag.
func _get_global_connection_count(btn: Button, require_deferred: bool = true) -> int:
	var count: int = 0
	for connection: Dictionary in btn.pressed.get_connections():
		var callable: Callable = connection.get("callable", Callable())
		if callable == Globals._on_global_button_pressed:
			if require_deferred:
				var flags: int = connection.get("flags", 0)
				if flags & CONNECT_DEFERRED:
					count += 1
			else:
				count += 1
	return count


# ==========================================================================
# 2. REGISTRATION CONTROLS (INCLUSION & EXCLUSION RULES)
# ==========================================================================

## Regular runtime UI buttons should auto-bind to the global audio layer exactly once.
func test_standard_button_auto_connects_exactly_once() -> void:
	# Arrange & Act
	var standard_btn := Button.new()
	add_child_autofree(standard_btn)
	await _wait_for_registration()
	
	# Assert
	assert_eq(
		_get_global_connection_count(standard_btn),
		1,
		"Standard interactive buttons must have exactly one connection to the global handler."
	)


## Flat UI theme buttons must be exempted from global audio routing.
func test_flat_button_is_ignored_by_hook() -> void:
	# Arrange & Act
	var flat_btn := Button.new()
	flat_btn.flat = true
	add_child_autofree(flat_btn)
	await _wait_for_registration()
	
	# Assert
	assert_eq(
		_get_global_connection_count(flat_btn),
		0,
		"Flat buttons must bypass global audio registration."
	)


## Buttons carrying 'no_global_sound' metadata must remain isolated.
func test_meta_flagged_button_is_ignored_by_hook() -> void:
	# Arrange & Act
	var isolated_btn := Button.new()
	isolated_btn.set_meta("no_global_sound", true)
	add_child_autofree(isolated_btn)
	await _wait_for_registration()
	
	# Assert
	assert_eq(
		_get_global_connection_count(isolated_btn),
		0,
		"Metadata-flagged buttons must bypass global audio registration."
	)


## Internal dialog buttons should never receive global audio hooks.
func test_dialog_internal_buttons_are_ignored_by_hook() -> void:
	# Arrange & Act
	var confirmation_dialog := ConfirmationDialog.new()
	add_child_autofree(confirmation_dialog)
	
	var ok_btn := confirmation_dialog.get_ok_button()
	var cancel_btn := confirmation_dialog.get_cancel_button()
	await _wait_for_registration()
	
	# Assert
	assert_eq(_get_global_connection_count(ok_btn), 0, "Dialog OK button must ignore global hooks.")
	assert_eq(_get_global_connection_count(cancel_btn), 0, "Dialog Cancel button must ignore global hooks.")


## Architectural Policy: Engine button subclasses are intentionally excluded 
## from automatic global audio routing to prevent double audio tracking against local triggers.
func test_button_subclass_is_ignored_by_strict_class_contract() -> void:
	# Arrange & Act
	var custom_btn := CheckButton.new()
	add_child_autofree(custom_btn)
	await _wait_for_registration()
	
	# Assert
	assert_eq(
		_get_global_connection_count(custom_btn),
		0,
		"Engine button subclasses must bypass global audio registration matching rules."
	)


# ==========================================================================
# 3. SCENE-TREE LIFECYCLE CONTROLS (MUTATION & REGRESSION PROTECTION)
# ==========================================================================

## Moving a node inside the active scene layout tree must not generate duplicate connection tracks.
func test_reparenting_does_not_create_duplicate_connections() -> void:
	# Arrange
	var parent_a := Control.new()
	var parent_b := Control.new()
	var btn := Button.new()
	
	add_child_autofree(parent_a)
	add_child_autofree(parent_b)
	parent_a.add_child(btn)
	await _wait_for_registration()
	
	assert_eq(_get_global_connection_count(btn), 1, "Precondition: Single tracking baseline established.")

	# Act
	btn.reparent(parent_b)
	await _wait_for_registration()

	# Assert
	assert_eq(
		_get_global_connection_count(btn),
		1,
		"Reparenting a node inside the scene tree must not introduce duplicate signal connections."
	)


## Manually re-triggering tree scan events against an already tracked node must remain idempotent.
func test_duplicate_scan_calls_do_not_duplicate_connections() -> void:
	# Arrange
	var btn := Button.new()
	add_child_autofree(btn)
	await _wait_for_registration()
	assert_eq(_get_global_connection_count(btn), 1, "Precondition: Single link registered.")

	# Act
	# This intentionally exercises the internal callback because duplicate registration 
	# protection loops live entirely within that routine block.
	Globals._on_node_added(btn)
	await _wait_for_registration()

	# Assert
	assert_eq(
		_get_global_connection_count(btn),
		1,
		"Repeated tree tracking passes must guard against duplicate audio stream connections."
	)


## Architectural Constraint: Runtime metadata updates applied post-entrance are not reactive.
func test_post_registration_metadata_changes_do_not_retroactively_disconnect() -> void:
	# Arrange
	var btn := Button.new()
	add_child_autofree(btn)
	await _wait_for_registration()
	assert_eq(_get_global_connection_count(btn), 1, "Precondition: Normal hook assigned on entrance.")

	# Act
	btn.set_meta("no_global_sound", true)
	await _wait_for_registration()

	# Assert
	assert_eq(
		_get_global_connection_count(btn),
		1,
		"Architectural Constraint: Runtime metadata updates applied post-entrance are not reactive."
	)


# ==========================================================================
# 4. CLEANUP & MEMORY RESILIENCE
# ==========================================================================

## Verifies that freeing a registered node doesn't corrupt state or pollute tracking systems
## when subsequent identical button nodes enter the tree.
func test_node_destruction_cleanup_is_safe() -> void:
	# Arrange
	var initial_btn := Button.new()
	# Upgraded to autofree to prevent scene tree pollution if the precondition assertion fails
	add_child_autofree(initial_btn)
	await _wait_for_registration()
	assert_eq(_get_global_connection_count(initial_btn), 1, "Precondition: First button hooked up cleanly.")
	
	# Act: Deallocate the node from memory completely
	initial_btn.queue_free()
	await _wait_for_registration()
	
	# Instantiate a replacement button control
	var fresh_btn := Button.new()
	add_child_autofree(fresh_btn)
	await _wait_for_registration()
	
	# Assert: Tracking baseline re-registers perfectly without bleeding stale links
	assert_eq(
		_get_global_connection_count(fresh_btn),
		1,
		"Memory Cleanup Failed: Node destruction caused tracking anomalies or double connection leaks on fresh nodes."
	)
## Functional Coverage: Verifies that the deferred connection track established during
## instantiation tracking cleanly triggers audio output via AudioManager upon signal emission.
func test_standard_button_pressed_executes_audio_output() -> void:
	# Arrange: Instantiate a standard baseline push button node
	var standard_btn: Button = Button.new()
	
	# Act: Append button node to current layout scene tracking frame windows
	add_child_autofree(standard_btn)
	await _wait_for_registration()
	
	# Act: Clean running audio buffers to isolate manual tracking loop emissions
	AudioManager.stop_all_sfx()
	if AudioManager.has_method("cleanup_for_test"):
		AudioManager.cleanup_for_test()

	# Act: Simulate a direct hardware selection event by manually emitting the pressed track
	standard_btn.pressed.emit()
	
	# Act: Yield execution to allow the CONNECT_DEFERRED queue pipeline to completely settle
	await _wait_for_registration()

	# Assert: Verify that the global button press handler accurately requested playback
	assert_true(
		AudioManager.is_any_sfx_playing(),
		"Functional Failure: Automated button hook was deferred but failed to route playback to AudioManager on press."
	)
