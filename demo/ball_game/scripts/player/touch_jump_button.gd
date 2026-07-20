## On-screen virtual jump button for mobile touch input.
## Draws a wide rectangle (spacebar-style) at the bottom center of the screen.
## On touch, injects the "jump" InputEventAction so ball.gd needs no changes.

extends Control
class_name TouchJumpButton

@export var button_width: float = 160.0
@export var button_height: float = 56.0
@export var button_opacity: float = 0.45
@export var margin_bottom: float = 30.0

var _touch_idx: int = -1
var _pressed: bool = false
var _virtual_enabled: bool = true


func _ready() -> void:
	assert(InputMap.has_action("jump"),
		"TouchJumpButton: input action 'jump' not found in InputMap")


func set_virtual_enabled(enabled: bool) -> void:
	_virtual_enabled = enabled
	if not enabled and _pressed:
		_release_jump()
		_touch_idx = -1
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not _virtual_enabled:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _hit_test(event.position) and _touch_idx < 0:
			_touch_idx = event.index
			_pressed = true
			_press_jump()
			queue_redraw()
	else:
		if event.index == _touch_idx:
			_touch_idx = -1
			_pressed = false
			_release_jump()
			queue_redraw()


func _hit_test(pos: Vector2) -> bool:
	var rect := _get_rect()
	return rect.has_point(pos)


func _get_rect() -> Rect2:
	var viewport_size := get_viewport_rect().size
	var origin := Vector2(
		(viewport_size.x - button_width) * 0.5,
		viewport_size.y - margin_bottom - button_height
	)
	return Rect2(origin, Vector2(button_width, button_height))


func _press_jump() -> void:
	var ev := InputEventAction.new()
	ev.action = "jump"
	ev.pressed = true
	ev.strength = 1.0
	Input.parse_input_event(ev)


func _release_jump() -> void:
	var ev := InputEventAction.new()
	ev.action = "jump"
	ev.pressed = false
	ev.strength = 0.0
	Input.parse_input_event(ev)


func _draw() -> void:
	if not _virtual_enabled:
		return

	var rect := _get_rect()
	var color_bg := Color(1, 1, 1, button_opacity * 0.35 if not _pressed else button_opacity * 0.55)
	var color_border := Color(1, 1, 1, button_opacity if not _pressed else 0.8)
	var color_text := Color(1, 1, 1, button_opacity * 1.5 if not _pressed else 1.0)

	draw_rect(rect, color_bg)
	draw_rect(rect, color_border, false, 2.0)

	var font := ThemeDB.fallback_font
	var font_size := 18
	var text := "Jump"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := Vector2(
		rect.position.x + (rect.size.x - text_size.x) * 0.5,
		rect.position.y + (rect.size.y + text_size.y) * 0.5
	)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color_text)
