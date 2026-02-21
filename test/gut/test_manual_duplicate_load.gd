## test_manual_duplicate_load.gd
## -------------------------------------------------------------------------
## Regression test: load_input_mappings must deduplicate identical events
## within the same action when the config contains the same serialized string
## more than once (e.g. from a corrupted or hand-edited file).
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
	# Restore fire bindings so subsequent tests see clean state.
	Settings.load_input_mappings(Settings.CONFIG_PATH, [TEST_ACTION])


func test_load_deduplicates_identical_events_within_action() -> void:
	# 3. Load the mappings using the existing logic
	Settings.load_input_mappings(TEST_CONFIG_PATH, [TEST_ACTION])
	
	var events: Array[InputEvent] = InputMap.action_get_events(TEST_ACTION)
	
	# 4. Deduplication ensures only one event is added despite two identical serialized entries.
	assert_eq(events.size(), 1, "Load should ignore identical duplicate events within the same action")
