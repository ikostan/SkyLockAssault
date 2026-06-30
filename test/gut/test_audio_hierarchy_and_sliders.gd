## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later
## test_audio_hierarchy_and_sliders.gd
##
## Integration suite verifying multi-tiered UI interactivity locks and volume
## component tracking security during external focus loss conditions.
extends "res://addons/gut/test.gd"

const SIGNAL_SETTLE_FRAMES: int = 2

var audio_scene: PackedScene = load(GamePaths.AUDIO_SETTINGS_SCENE)
var audio_instance: Control


func before_each() -> void:
	AudioManager.reset_volumes()
	audio_instance = audio_scene.instantiate() as Control
	add_child_autofree(audio_instance)
	await settle_ui()


func after_each() -> void:
	if is_instance_valid(audio_instance):
		audio_instance.queue_free()
	audio_instance = null
	await settle_ui()


## Shared helper to wait for deferred signals and UI layouts to settle completely.
func settle_ui() -> void:
	await wait_process_frames(SIGNAL_SETTLE_FRAMES)


## Shared helper to cleanly synthesize an active left-click mouse drag interaction sequence.
func _begin_drag(slider: VolumeSlider) -> void:
	slider.grab_focus()
	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = MOUSE_BUTTON_LEFT
	mouse_event.pressed = true
	slider._on_gui_input(mouse_event)


# ==========================================================================
# 1. CORE HIERARCHY PROPAGATION
# ==========================================================================

## Verifies that muting Master volume actively propagates disabled flags 
## down to the entire downstream audio configuration panel.
func test_master_mute_locks_entire_child_hierarchy() -> void:
	# Arrange
	# Clean baseline is handled by before_each()

	# Act
	AudioManager.set_muted(AudioConstants.BUS_MASTER, true)
	await settle_ui()
	
	# Assert
	assert_true(AudioManager.get_muted(AudioConstants.BUS_MASTER), "Model: Master must be logged as muted.")
	assert_true(audio_instance.mute_music.disabled, "UI: Music Mute should lock out when Master is muted.")
	assert_false(audio_instance.music_slider.editable, "UI: Music Slider should be uneditable when Master is muted.")
	assert_true(audio_instance.mute_sfx.disabled, "UI: SFX Mute should lock out when Master is muted.")
	assert_false(audio_instance.weapon_slider.editable, "UI: Weapon Sub-slider must freeze when Master hierarchy closes.")


## Verifies that muting the parent SFX channel selectively locks sub-buses
## while leaving unrelated tracks like Music operational.
func test_sfx_mute_locks_only_sfx_sub_buses() -> void:
	# Arrange
	AudioManager.set_muted(AudioConstants.BUS_MASTER, false)
	await wait_process_frames(1)

	# Act
	AudioManager.set_muted(AudioConstants.BUS_SFX, true)
	await settle_ui()
	
	# Assert
	assert_true(AudioManager.get_muted(AudioConstants.BUS_SFX), "Model: SFX must be logged as muted.")
	assert_false(audio_instance.mute_music.disabled, "UI: Music selection toggle must remain open.")
	assert_true(audio_instance.music_slider.editable, "UI: Music slider scale should remain operational.")
	
	assert_true(audio_instance.mute_weapon.disabled, "UI: Weapon Mute button must lock down under parent SFX mute conditions.")
	assert_false(audio_instance.weapon_slider.editable, "UI: Weapon volume adjustment track must lock down.")
	assert_true(audio_instance.mute_rotor.disabled, "UI: Rotor structural toggle must lock down.")


# ==========================================================================
# 2. STATE RESTORATION AND TRANSITIONS (REGRESSION PROTECTION)
# ==========================================================================

## Verifies that unmuting the Master bus restores full interactivity across all child nodes.
func test_master_unmute_restores_child_interactivity() -> void:
	# Arrange: Force an initial locked state completely down the hierarchy
	AudioManager.set_muted(AudioConstants.BUS_MASTER, true)
	await settle_ui()
	assert_true(AudioManager.get_muted(AudioConstants.BUS_MASTER))
	assert_true(audio_instance.mute_music.disabled, "Precondition: Hierarchy must be initially locked.")

	# Act: Unmute master and allow signals to settle
	AudioManager.set_muted(AudioConstants.BUS_MASTER, false)
	await settle_ui()

	# Assert: All standard primary children must become operational again alongside model states
	assert_false(AudioManager.get_muted(AudioConstants.BUS_MASTER), "Model: Master must be logged as unmuted.")
	assert_false(audio_instance.mute_music.disabled, "UI: Music Mute should be re-enabled when Master is unmuted.")
	assert_true(audio_instance.music_slider.editable, "UI: Music Slider should be editable when Master is unmuted.")
	assert_false(audio_instance.mute_sfx.disabled, "UI: SFX Mute should be re-enabled when Master is unmuted.")
	assert_true(audio_instance.sfx_slider.editable, "UI: SFX Slider should be editable when Master is unmuted.")


## Verifies that nested sub-buses correctly respond to intermediate parent state changes.
func test_nested_hierarchy_transitions_re_enable_sub_buses() -> void:
	# Arrange: Keep Master unmuted, but mute parent SFX bus to lock sub-buses down
	AudioManager.set_muted(AudioConstants.BUS_MASTER, false)
	AudioManager.set_muted(AudioConstants.BUS_SFX, true)
	await settle_ui()
	assert_true(AudioManager.get_muted(AudioConstants.BUS_SFX))
	assert_true(audio_instance.mute_weapon.disabled, "Precondition: Sub-buses must be locked down by parent SFX.")

	# Act: Unmute the intermediate parent SFX bus
	AudioManager.set_muted(AudioConstants.BUS_SFX, false)
	await settle_ui()

	# Assert: Sub-buses must dynamically follow the intermediate parent restoration
	assert_false(AudioManager.get_muted(AudioConstants.BUS_SFX), "Model: SFX parent must be logged as unmuted.")
	assert_false(audio_instance.mute_weapon.disabled, "UI: Weapon Mute should re-enable when SFX is unmuted.")
	assert_true(audio_instance.weapon_slider.editable, "UI: Weapon Slider should become editable when SFX is unmuted.")
	assert_false(audio_instance.mute_rotor.disabled, "UI: Rotor Mute should re-enable when SFX is unmuted.")
	assert_true(audio_instance.rotor_slider.editable, "UI: Rotor Slider should become editable when SFX is unmuted.")


## Verifies that changing a sub-bus state does not leak or contaminate unrelated peer controls.
func test_unrelated_bus_mutations_preserve_independent_states() -> void:
	# Arrange: Mute Music explicitly to create a distinct custom state snapshot
	AudioManager.set_muted(AudioConstants.BUS_MUSIC, true)
	await settle_ui()
	assert_true(AudioManager.get_muted(AudioConstants.BUS_MUSIC))
	assert_false(audio_instance.mute_music.button_pressed, "Precondition: Music UI should show muted (not pressed).")

	# Act: Perform high-frequency mutations on a completely separate SFX sub-branch
	AudioManager.set_muted(AudioConstants.BUS_SFX_WEAPON, true)
	await wait_process_frames(1)
	AudioManager.set_muted(AudioConstants.BUS_SFX_WEAPON, false)
	await settle_ui()

	# Assert: The isolated music configuration controls and models must remain completely unchanged
	assert_true(AudioManager.get_muted(AudioConstants.BUS_MUSIC), "Model: Music must firmly retain its muted state.")
	assert_false(audio_instance.mute_music.button_pressed, "UI: Music control state must survive unrelated weapon sub-bus changes.")
	assert_false(audio_instance.music_slider.editable, "UI: Music slider must remain frozen via its own specific mute rule.")


# ==========================================================================
# 3. SLIDER TRACKING & FOCUS RESILIENCE
# ==========================================================================

## Verifies that dragging tracking states fail-safe instantly if an external event 
## steals application layout window alignment.
func test_slider_drag_state_drops_on_application_focus_loss() -> void:
	# Arrange
	var slider: VolumeSlider = audio_instance.master_slider
	_begin_drag(slider)
	assert_true(slider.is_user_dragging(), "Precondition: Slider must actively confirm dragging status profile.")
	
	# Act
	# Direct notification invocation is intentional because GUT cannot synthesize OS window focus changes.
	slider._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	
	# Assert
	assert_false(
		slider.is_user_dragging(),
		"Slider must instantly drop active drag state tracking when OS window focus drops."
	)


## Verifies that executing multiple unexpected focus loss calls back-to-back behaves safely.
func test_slider_focus_loss_notification_is_idempotent() -> void:
	# Arrange
	var slider: VolumeSlider = audio_instance.master_slider
	_begin_drag(slider)
	assert_true(slider.is_user_dragging(), "Precondition: Slider tracking drag sequence.")

	# Act
	# Direct notification invocation is intentional because GUT cannot synthesize OS window focus changes.
	slider._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	slider._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await wait_process_frames(1)

	# Assert
	assert_false(slider.is_user_dragging(), "Slider drag state must remain safely dropped.")


## Verifies that an app focus loss notification does not cause an accidental toggle inversion if the user wasn't dragging.
func test_slider_focus_loss_does_not_toggle_drag_state_unintentionally() -> void:
	# Arrange
	var slider: VolumeSlider = audio_instance.master_slider
	assert_false(slider.is_user_dragging(), "Precondition: Slider is stationary.")

	# Act
	# Direct notification invocation is intentional because GUT cannot synthesize OS window focus changes.
	slider._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await wait_process_frames(1)

	# Assert
	assert_false(slider.is_user_dragging(), "Slider drag state must strictly remain false; no accidental inversion.")
