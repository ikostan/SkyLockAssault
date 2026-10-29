## Copyright (C) 2026 Egor Kostan
## SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
## sfx_manager.gd
## Autoload singleton for non-positional SFX playback, split out of AudioManager.
## Owns the pooled AudioStreamPlayers, the LRU stream cache, the playback diagnostics
## used by tests, and the global UI button click hook (Issue #800).
## Volume and mute state stay in AudioManager. Access as SfxManager.play_sfx(...), etc.

extends Node

## Hard cap for cached SFX streams to prevent unbounded memory growth.
const MAX_SFX_CACHE_SIZE: int = 20

## Number of reusable AudioStreamPlayers to keep in memory for UI sounds.
const SFX_POOL_SIZE: int = 8

# --- SFX CACHE STATE ---
## Dictionary to store preloaded AudioStreams to prevent disk I/O stutter.
var _sfx_cache: Dictionary = {}

## Dictionary acting as a set to track missing SFX and prevent repeated load attempts/log spam.
var _missing_sfx_cache: Dictionary = {}

## Array of pre-instantiated AudioStreamPlayers to prevent node instantiation churn.
var _sfx_pool: Array[AudioStreamPlayer] = []


func _ready() -> void:
	# Initialize the SFX object pool
	_initialize_sfx_pool()

	# Connect global listener with a safety guard to ensure only one listener attaches (Issue #800)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)

	# Retroactively scan for any buttons that snuck into the tree during the initialization frame
	_retroactive_ui_scan(get_tree().root)


## Recursively passes existing tree nodes into the parsing logic to catch early initializations
func _retroactive_ui_scan(node: Node) -> void:
	if not is_instance_valid(node):
		return

	# FIX: Optimize tree traversal by skipping function call churn on non-Button components
	if node.get_class() == "Button":
		_on_node_added(node)

	# Always traverse children so we don't miss buttons nested inside containers/panels
	for child: Node in node.get_children():
		_retroactive_ui_scan(child)


## Private helper to initialize the SFX object pool matching production setup.
func _initialize_sfx_pool() -> void:
	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_pool.append(p)


## Centralized SFX Playback API (Issue #570)
## Handles non-positional audio with LRU caching and auto-cleanup.
## :param sfx_name: The logical identifier (e.g., "ui_navigation" or "slider").
## :param bus_name: Target audio bus (defaults to SFX_Menu).
## :param pitch_scale: Pitch override for variety.
## :param volume_db: Volume offset in decibels.
func play_sfx(
	sfx_name: String,
	bus_name: String = AudioConstants.BUS_SFX_MENU,
	pitch_scale: float = 1.0,
	volume_db: float = 0.0
) -> void:
	# LAZY-INIT SAFEGUARD: If the pool hasn't been initialized yet, build it on the fly
	if _sfx_pool.is_empty():
		_initialize_sfx_pool()  # Assumes this is your pool setup function name

	if sfx_name.is_empty():
		return

	# Short-circuit: If we already know this file is missing, do not attempt to load it again.
	if _missing_sfx_cache.has(sfx_name):
		return

	# 1. Resolve and Cache the AudioStream (with LRU Eviction)
	if not _sfx_cache.has(sfx_name):
		# Resolve the logical name to its exact mapped file name
		var file_name: String = sfx_name
		if sfx_name in AudioConstants.SFX_ASSET_MAP:
			file_name = AudioConstants.SFX_ASSET_MAP[sfx_name]
		else:
			# Structural fallback safely preserving legacy/direct calls
			file_name += ".wav"

		var full_path: String = AudioConstants.SFX_DIR_PATH + file_name

		# Safety guard against non-existent files to block core engine loader errors from polluting tests
		if not ResourceLoader.exists(full_path):
			Globals.log_message(
				"SFX file not found or failed to load: " + full_path, Globals.LogLevel.WARNING
			)
			# Cache the failure so we don't spam the disk and logs on subsequent requests
			_missing_sfx_cache[sfx_name] = true
			return

		var stream: AudioStream = load(full_path)

		if stream:
			# Eviction strategy: If cache is full, remove the oldest (first) entry
			if _sfx_cache.size() >= MAX_SFX_CACHE_SIZE:
				var oldest_key: String = _sfx_cache.keys()[0]
				_sfx_cache.erase(oldest_key)
				Globals.log_message(
					"SFX cache full. Evicted: " + oldest_key, Globals.LogLevel.DEBUG
				)

			_sfx_cache[sfx_name] = stream
		else:
			Globals.log_message(
				"SFX file found but failed to parse correctly: " + full_path,
				Globals.LogLevel.WARNING
			)
			_missing_sfx_cache[sfx_name] = true
			return
	else:
		# LRU Update: Godot 4 Dictionaries preserve insertion order.
		# By erasing and re-inserting, we push this active sound to the "newest" end of the dictionary.
		var stream: AudioStream = _sfx_cache[sfx_name]
		_sfx_cache.erase(sfx_name)
		_sfx_cache[sfx_name] = stream

	# 2. Grab an available player from the object pool (Safe against freed/dangling instances!)
	var player: AudioStreamPlayer = null
	for p: AudioStreamPlayer in _sfx_pool:
		if is_instance_valid(p) and not p.playing:
			player = p
			break

	# Fallback: If all players are busy, hijack the first valid one in the pool
	if player == null:
		for p: AudioStreamPlayer in _sfx_pool:
			if is_instance_valid(p):
				player = p
				break

	# Final safety guard in case the pool somehow contains zero valid instances
	if player == null:
		push_error("AudioManager: No valid AudioStreamPlayer instances found in pool.")
		return

	player.stream = _sfx_cache[sfx_name]
	player.pitch_scale = pitch_scale
	player.volume_db = volume_db

	# 3. Bus Validation & Routing
	if AudioServer.get_bus_index(bus_name) == -1:
		Globals.log_message(
			"Invalid bus '%s' requested for SFX. Falling back to SFX_Menu." % bus_name,
			Globals.LogLevel.WARNING
		)
		player.bus = AudioConstants.BUS_SFX_MENU
	else:
		player.bus = bus_name

	# 4. Play (No queue_free needed since we reuse the nodes)
	player.play()


## [DIAGNOSTIC]
## Checks if any AudioStreamPlayer node within the pre-allocated pool is currently active.
## :rtype: bool
func is_any_sfx_playing() -> bool:
	for player: AudioStreamPlayer in _sfx_pool:
		if is_instance_valid(player) and player.playing:
			return true
	return false


## [DIAGNOSTIC]
## Returns the total number of AudioStreamPlayer channels currently active.
## :rtype: int
func get_active_sfx_playback_count() -> int:
	var count: int = 0
	for player: AudioStreamPlayer in _sfx_pool:
		if is_instance_valid(player) and player.playing:
			count += 1
	return count


## Stops all active audio layers and clears streamed audio resources across the object pool.
## :rtype: void
func stop_all_sfx() -> void:
	for player: AudioStreamPlayer in _sfx_pool:
		if is_instance_valid(player):
			player.stop()
			player.stream = null


## [DIAGNOSTIC]
## Public API: Returns the resource path of the most recently started active SFX.
## If multiple sounds are active, this returns the one most recently assigned to the pool.
## If no sounds are playing, returns an empty string.
## Returns String: Resource path of the active stream.
func get_active_sfx_stream_path() -> String:
	# Iterate backwards through the pool to return the most recently
	# added/played sound, making the choice deterministic and explicit.
	for i in range(_sfx_pool.size() - 1, -1, -1):
		var player: AudioStreamPlayer = _sfx_pool[i]
		if is_instance_valid(player) and player.playing and player.stream:
			return player.stream.resource_path
	return ""


## [DIAGNOSTIC]
## Public API: Returns the target audio bus name of the most recently started active SFX.
## If no sounds are playing, returns an empty string.
## Returns String: Name of the assigned audio bus.
func get_active_sfx_bus_name() -> String:
	# Iterate backwards matching our deterministic track verification rules
	for i in range(_sfx_pool.size() - 1, -1, -1):
		var player: AudioStreamPlayer = _sfx_pool[i]
		if is_instance_valid(player) and player.playing:
			return player.bus
	return ""


## FOR GUT UNIT TEST ONLY
## Forcefully clear resources to prevent leaks between unit tests.
## Strictly guarded to prevent accidental execution in production builds.
func cleanup_for_test() -> void:
	# 0. Production safety guards
	if not OS.is_debug_build():
		return

	_sfx_cache.clear()
	_missing_sfx_cache.clear()

	# 1. Clean the pool deterministically
	for i in range(_sfx_pool.size() - 1, -1, -1):
		var player := _sfx_pool[i]
		if is_instance_valid(player):
			player.stop()
			# Reset bus before freeing to avoid dangling references
			player.bus = "Master"
			if player.get_parent() == self:
				remove_child(player)
			player.free()
		_sfx_pool.remove_at(i)

	# 1b. Free orphaned players left behind when a test swapped this node's script
	# (set_script() resets _sfx_pool but keeps the child nodes).
	for child: Node in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			remove_child(child)
			child.free()

	# 2. Re-create the pool matching production configuration
	_initialize_sfx_pool()


## Automatically hooks up base Button elements for confirmation sfx (Ported via Issue #800)
func _on_node_added(node: Node) -> void:
	# Use strict string evaluation to satisfy the verification contract
	if node.get_class() == "Button":
		var btn := node as Button
		if is_instance_valid(btn):
			# Flat Button Protection: Avoid superimposing global audio over theme audio
			if btn.flat or btn.has_meta("no_global_sound"):
				return

			# Dialog Protection: Exclude internal buttons of Accept/ConfirmationDialogs
			var parent: Node = btn.get_parent()
			while parent:
				if parent is AcceptDialog:
					return
				parent = parent.get_parent()

			# Guard against duplicate connections using CONNECT_DEFERRED for thread safety
			if not btn.pressed.is_connected(_on_global_button_pressed):
				btn.pressed.connect(_on_global_button_pressed, CONNECT_DEFERRED)


## Centralized button audio execution target routed natively within AudioManager
func _on_global_button_pressed() -> void:
	# Route button accepts directly through the internal SFX bus configuration
	play_sfx("ui_accept", AudioConstants.BUS_SFX_MENU)
