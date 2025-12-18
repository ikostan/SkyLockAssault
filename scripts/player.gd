extends Node2D

# Fuel color thresholds (percentages)
const HIGH_FUEL_THRESHOLD: float = 90.0  # Starts green lerp
const MEDIUM_FUEL_THRESHOLD: float = 50.0  # Switches to yellow lerp
const LOW_FUEL_THRESHOLD: float = 30.0  # Switches to red lerp
const NO_FUEL_THRESHOLD: float = 15.0  # Fully Red Color

# Exported vars first (for Inspector editing)
@export var speed: float = 250.0
@export var max_fuel: float = 100.0
var current_fuel: float

# Regular vars for computed boundaries (no export needed if set in code)
var player_half_width: float = 0.0
var player_half_height: float = 0.0
var player_x_min: float = 0.0
var player_x_max: float = 0.0
var player_y_min: float = 0.0
var player_y_max: float = 0.0
# For gradual colors shifts (e.g., green to red as fuel drops), use Color.lerp
var lerp_factor: float

# Weapon system
var weapons: Array[Node] = []  # Fill in editor or _ready
var current_weapon: int = 0
var screen_size: Vector2

# Onreadys next
@onready var player: CharacterBody2D = $CharacterBody2D
@onready var collision_shape: CollisionShape2D = $CharacterBody2D/CollisionShape2D
@onready
var fuel_bar: ProgressBar = $"../PlayerStatsPanel/VBoxContainer/HBoxContainer/FuelProgressBar"
@onready var fuel_timer: Timer = $FuelTimer
# Get the fill style
@onready var fill_style: StyleBoxFlat = fuel_bar.get_theme_stylebox("fill")
# Cached initial fill color
@onready var progress_bar_bg_color: Color = fill_style.bg_color
# In plane.gd (or main player script) - central input
@onready var weapon: Node2D = $CharacterBody2D/Weapon  # Path to your WeaponManager node


func _ready() -> void:
	# Dynamically calculate half-sizes (use both extents for width/height; assumes RectangleShape2D)
	if collision_shape.shape is RectangleShape2D:
		player_half_width = collision_shape.shape.extents.x * abs(collision_shape.scale.x)
		player_half_height = collision_shape.shape.extents.y * abs(collision_shape.scale.y)
	else:
		Globals.log_message(
			"Warning: Using fallback size—check collision shape type.", Globals.LogLevel.WARNING
		)
		player_half_width = 12.0  # Default guess; adjust based on your sprite
		player_half_height = 12.0

	# Set screen boundaries (assuming centered origin; tweak if top-left)
	var screen_size: Vector2 = get_viewport_rect().size
	player_x_min = (screen_size.x * -0.5) + (player_half_width * 2)
	player_x_max = (screen_size.x * 0.5) - (player_half_width * 2)
	player_y_min = (screen_size.y * -0.83) + player_half_height
	player_y_max = screen_size.y / 7

	# After player_half_width/height calc
	Globals.log_message(
		(
			"Boundaries: x("
			+ str(player_x_min)
			+ "-"
			+ str(player_x_max)
			+ ") y("
			+ str(player_y_min)
			+ "-"
			+ str(player_y_max)
			+ ")"
		),
		Globals.LogLevel.DEBUG
	)

	# Initialize fuel
	current_fuel = max_fuel
	fuel_bar.max_value = max_fuel
	fuel_bar.value = current_fuel  # Set initial progress
	fuel_timer.timeout.connect(_on_fuel_timer_timeout)
	fuel_timer.start()

	# Null-safe weapon log
	if weapon:
		Globals.log_message(
			"Player ready. Weapons loaded: " + str(weapon.weapon_types.size()),
			Globals.LogLevel.DEBUG
		)
	else:
		push_error("Weapon node not found! Check player.tscn scene tree for $Weapon child.")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("fire"):
		# Globals.log_message("Fire input pressed → calling weapon.fire()", Globals.LogLevel.DEBUG)
		if weapon and weapon.has_method("fire"):
			weapon.fire()
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("next_weapon"):
		Globals.log_message("Next weapon input pressed", Globals.LogLevel.DEBUG)
		if weapon and weapon.has_method("switch_to") and weapon.get_num_weapons() > 1:
			var next: int = (weapon.current_index + 1) % weapon.get_num_weapons()
			weapon.switch_to(next)
		get_viewport().set_input_as_handled()


# Connect Timer's timeout signal
func _on_fuel_timer_timeout() -> void:
	var fuel_left: float = current_fuel - (0.5 * Globals.difficulty)  # Scale base rate
	# Add a clamp so current_fuel never drops below zero
	# to prevent negative values and any unintended behavior in the fuel bar.
	current_fuel = clamp(fuel_left, 0, max_fuel)
	# Now compute percent and lerp from the clamped/updated value
	var fuel_percent: float = (current_fuel / max_fuel) * 100.0
	fuel_bar.value = current_fuel
	lerp_factor = 1.0 - (current_fuel / max_fuel)  # 0=full (green), 1=empty (red)
	progress_bar_bg_color = fill_style.bg_color

	if fuel_percent > HIGH_FUEL_THRESHOLD:
		fill_style.bg_color = Color.GREEN  # Full green for high fuel
	elif fuel_percent >= MEDIUM_FUEL_THRESHOLD:
		# Lerp green to yellow (factor 0 at 90%, 1 at 50%)
		var section_factor: float = (
			(HIGH_FUEL_THRESHOLD - fuel_percent) / (HIGH_FUEL_THRESHOLD - MEDIUM_FUEL_THRESHOLD)
		)
		fill_style.bg_color = Color.GREEN.lerp(Color.YELLOW, section_factor)
	elif fuel_percent >= LOW_FUEL_THRESHOLD:
		# Lerp yellow to red
		var section_factor: float = (
			(MEDIUM_FUEL_THRESHOLD - fuel_percent) / (MEDIUM_FUEL_THRESHOLD - LOW_FUEL_THRESHOLD)
		)
		fill_style.bg_color = Color.YELLOW.lerp(Color.RED, section_factor)
	elif fuel_percent > NO_FUEL_THRESHOLD:
		# Lerp red to darker or full red
		var section_factor: float = (
			(LOW_FUEL_THRESHOLD - fuel_percent) / (LOW_FUEL_THRESHOLD - NO_FUEL_THRESHOLD)
		)
		fill_style.bg_color = Color.RED.lerp(Color(0.5, 0, 0), section_factor)  # Example to dark red
	else:
		fill_style.bg_color = Color.RED  # Full red

	if current_fuel <= 0:
		speed = 0.0  # Or game over logic
		fuel_timer.stop()
	Globals.log_message("Fuel left: " + str(current_fuel), Globals.LogLevel.DEBUG)


func _physics_process(_delta: float) -> void:
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "speed_up", "speed_down")
	if direction != Vector2.ZERO:
		player.velocity = direction * speed
	else:
		player.velocity = Vector2.ZERO
	player.move_and_slide()

	player.position.x = clamp(player.position.x, player_x_min, player_x_max)
	player.position.y = clamp(player.position.y, player_y_min, player_y_max)
