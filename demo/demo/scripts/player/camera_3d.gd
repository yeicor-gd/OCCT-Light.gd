extends Node3D

@export var target: RigidBody3D
@export var planet_center: Vector3

@export_group("Follow")
@export var follow_distance := 8.0
@export var focus_height := 1.0
@export var position_smoothing := 8.0
@export var rotation_smoothing := 10.0

@export_group("Manual Camera")
@export var yaw_speed := 2.5
@export var pitch_speed := 1.8
@export var min_pitch := deg_to_rad(-75.0)
@export var max_pitch := deg_to_rad(45.0)

@export_group("Auto Follow")
@export var recenter_delay := 1.25
@export var recenter_speed := 3.0
@export var movement_threshold := 0.3

var yaw := 0.0
var pitch := deg_to_rad(-20.0)

var time_since_manual := 999.0

func _process(delta):

	if target == null or planet_center == null:
		return

	var input := _camera_input()

	if input.length_squared() > 0.0001:

		yaw += input.x * yaw_speed * delta
		pitch += input.y * pitch_speed * delta

		pitch = clamp(pitch, min_pitch, max_pitch)

		time_since_manual = 0.0

	else:

		time_since_manual += delta

	_update_camera(delta)


func _camera_input() -> Vector2:

	var stick := Input.get_vector(
		"camera_left",
		"camera_right",
		"camera_down",
        "camera_up"
	)

	if Input.is_action_pressed("camera_drag"):

		var mouse := Input.get_last_mouse_velocity()

		stick += mouse * Vector2(-0.003, -0.003)

	return stick


func _update_camera(delta):

	var up := (target.global_position - planet_center).normalized()

	#
	# Determine desired forward direction.
	#

	var velocity := target.linear_velocity

	velocity -= up * velocity.dot(up)

	var desired_forward: Vector3

	if velocity.length() > movement_threshold:

		desired_forward = velocity.normalized()

	else:

		desired_forward = -global_basis.z

	#
	# Automatic recenter after player stops moving camera.
	#

	if time_since_manual > recenter_delay:

		var current_forward := -global_basis.z

		current_forward -= up * current_forward.dot(up)
		current_forward = current_forward.normalized()

		var angle := signed_angle(
			current_forward,
			desired_forward,
			up
		)

		yaw += angle * recenter_speed * delta

	#
	# Gravity-aligned basis.
	#

	var gravity_basis := Basis.looking_at(
			desired_forward,
			up
		)

	#
	# User yaw.
	#

	var yaw_quat := Quaternion(
			up,
			yaw
		)

	#
	# Right axis after yaw.
	#

	var right := yaw_quat * gravity_basis.x

	#
	# User pitch.
	#

	var pitch_quat := Quaternion(
			right,
			pitch
		)

	#
	# Final orientation.
	#

	var target_quat := yaw_quat * pitch_quat * gravity_basis.get_rotation_quaternion()

	#
	# Smooth rotation.
	#

	var current_quat := global_basis.get_rotation_quaternion()

	current_quat = current_quat.slerp(
		target_quat,
		rotation_smoothing * delta
	)

	global_basis = Basis(current_quat)

	#
	# Desired camera position.
	#

	var desired_position := target.global_position+ up * focus_height - global_basis.z * follow_distance

	global_position = global_position.lerp(
		desired_position,
		position_smoothing * delta
	)

	#
	# Keep looking at the ball.
	#

	var focus := target.global_position + up * focus_height

	look_at(
		focus,
		up
	)


func signed_angle(
	from: Vector3,
	to: Vector3,
	axis: Vector3
) -> float:

	var cross := from.cross(to)

	return atan2(
		axis.dot(cross),
		from.dot(to)
	)
