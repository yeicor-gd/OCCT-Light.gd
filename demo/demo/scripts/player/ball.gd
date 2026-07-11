extends RigidBody3D

@export var planet_center: Vector3

@export var gravity = 35.0
@export var acceleration = 24.0
@export var max_speed = 18.0

@export var move_virtual_joystick: NodePath

var move_input := Vector2.ZERO


func _integrate_forces(state):

	var up = (global_position - planet_center).normalized()
	var down = -up

	# custom gravity
	apply_central_force(down * gravity * mass)

	# tangent basis

	var camera = get_viewport().get_camera_3d()

	var forward = -camera.global_basis.z

	forward = (forward - up * forward.dot(up)).normalized()

	var right = forward.cross(up).normalized()

	var move = right * move_input.x + forward * move_input.y

	if move.length() > 0.01:
		var tangent_velocity = linear_velocity - up * linear_velocity.dot(up)

		if tangent_velocity.length() < max_speed:
			apply_central_force(move.normalized() * acceleration * mass)


func _process(_delta):
	move_input = Input.get_vector(
		"move_left",
		"move_right",
		"move_back",
		"move_forward",
	)
