extends GdUnitTestSuite
@warning_ignore("unused_parameter")
@warning_ignore("return_value_discarded")

var runner: GdUnitSceneRunner

# Optional: Setup before all tests (e.g., mock globals)
func before() -> void:
	pass

# Optional: Teardown after all tests
func after() -> void:
	pass

func test_player_present() -> void:
	var main_scene: Variant = auto_free(load("res://scenes/main_scene.tscn").instantiate())
	add_child(main_scene)  # FIXED: Add to test tree → triggers _enter_tree()/_ready()
	await await_idle_frame()  # FIXED: Await 1 frame for @onready/timers
	await await_millis(1300)  # FIXED: Buffer for menu fades (adjust via logs; 0.5s panel + 0.5s container + margin)
	
	assert_object(main_scene).is_not_null()  # Assert scene loads
	var player: Node2D = main_scene.get_node("Player")  # FIXED: get_node() > find_child() (exact path, faster)
	assert_object(player).is_instanceof(Node2D)
	assert_object(player).is_not_null()
	assert_bool(player.visible).is_true()  # Check post-fade
	assert_bool(player.is_inside_tree()).is_true()  # Explicit: Verify tree status (prevents error)
