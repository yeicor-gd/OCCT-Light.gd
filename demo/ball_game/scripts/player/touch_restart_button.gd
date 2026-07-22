## On-screen virtual restart button for mobile touch input.
## Draws a small rounded button at the top-right corner of the screen.
## On touch, injects the "reset" InputEventAction.

extends Control
class_name TouchRestartButton

@export var button_size := Vector2(48.0, 32.0)
@export var button_opacity: float = 0.45
@export var margin_top: float = 50.0
@export var margin_right: float = 10.0

var _virtual_enabled: bool = true


func _ready() -> void:
	assert(InputMap.has_action("reset"),
		"TouchRestartButton: input action 'reset' not found in InputMap")

func set_virtual_enabled(enabled: bool) -> void:
	_virtual_enabled = enabled
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not _virtual_enabled:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _hit_test(event.position):
			_press_reset()
			_release_reset.call_deferred()


func _hit_test(pos: Vector2) -> bool:
	var rect := _get_rect()
	return rect.has_point(pos)


func _get_rect() -> Rect2:
	var viewport_size := get_viewport_rect().size
	var origin := Vector2(
		viewport_size.x - margin_right - button_size.x,
		margin_top
	)
	return Rect2(origin, Vector2(button_size.x, button_size.y))


func _press_reset() -> void:
	var ev := InputEventAction.new()
	ev.action = "reset"
	ev.pressed = true
	ev.strength = 1.0
	Input.parse_input_event(ev)
	print("Pressed reset")


func _release_reset() -> void:
	var ev := InputEventAction.new()
	ev.action = "reset"
	ev.pressed = false
	ev.strength = 0.0
	Input.parse_input_event(ev)
	print("Released reset")


func _draw() -> void:
	if not _virtual_enabled:
		return

	var rect := _get_rect()
	var color_bg := Color(1, 1, 1, button_opacity * 0.35)
	var color_border := Color(1, 1, 1, button_opacity)

	draw_rect(rect, color_bg)
	draw_rect(rect, color_border, false, 2.0)

	var font := ThemeDB.fallback_font
	var font_size := 14
	var text := "Reset"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := Vector2(
		rect.position.x + (rect.size.x - text_size.x) * 0.5,
		rect.position.y + (rect.size.y + text_size.y) * 0.4
	)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, button_opacity * 1.5))
