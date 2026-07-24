extends Node3D
class_name CameraRig

@export var target: RigidBody3D
@export var planet_center: Vector3

@export_group("Follow")
@export var focus_height := 0.0
@export var position_smoothing := 10.0
@export var rotation_smoothing := 12.0

@export_group("Orbit")
@export var rotate_speed := 2.5
@export var pitch_speed := 2.0
@export var min_pitch := deg_to_rad(-75.0)
@export var max_pitch := deg_to_rad(45.0)

@export_group("Auto Follow")
@export var recenter_delay := 1.5
@export var recenter_speed := 4.0
@export var movement_threshold := 0.25

var forward := Vector3.FORWARD
var pitch := deg_to_rad(-20.0)

var time_since_manual := 999.0

var orbit_mode := false

var _mouse_dragging := false
var _mouse_delta := Vector2.ZERO

signal rotation_changed(_global_basis)


func _ready():

	if target:

		var up = (target.global_position - planet_center).normalized()

		forward = -transform.basis.z
		forward -= up * forward.dot(up)

		if forward.length_squared() < 0.001:
			forward = Vector3.FORWARD

		forward = forward.normalized()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_dragging = event.pressed
			DisplayServer.mouse_set_mode(
				DisplayServer.MOUSE_MODE_CAPTURED if event.pressed
				else DisplayServer.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseMotion and _mouse_dragging:
		var viewport_size := get_viewport().get_visible_rect().size
		_mouse_delta.x -= event.relative.x / (viewport_size.x * 0.5)
		_mouse_delta.y -= event.relative.y / (viewport_size.y * 0.5)


func _physics_process(delta):

	if orbit_mode:
		return

	if target == null:
		return

	var up = (target.global_position - planet_center).normalized()

	#
	# Keep the forward vector tangent to the planet.
	#

	forward -= up * forward.dot(up)

	if forward.length_squared() < 0.001:
		forward = up.cross(Vector3.RIGHT).normalized()

	forward = forward.normalized()

	#
	# Manual camera (keyboard / gamepad).
	#

	var input = _camera_input()

	if abs(input.x) > 0.001:

		forward = forward.rotated(
			up,
			input.x * rotate_speed * delta
		)

		time_since_manual = 0.0

	else:

		time_since_manual += delta

	pitch += input.y * pitch_speed * delta
	pitch = clamp(pitch, min_pitch, max_pitch)

	#
	# Manual camera (mouse drag, accumulated between physics frames).
	#

	if _mouse_delta.length_squared() > 0.000001:
		forward = forward.rotated(up, _mouse_delta.x * rotate_speed)
		time_since_manual = 0.0
		pitch += _mouse_delta.y * pitch_speed
		pitch = clamp(pitch, min_pitch, max_pitch)
		_mouse_delta = Vector2.ZERO

	#
	# Automatic follow.
	#

	var velocity = target.linear_velocity
	velocity -= up * velocity.dot(up)

	if (
		time_since_manual > recenter_delay
		and velocity.length() > movement_threshold
	):

		forward = forward.slerp(
			velocity.normalized(),
			recenter_speed * delta
		).normalized()

	#
	# Build orientation.
	#

	var right = forward.cross(up).normalized()
	forward = up.cross(right).normalized()

	var mbasis = Basis(
		right,
		up,
		-forward
	)

	mbasis = mbasis.rotated(right, pitch)

	global_basis = Basis(
		global_basis
			.get_rotation_quaternion()
			.slerp(
				mbasis.get_rotation_quaternion(),
				rotation_smoothing * delta
			)
	)

	#
	# Follow target.
	#

	var desired = target.global_position + up * focus_height

	global_position = global_position.lerp(
		desired,
		position_smoothing * delta
	)
	
	rotation_changed.emit(global_basis)


func _camera_input() -> Vector2:

	return Input.get_vector(
		"camera_right",
		"camera_left",
		"camera_down",
		"camera_up"
	)


func get_forward(up: Vector3) -> Vector3:
	var f = (forward - up * forward.dot(up))
	return f.normalized()

func get_right(up: Vector3) -> Vector3:
	return -forward.cross(up).normalized()
