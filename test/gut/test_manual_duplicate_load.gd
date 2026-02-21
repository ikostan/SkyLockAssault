## test_manual_duplicate_load.gd
## -------------------------------------------------------------------------
## We will manually write a ConfigFile that contains the same key serialized
## twice for the same action. When Settings.load_input_mappings processes
## this file, it will call InputMap.action_add_event for each entry without
## checking if the action already contains that specific binding
## -------------------------------------------------------------------------

extends GutTest

const TEST_ACTION: String = "fire"
const TEST_CONFIG_PATH: String = "user://test_manual_dup.cfg"


func before_each() -> void:
	# 1. Ensure the action exists and is empty
	if not InputMap.has_action(TEST_ACTION):
		InputMap.add_action(TEST_ACTION)
	InputMap.action_erase_events(TEST_ACTION)
	
	# 2. Manually create a "corrupted" config with two identical entries
	var config := ConfigFile.new()
	var duplicates: Array[String] = ["key:32", "key:32"] # Two Space bars
	config.set_value("input", TEST_ACTION, duplicates)
	config.save(TEST_CONFIG_PATH)


func after_each() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)


func test_load_fails_to_deduplicate_internal_duplicates() -> void:
	# 3. Load the mappings using the existing logic
	Settings.load_input_mappings(TEST_CONFIG_PATH, [TEST_ACTION])
	
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	
	# 4. This assertion will FAIL before the fix because events.size() will be 2
	assert_eq(events.size(), 1, "Load should ignore identical duplicate events within the same action")
