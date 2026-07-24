## On-screen virtual joysticks for mobile touch input.
## Left joystick: movement (WASD actions).
## Right joystick: camera (IJKL actions).
## Draws a base circle and a movable knob for each.
## Uses MOUSE_FILTER_IGNORE so UI buttons remain fully interactive.

extends Control
class_name TouchJoystick

@export var joystick_radius: float = 70.0
@export var knob_radius: float = 30.0
@export var camera_joystick_radius: float = 55.0
@export var camera_knob_radius: float = 24.0
@export var joystick_opacity: float = 0.55
@export var idle_opacity: float = 0.30
@export var idle_margin: float = 30.0

var _joystick_touch_idx: int = -1
var _joystick_center: Vector2 = Vector2.ZERO
var _knob_offset: Vector2 = Vector2.ZERO

var _cam_joy_touch_idx: int = -1
var _cam_joy_center: Vector2 = Vector2.ZERO
var _cam_knob_offset: Vector2 = Vector2.ZERO

var _virtual_enabled: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for action in ["move_left", "move_right", "move_back", "move_forward",
		"camera_left", "camera_right", "camera_down", "camera_up"]:
		assert(InputMap.has_action(action),
			"TouchJoystick: input action '%s' not found in InputMap" % action)


func set_virtual_enabled(enabled: bool) -> void:
	_virtual_enabled = enabled
	if not enabled:
		_release_all_move_actions()
		_release_all_camera_actions()
		_joystick_touch_idx = -1
		_cam_joy_touch_idx = -1
		_knob_offset = Vector2.ZERO
		_cam_knob_offset = Vector2.ZERO
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not _virtual_enabled:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	var viewport_size := get_viewport_rect().size
	var half_w := viewport_size.x * 0.5

	if event.pressed:
		if event.position.x < half_w and _joystick_touch_idx < 0:
			_joystick_touch_idx = event.index
			_joystick_center = event.position
			_knob_offset = Vector2.ZERO
			queue_redraw()
		elif event.position.x >= half_w and _cam_joy_touch_idx < 0:
			var jump_btn = get_node_or_null("../TouchJumpButton")
			if jump_btn and jump_btn.has_method("contains_point") and jump_btn.contains_point(event.position):
				pass  # let the jump button handle this touch
			else:
				_cam_joy_touch_idx = event.index
				_cam_joy_center = event.position
				_cam_knob_offset = Vector2.ZERO
				queue_redraw()
	else:
		if event.index == _joystick_touch_idx:
			_joystick_touch_idx = -1
			_knob_offset = Vector2.ZERO
			_release_all_move_actions()
			queue_redraw()
		if event.index == _cam_joy_touch_idx:
			_cam_joy_touch_idx = -1
			_cam_knob_offset = Vector2.ZERO
			_release_all_camera_actions()
			queue_redraw()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == _joystick_touch_idx:
		var delta := event.position - _joystick_center
		if delta.length() > joystick_radius:
			delta = delta.normalized() * joystick_radius
		_knob_offset = delta
		_apply_move_input(delta / joystick_radius)
		queue_redraw()
	elif event.index == _cam_joy_touch_idx:
		var delta := event.position - _cam_joy_center
		if delta.length() > camera_joystick_radius:
			delta = delta.normalized() * camera_joystick_radius
		_cam_knob_offset = delta
		_apply_camera_input(delta / camera_joystick_radius)
		queue_redraw()


func _apply_move_input(axis: Vector2) -> void:
	_set_action("move_right", maxf(0.0,  axis.x))
	_set_action("move_left",  maxf(0.0, -axis.x))
	_set_action("move_back",  maxf(0.0,  axis.y))
	_set_action("move_forward", maxf(0.0, -axis.y))


func _release_all_move_actions() -> void:
	for a in ["move_left", "move_right", "move_back", "move_forward"]:
		_set_action(a, 0.0)


func _apply_camera_input(axis: Vector2) -> void:
	_set_action("camera_right", maxf(0.0,  axis.x))
	_set_action("camera_left",  maxf(0.0, -axis.x))
	_set_action("camera_down",  maxf(0.0,  axis.y))
	_set_action("camera_up",    maxf(0.0, -axis.y))


func _release_all_camera_actions() -> void:
	for a in ["camera_left", "camera_right", "camera_down", "camera_up"]:
		_set_action(a, 0.0)


func _set_action(action: String, strength: float) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = strength > 0.05
	ev.strength = strength
	Input.parse_input_event(ev)


func _draw() -> void:
	if not _virtual_enabled:
		return

	var viewport_size := get_viewport_rect().size

	# Movement joystick (bottom-left).
	var move_idle := Vector2(
		idle_margin + joystick_radius,
		viewport_size.y - idle_margin - joystick_radius
	)
	if _joystick_touch_idx < 0:
		_draw_joystick(move_idle, idle_opacity, joystick_radius, knob_radius, Vector2.ZERO)
	else:
		_draw_joystick(_joystick_center, joystick_opacity, joystick_radius, knob_radius, _knob_offset)

	# Camera joystick (bottom-right, above the jump button).
	var cam_idle := Vector2(
		viewport_size.x - idle_margin - camera_joystick_radius,
		viewport_size.y - idle_margin - camera_joystick_radius - 110.0
	)
	if _cam_joy_touch_idx < 0:
		_draw_joystick(cam_idle, idle_opacity, camera_joystick_radius, camera_knob_radius, Vector2.ZERO)
	else:
		_draw_joystick(_cam_joy_center, joystick_opacity, camera_joystick_radius, camera_knob_radius, _cam_knob_offset)


func _draw_joystick(center: Vector2, opacity: float, radius: float, k_radius: float, knob_offset: Vector2) -> void:
	draw_circle(center, radius, Color(1, 1, 1, opacity * 0.4))
	draw_arc(center, radius, 0, TAU, 40, Color(1, 1, 1, opacity), 2.0)
	var knob_pos := center + knob_offset
	draw_circle(knob_pos, k_radius, Color(1, 1, 1, opacity * 0.7))
	draw_arc(knob_pos, k_radius, 0, TAU, 24, Color(1, 1, 1, opacity), 2.0)
