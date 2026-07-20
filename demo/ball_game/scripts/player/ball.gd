extends RigidBody3D

@export var planet_center: Vector3

@export var gravity := 9.81

@export var acceleration := 10.0
@export var max_speed := 10.0
@export var jump_impulse := 0.5

@export var grounded_min_vertical_projection := 0.5
@export var air_control := 0.5
@export var air_torque := 2.0

@export var camera_rig: CameraRig

@onready var ground_cast: ShapeCast3D = $GroundCast

var move_input := Vector2.ZERO

var grounded := false
var ground_normal := Vector3.UP

var jump_pressed := false

var game_active := true

signal jumped


func set_game_active(active: bool) -> void:
	game_active = active
	if not active:
		move_input = Vector2.ZERO
		jump_pressed = false


func _ready():
	contact_monitor = true
	max_contacts_reported = 8


func _process(_delta):

	if not game_active:
		move_input = Vector2.ZERO
		jump_pressed = false
		return

	move_input = Input.get_vector(
		"move_left",
		"move_right",
		"move_back",
		"move_forward"
	)

	jump_pressed =  Input.is_action_pressed("jump")


func _integrate_forces(_state):

	# -------------------------------------------------
	# Gravity
	# -------------------------------------------------

	var up = (global_position - planet_center).normalized()
	var down = -up

	apply_central_force(down * gravity * mass)

	# -------------------------------------------------
	# Ground detection
	# -------------------------------------------------

	ground_cast.force_shapecast_update()

	grounded = false
	ground_normal = up

	var best_dot := -1.0

	for i in range(ground_cast.get_collision_count()):

		var normal = ground_cast.get_collision_normal(i).normalized()
		var d = normal.dot(up)

		if d > best_dot:
			best_dot = d
			ground_normal = normal

	if best_dot > grounded_min_vertical_projection:
		grounded = true
	else:
		ground_normal = up

	# -------------------------------------------------
	# Camera-relative movement
	# -------------------------------------------------

	var forward = camera_rig.get_forward(up)

	forward = forward.slide(ground_normal).normalized()

	if forward.length_squared() < 0.001:
		forward = up.cross(Vector3.RIGHT).normalized()

	var right = forward.cross(ground_normal).normalized()

	var desired = (
		forward * move_input.y +
		right * move_input.x
	)

	if desired.length_squared() > 0.001:

		desired = desired.normalized()

		# Follow the surface.
		desired = desired.slide(ground_normal).normalized()

		var tangent_velocity = linear_velocity.slide(ground_normal)
		var speed = tangent_velocity.dot(desired)

		if speed < max_speed:

			var accel := acceleration

			if !grounded:
				accel *= air_control

			apply_central_force(
				desired * accel * mass
			)

	# -------------------------------------------------
	# Fake air rotation
	# -------------------------------------------------

	if !grounded and desired.length_squared() > 0.001:

		var torque_axis = ground_normal.cross(desired)

		if torque_axis.length_squared() > 0.001:
			apply_torque(
				torque_axis.normalized() * air_torque
			)

	# -------------------------------------------------
	# Jump
	# -------------------------------------------------

	if grounded and jump_pressed: # Use up instead of ground_normal for more control

		var vertical_speed = linear_velocity.dot(up)

		if vertical_speed < 0.0:
			linear_velocity -= up * vertical_speed

		apply_central_impulse(
			up * jump_impulse * mass
		)
		jumped.emit()
