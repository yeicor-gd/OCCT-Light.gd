## On-screen virtual joystick for mobile touch input.
## Draws a base circle and a movable knob anywhere on the left half of the
## screen; injects synthetic InputEventAction events for move_left/right/
## back/forward so ball.gd needs no changes.
## Uses MOUSE_FILTER_IGNORE so UI buttons (Settings, Back, timer) on the right
## remain fully interactive through this transparent overlay.

extends Control
class_name TouchJoystick

@export var joystick_radius: float = 70.0
@export var knob_radius: float = 30.0
@export var joystick_opacity: float = 0.55

var _joystick_touch_idx: int = -1
var _joystick_center: Vector2 = Vector2.ZERO
var _knob_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	# IGNORE so touches on the right half propagate to UI controls normally.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for action in ["move_left", "move_right", "move_back", "move_forward"]:
		assert(InputMap.has_action(action),
			"TouchJoystick: input action '%s' not found in InputMap" % action)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	var half_w := get_viewport_rect().size.x * 0.5

	if event.pressed:
		# Only claim touches in the left half; leave the right half to UI.
		if event.position.x < half_w and _joystick_touch_idx < 0:
			_joystick_touch_idx = event.index
			_joystick_center = event.position
			_knob_offset = Vector2.ZERO
			queue_redraw()
	else:
		if event.index == _joystick_touch_idx:
			_joystick_touch_idx = -1
			_knob_offset = Vector2.ZERO
			_release_all_move_actions()
			queue_redraw()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index != _joystick_touch_idx:
		return
	var delta := event.position - _joystick_center
	if delta.length() > joystick_radius:
		delta = delta.normalized() * joystick_radius
	_knob_offset = delta
	_apply_move_input(delta / joystick_radius)
	queue_redraw()


func _apply_move_input(axis: Vector2) -> void:
	# axis is in [-1,1] for both components (joystick space: right=+X, down=+Y)
	_set_action("move_right", maxf(0.0,  axis.x))
	_set_action("move_left",  maxf(0.0, -axis.x))
	_set_action("move_back",  maxf(0.0,  axis.y))
	_set_action("move_forward", maxf(0.0, -axis.y))


func _release_all_move_actions() -> void:
	for a in ["move_left", "move_right", "move_back", "move_forward"]:
		_set_action(a, 0.0)


func _set_action(action: String, strength: float) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = strength > 0.05
	ev.strength = strength
	Input.parse_input_event(ev)


func _draw() -> void:
	if _joystick_touch_idx < 0:
		return
	# Base circle
	draw_circle(_joystick_center, joystick_radius,
		Color(1, 1, 1, joystick_opacity * 0.4))
	draw_arc(_joystick_center, joystick_radius, 0, TAU, 40,
		Color(1, 1, 1, joystick_opacity), 2.0)
	# Knob
	var knob_pos := _joystick_center + _knob_offset
	draw_circle(knob_pos, knob_radius, Color(1, 1, 1, joystick_opacity * 0.7))
	draw_arc(knob_pos, knob_radius, 0, TAU, 24,
		Color(1, 1, 1, joystick_opacity), 2.0)
