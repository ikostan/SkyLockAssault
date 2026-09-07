## Copyright (C) 2025 Egor Kostan
## SPDX-License-Identifier: GPL-3.0-or-later

@tool  # Runs in editor
extends ResourcePreloader

@export var force_reload: bool = false:
	set = _force_reload


## TEST WRAPPER: Allows testing to simulate the editor environment.
func _is_in_editor() -> bool:
	return Engine.is_editor_hint()


## TEST WRAPPER: Allows testing to simulate texture load failures safely.
func _load_resource(path: Variant) -> Texture2D:
	return load(path as String) as Texture2D


## Forces reload in editor.
## @param value: bool - Toggle value.
## @return: void
func _force_reload(value: bool) -> void:
	if value and _is_in_editor():
		Globals.log_message("Forcing reload of resources!", Globals.LogLevel.DEBUG)
		_ready()
		force_reload = false  # Reset toggle


## Editor-only ready function.
## @return: void
func _ready() -> void:
	if _is_in_editor():  # Only run in editor
		# Clear existing preloaded resources to avoid duplicates on reload
		var ids: Array = get_resource_list()  # Changed to untyped Array
		Globals.log_message("get_resource_list completed, ids size: %d" % ids.size(), Globals.LogLevel.DEBUG)
		for id: String in ids:
			remove_resource(id)

		# Load and add bushes
		var bush_dir_path: String = "res://files/trees/"  # Your updated bushes path
		var bush_textures: Array[Texture2D] = load_textures_from_dir(bush_dir_path)
		for i in bush_textures.size():
			var texture: Texture2D = bush_textures[i]
			if texture:
				add_resource("bush_" + str(i), texture)  # Unique ID for each texture
		Globals.log_message("Editor: Loaded %d bush textures" % bush_textures.size(), Globals.LogLevel.DEBUG)

		# Load and add decor
		var decor_dir_path: String = "res://files/random_decor/"  # Your updated decor path
		var decor_textures: Array[Texture2D] = load_textures_from_dir(decor_dir_path)
		for i in decor_textures.size():
			var texture: Texture2D = decor_textures[i]
			if texture:
				add_resource("decor_" + str(i), texture)  # Unique ID for each texture
		Globals.log_message("Editor: Loaded %d decor textures" % decor_textures.size(), Globals.LogLevel.DEBUG)


## Helper to scan and load textures from a directory (editor only)
## @param dir_path: String - Directory path.
## @return: Array[Texture2D] - Loaded textures.
func load_textures_from_dir(dir_path: String) -> Array[Texture2D]:
	Globals.log_message("Trying to open directory: " + dir_path, Globals.LogLevel.DEBUG)
	var textures: Array[Texture2D] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		var file_count: int = 0  # Track total files found
		var file_list: String = ""  # To list all files
		while file_name != "":
			file_count += 1
			file_list += file_name + ", "  # Collect all files
			if not dir.current_is_dir() and file_name.ends_with(".png"):
				var texture_path: String = dir_path + file_name
				
				# USE THE WRAPPER HERE
				var texture: Texture2D = _load_resource(texture_path)
				
				if texture:
					textures.append(texture)
					Globals.log_message("Loaded texture: " + texture_path, Globals.LogLevel.DEBUG)
				else:
					Globals.log_message("Warning: Failed to load " + texture_path + " in editor", Globals.LogLevel.WARNING)
			file_name = dir.get_next()
		dir.list_dir_end()
		Globals.log_message("Total files found in directory: %d" % file_count, Globals.LogLevel.DEBUG)
		Globals.log_message("Files list: " + file_list.strip_edges(), Globals.LogLevel.DEBUG)
	else:
		Globals.log_message("Error: Could not open directory at " + dir_path, Globals.LogLevel.ERROR)
	return textures
