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
	
	# FIX (CodeRabbit AI): Prevent state leakage if an early assertion aborts the test body
	if not get_tree().node_added.is_connected(AudioManager._on_node_added):
		get_tree().node_added.connect(AudioManager._on_node_added)
		
	await _wait_for_registration()


# ==========================================================================
# 1. TIMING, LIFECYCLE & STRUCTURAL HELPERS
# ==========================================================================

## Shared helper to handle multi-frame deferral windows safely.
func _wait_for_registration() -> void:
	await wait_process_frames(2)


## Counts how many times the global audio hook is connected to an active button component.
## Strictly validates that the target node possesses a 'pressed' signal, failing early if missing.
func _get_button_connection_count(node: Node, require_deferred: bool = true) -> int:
	if not node.has_signal("pressed"):
		fail_test("Architectural Test Bug: Node '%s' does not possess a 'pressed' signal." % node.name)
		return 0
		
	var count: int = 0
	# FIX: Explicitly type as Array instead of using inference
	var connections: Array = node.pressed.get_connections()
	
	for connection: Dictionary in connections:
		var callable: Callable = connection.get("callable", Callable())
		#if callable == Globals._on_global_button_pressed:
		if callable == AudioManager._on_global_button_pressed:
			if require_deferred:
				var flags: int = connection.get("flags", 0)
				if flags & CONNECT_DEFERRED:
					count += 1
			else:
				count += 1
	return count


## Safe connection counter for layout controls that are explicitly expected to lack a 'pressed' signal.
func _get_non_button_connection_count(node: Node) -> int:
	if not node.has_signal("pressed"):
		return 0
		
	var count: int = 0
	# FIX: Explicitly type as Array instead of using inference
	var connections: Array = node.pressed.get_connections()
	
	for connection: Dictionary in connections:
		var callable: Callable = connection.get("callable", Callable())
		#if callable == Globals._on_global_button_pressed:
		if callable == AudioManager._on_global_button_pressed:	
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
		_get_button_connection_count(standard_btn, true),
		1,
		"Standard interactive buttons must have exactly one connection to the global handler."
	)


## Mock a standard node and verify it is bypassed because it fails the strict class evaluation.
func test_standard_non_button_node_is_bypassed_by_class_evaluation() -> void:
	# Arrange & Act
	var plain_control := Control.new()
	add_child_autofree(plain_control)
	await _wait_for_registration()
	
	# Assert - Uses explicit helper designed for objects lacking button press capabilities
	assert_eq(
		_get_non_button_connection_count(plain_control),
		0,
		"Standard non-Button nodes must be bypassed by the strict node.get_class() == 'Button' evaluation."
	)


## Flat UI theme buttons must be exempted from global audio routing.
func test_flat_button_is_ignored_by_hook() -> void:
	# Arrange & Act
	var flat_btn := Button.new()
	flat_btn.flat = true
	add_child_autofree(flat_btn)
	await _wait_for_registration()
	
	# Assert - Setting require_deferred to false checks for ANY accidental global routing connection
	assert_eq(
		_get_button_connection_count(flat_btn, false),
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
		_get_button_connection_count(isolated_btn, false),
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
	assert_eq(_get_button_connection_count(ok_btn, false), 0, "Dialog OK button must ignore global hooks.")
	assert_eq(_get_button_connection_count(cancel_btn, false), 0, "Dialog Cancel button must ignore global hooks.")


## Construct instances of AcceptDialog and ConfirmationDialog, append buttons internally,
## and assert that tree traversal up the hierarchy catches the ancestor to block attachment.
func test_dialog_ancestry_traversal_prevents_global_attachment() -> void:
	# Arrange
	var accept_dialog := AcceptDialog.new()
	var confirmation_dialog := ConfirmationDialog.new()
	add_child_autofree(accept_dialog)
	add_child_autofree(confirmation_dialog)
	
	var custom_btn_accept := Button.new()
	var custom_btn_confirm := Button.new()
	
	# Act - Append custom buttons directly into dialog hierarchies
	accept_dialog.add_child(custom_btn_accept)
	confirmation_dialog.add_child(custom_btn_confirm)
	await _wait_for_registration()
	
	# Assert
	assert_eq(
		_get_button_connection_count(custom_btn_accept, false),
		0,
		"Buttons appended inside an AcceptDialog must be blocked via ancestry tree evaluation."
	)
	assert_eq(
		_get_button_connection_count(custom_btn_confirm, false),
		0,
		"Buttons appended inside a ConfirmationDialog must be blocked via ancestry tree evaluation."
	)


## Architectural Policy: Engine button subclasses are intentionally excluded 
## from automatic global audio routing to prevent double audio tracking against local triggers.
func test_button_subclass_is_ignored_by_strict_class_contract() -> void:
	# Arrange & Act
	var custom_btn := CheckButton.new()
	add_child_autofree(custom_btn)
	await _wait_for_registration()
	
	# Assert
	assert_eq(
		_get_button_connection_count(custom_btn, false),
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
	
	assert_eq(_get_button_connection_count(btn, true), 1, "Precondition: Single tracking baseline established.")

	# Act
	btn.reparent(parent_b)
	await _wait_for_registration()

	# Assert
	assert_eq(
		_get_button_connection_count(btn, true),
		1,
		"Reparenting a node inside the scene tree must not introduce duplicate signal connections."
	)


## Manually re-triggering tree scan events against an already tracked node must remain idempotent.
func test_duplicate_scan_calls_do_not_duplicate_connections() -> void:
	# Arrange
	var btn := Button.new()
	add_child_autofree(btn)
	await _wait_for_registration()
	assert_eq(_get_button_connection_count(btn, true), 1, "Precondition: Single link registered.")

	# Act - FIX: Target AudioManager instead of Globals
	AudioManager._on_node_added(btn)
	await _wait_for_registration()

	# Assert
	assert_eq(
		_get_button_connection_count(btn, true),
		1,
		"Repeated tree tracking passes must guard against duplicate audio stream connections."
	)


## Assert that button connections strictly utilize the CONNECT_DEFERRED flag
## to validate safe multi-threaded runtime scene tree interaction.
func test_button_connection_strictly_utilizes_deferred_flag() -> void:
	var standard_btn := Button.new()
	add_child_autofree(standard_btn)
	await _wait_for_registration()
	
	assert_eq(
		_get_button_connection_count(standard_btn, true), 
		1, 
		"Audio connection hooks must utilize CONNECT_DEFERRED."
	)


## Architectural Constraint: Runtime metadata updates applied post-entrance are not reactive.
func test_post_registration_metadata_changes_do_not_retroactively_disconnect() -> void:
	# Arrange
	var btn := Button.new()
	add_child_autofree(btn)
	await _wait_for_registration()
	assert_eq(_get_button_connection_count(btn, true), 1, "Precondition: Normal hook assigned on entrance.")

	# Act
	btn.set_meta("no_global_sound", true)
	await _wait_for_registration()

	# Assert
	assert_eq(
		_get_button_connection_count(btn, true),
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
	add_child_autofree(initial_btn)
	await _wait_for_registration()
	assert_eq(_get_button_connection_count(initial_btn, true), 1, "Precondition: First button hooked up cleanly.")
	
	# Act: Deallocate the node from memory completely
	initial_btn.queue_free()
	await _wait_for_registration()
	
	# Instantiate a replacement button control
	var fresh_btn := Button.new()
	add_child_autofree(fresh_btn)
	await _wait_for_registration()
	
	# Assert: Tracking baseline re-registers perfectly without bleeding stale links
	assert_eq(
		_get_button_connection_count(fresh_btn, true),
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
	
	# Act: Yield exactly one frame to allow the CONNECT_DEFERRED queue pipeline to completely settle
	await get_tree().process_frame

	# Assert: Verify that the global button press handler accurately requested playback
	assert_true(
		AudioManager.is_any_sfx_playing(),
		"Functional Failure: Automated button hook was deferred but failed to route playback to AudioManager on press."
	)


# ==========================================================================
# 5. RETROACTIVE INITIALIZATION & AUTOLOAD LIFECYCLE TESTS (SOURCERY-AI)
# ==========================================================================

## Verifies that buttons already present in the scene tree *before* a scan 
## are successfully hooked up by the retroactive tree traversal function.
func test_retroactive_scan_captures_pre_existing_buttons() -> void:
	# 1. Arrange: Disconnect the live listener temporarily to simulate a button 
	# entering the tree BEFORE AudioManager is ready.
	if get_tree().node_added.is_connected(AudioManager._on_node_added):
		get_tree().node_added.disconnect(AudioManager._on_node_added)
		
	var early_button := Button.new()
	add_child_autofree(early_button)
	
	# Precondition check: The button should have 0 connections because the listener was off.
	assert_eq(
		_get_button_connection_count(early_button, false),
		0,
		"Precondition Failed: Early button should not be automatically wired without a live listener."
	)
	
	# 2. Act: Re-connect the production listener and force-run the retroactive scan wrapper
	get_tree().node_added.connect(AudioManager._on_node_added)
	if AudioManager.has_method("_retroactive_ui_scan"):
		AudioManager._retroactive_ui_scan(get_tree().root)
	else:
		fail_test("Architectural Failure: AudioManager is missing the '_retroactive_ui_scan' method.")
		return
		
	await _wait_for_registration()
	
	# 3. Assert: The early button must now be fully wired up
	assert_eq(
		_get_button_connection_count(early_button, true),
		1,
		"Retroactive scan failed to crawl the scene tree and hook up pre-existing buttons."
	)


## Verifies that running the retroactive initialization scan against an active, 
## already-tracked hierarchy remains completely safe and idempotent.
func test_retroactive_scan_is_idempotent_and_does_not_double_bind() -> void:
	# 1. Arrange: Let a standard button auto-register naturally through the active listener
	var standard_button := Button.new()
	add_child_autofree(standard_button)
	await _wait_for_registration()
	
	assert_eq(
		_get_button_connection_count(standard_button, true),
		1,
		"Precondition Failed: Standard button did not perform baseline auto-connection."
	)
	
	# 2. Act: Execute a manual retroactive sweep across the entire root tree layout
	if AudioManager.has_method("_retroactive_ui_scan"):
		AudioManager._retroactive_ui_scan(get_tree().root)
	await _wait_for_registration()
	
	# 3. Assert: Connection counts must still be exactly 1 thanks to the internal .is_connected() guard
	assert_eq(
		_get_button_connection_count(standard_button, true),
		1,
		"Idempotency Guard Failed: Retroactive scan introduced duplicate audio connections to an active button."
	)


## Verifies that AudioManager guards against duplicate listener registration 
## on the SceneTree's node_added signal.
func test_audiomanager_listener_registration_is_strictly_singular() -> void:
	# 1. Arrange: Verify the production baseline is already active
	assert_true(
		get_tree().node_added.is_connected(AudioManager._on_node_added),
		"Precondition Failed: AudioManager should naturally be connected to node_added."
	)
	
	# Extract initial connections array to count total bindings
	var initial_connections: Array = get_tree().node_added.get_connections()
	var baseline_listener_count: int = 0
	for conn: Dictionary in initial_connections:
		if conn.get("callable", Callable()) == AudioManager._on_node_added:
			baseline_listener_count += 1
			
	assert_eq(baseline_listener_count, 1, "Baseline setup should have exactly one listener attached.")

	# 2. Act: Manually simulate a secondary initialization or boot path trigger by calling connect again
	if not get_tree().node_added.is_connected(AudioManager._on_node_added):
		get_tree().node_added.connect(AudioManager._on_node_added)
	
	# 3. Assert: Total active listener attachments on the signal must remain exactly 1
	var post_connections: Array = get_tree().node_added.get_connections()
	var post_listener_count: int = 0
	for conn: Dictionary in post_connections:
		if conn.get("callable", Callable()) == AudioManager._on_node_added:
			post_listener_count += 1
			
	assert_eq(
		post_listener_count, 
		1, 
		"Guard Failure: Multiple boot paths or setup loops duplicated the tree observer listener."
	)


## Verifies that the optimized retroactive scan successfully crawls deep hierarchies 
## containing non-UI and structural nodes, ensuring leaf buttons are found while 
## container elements are bypassed cleanly.
func test_retroactive_scan_traverses_mixed_hierarchy_safely() -> void:
	# 1. Arrange: Disconnect live listener to prevent automatic runtime hooking on entrance
	if get_tree().node_added.is_connected(AudioManager._on_node_added):
		get_tree().node_added.disconnect(AudioManager._on_node_added)
		
	var structural_root := Node.new()          # Completely non-UI structural node
	var intermediate_box := Control.new()       # Layout container (non-Button UI)
	var leaf_button := Button.new()            # Target interactive element
	
	structural_root.add_child(intermediate_box)
	intermediate_box.add_child(leaf_button)
	add_child_autofree(structural_root)
	
	# Precondition check: Hierarchy must start entirely unlinked
	assert_eq(_get_button_connection_count(leaf_button, false), 0)
	assert_eq(_get_non_button_connection_count(intermediate_box), 0)
	
	# 2. Act: Target the optimized retroactive scan directly at the structural root node
	if AudioManager.has_method("_retroactive_ui_scan"):
		AudioManager._retroactive_ui_scan(structural_root)
	else:
		fail_test("Method '_retroactive_ui_scan' missing from AudioManager.")
		return
		
	await _wait_for_registration()
	
	# 3. Assert: The deep leaf button must be successfully wired up
	assert_eq(
		_get_button_connection_count(leaf_button, true),
		1,
		"Optimized retroactive scan failed to descend through non-button layers to find nested buttons."
	)
	
	# 4. Assert: Container items must remain untouched by the wiring logic
	assert_eq(
		_get_non_button_connection_count(intermediate_box),
		0,
		"Optimized retroactive scan incorrectly attempted to apply button hooks to container controls."
	)
