extends RigidBody3D

@export var planet_center: Vector3

@export var gravity := 9.81
@export var acceleration := 25.0
@export var max_speed := 8.0
@export var jump_impulse := 6.0

@export var camera_rig: CameraRig

var move_input := Vector2.ZERO

var grounded := false
var ground_normal := Vector3.UP
var jump_pressed := false
var jump_was_pressed := false


func _ready():
	contact_monitor = true
	max_contacts_reported = 8


func _process(_delta):
	move_input = Input.get_vector(
		"move_left",
		"move_right",
		"move_back",
        "move_forward"
	)

	var pressed = Input.is_action_pressed("jump")
	jump_pressed = pressed and !jump_was_pressed
	jump_was_pressed = pressed


func _integrate_forces(state: PhysicsDirectBodyState3D):

	# Planet up/down
	var up = (global_position - planet_center).normalized()
	var down = -up

	# Gravity
	apply_central_force(down * gravity * mass)

	# --------------------------
	# Ground detection
	# --------------------------

	grounded = false
	ground_normal = up

	for i in state.get_contact_count():

		var normal = state.get_contact_local_normal(i).normalized()

		# Contact is considered ground if mostly facing upward
		if normal.dot(up) > 0.4:
			grounded = true

			if normal.dot(up) > ground_normal.dot(up):
				ground_normal = normal

	# --------------------------
	# Camera-relative movement
	# --------------------------

	var forward = camera_rig.get_forward(up)

	# Project camera forward onto movement plane
	forward = forward.slide(ground_normal).normalized()

	if forward.length_squared() < 0.001:
		forward = up.cross(Vector3.RIGHT).normalized()

	var right = forward.cross(ground_normal).normalized()

	var desired = forward * move_input.y + right * move_input.x

	if desired.length_squared() > 0.0:

		desired = desired.normalized()

		# Always project movement along the surface
		desired = desired.slide(ground_normal).normalized()

		var tangent_velocity = linear_velocity.slide(ground_normal)

		var speed = tangent_velocity.dot(desired)

		if speed < max_speed:
			apply_central_force(
				desired * acceleration * mass
			)

	# --------------------------
	# Jump
	# --------------------------

	if grounded and jump_pressed:

		# Remove downward velocity before jumping
		var vertical_speed = linear_velocity.dot(ground_normal)

		if vertical_speed < 0.0:
			linear_velocity -= ground_normal * vertical_speed

		apply_central_impulse(
			ground_normal * jump_impulse * mass
		)
