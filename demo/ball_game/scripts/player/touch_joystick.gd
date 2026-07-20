## On-screen virtual joystick + camera drag for mobile touch input.
## Draws a base circle and a movable knob on the left half of the screen;
## injects synthetic InputEventAction events for move_left/right/back/forward
## so ball.gd needs no changes.
## Also handles right-half touch → camera drag via camera actions.
## Uses MOUSE_FILTER_IGNORE so UI buttons remain fully interactive.

extends Control
class_name TouchJoystick

@export var joystick_radius: float = 70.0
@export var knob_radius: float = 30.0
@export var joystick_opacity: float = 0.55
@export var idle_opacity: float = 0.30
@export var idle_margin: float = 30.0

var _joystick_touch_idx: int = -1
var _joystick_center: Vector2 = Vector2.ZERO
var _knob_offset: Vector2 = Vector2.ZERO

var _camera_touch_idx: int = -1
var _camera_last_pos: Vector2 = Vector2.ZERO

var _virtual_enabled: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for action in ["move_left", "move_right", "move_back", "move_forward"]:
		assert(InputMap.has_action(action),
			"TouchJoystick: input action '%s' not found in InputMap" % action)


func set_virtual_enabled(enabled: bool) -> void:
	_virtual_enabled = enabled
	if not enabled:
		_release_all_move_actions()
		_release_all_camera_actions()
		_joystick_touch_idx = -1
		_camera_touch_idx = -1
		_knob_offset = Vector2.ZERO
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
		elif event.position.x >= half_w and _camera_touch_idx < 0:
			_camera_touch_idx = event.index
			_camera_last_pos = event.position
	else:
		if event.index == _joystick_touch_idx:
			_joystick_touch_idx = -1
			_knob_offset = Vector2.ZERO
			_release_all_move_actions()
			queue_redraw()
		if event.index == _camera_touch_idx:
			_camera_touch_idx = -1
			_release_all_camera_actions()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == _joystick_touch_idx:
		var delta := event.position - _joystick_center
		if delta.length() > joystick_radius:
			delta = delta.normalized() * joystick_radius
		_knob_offset = delta
		_apply_move_input(delta / joystick_radius)
		queue_redraw()
	elif event.index == _camera_touch_idx:
		var delta := event.position - _camera_last_pos
		_camera_last_pos = event.position
		var viewport_size := get_viewport_rect().size
		var norm_x := delta.x / (viewport_size.x * 0.5)
		var norm_y := delta.y / (viewport_size.y * 0.5)
		_apply_camera_input(Vector2(norm_x, norm_y))


func _apply_move_input(axis: Vector2) -> void:
	_set_action("move_right", maxf(0.0,  axis.x))
	_set_action("move_left",  maxf(0.0, -axis.x))
	_set_action("move_back",  maxf(0.0,  axis.y))
	_set_action("move_forward", maxf(0.0, -axis.y))


func _release_all_move_actions() -> void:
	for a in ["move_left", "move_right", "move_back", "move_forward"]:
		_set_action(a, 0.0)


func _apply_camera_input(delta: Vector2) -> void:
	_set_action("camera_right", maxf(0.0,  delta.x))
	_set_action("camera_left",  maxf(0.0, -delta.x))
	_set_action("camera_down",  maxf(0.0,  delta.y))
	_set_action("camera_up",    maxf(0.0, -delta.y))


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

	# Always draw the idle joystick in the bottom-left corner.
	var idle_center := Vector2(
		idle_margin + joystick_radius,
		viewport_size.y - idle_margin - joystick_radius
	)

	if _joystick_touch_idx < 0:
		# Idle state: draw at fixed corner with reduced opacity.
		_draw_joystick(idle_center, idle_opacity)
	else:
		# Active state: draw at touch position with full opacity.
		_draw_joystick(_joystick_center, joystick_opacity)


func _draw_joystick(center: Vector2, opacity: float) -> void:
	# Base circle
	draw_circle(center, joystick_radius,
		Color(1, 1, 1, opacity * 0.4))
	draw_arc(center, joystick_radius, 0, TAU, 40,
		Color(1, 1, 1, opacity), 2.0)
	# Knob
	var knob_pos := center + _knob_offset
	draw_circle(knob_pos, knob_radius, Color(1, 1, 1, opacity * 0.7))
	draw_arc(knob_pos, knob_radius, 0, TAU, 24,
		Color(1, 1, 1, opacity), 2.0)
