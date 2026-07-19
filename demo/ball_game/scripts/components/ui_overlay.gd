extends CanvasLayer
class_name UIOverlay

@onready var panel: PanelContainer = $CenterContainer/Panel
@onready var title: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/Title
@onready var message: RichTextLabel = $CenterContainer/Panel/MarginContainer/VBoxContainer/Message
@onready var hint: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/Hint

func _ready() -> void:
	hide_overlay()
	
func _get_reset_name():
	var reset_name := "Reset"
	var events := InputMap.action_get_events("reset")
	if not events.is_empty():
		reset_name = str(events.map(func(c): return c.as_text()))
	return reset_name

func _show_common():
	hint.text = "Press \"%s\" to restart." % _get_reset_name()
	panel.show()

func show_game_over():
	title.text = "You lost!"
	message.visible = false
	_show_common()

func show_game_won(time_secs: float):
	title.text = "You won! 🏆"
	message.visible = true
	message.text = "Time: %.3f seconds" % time_secs
	_show_common()

func hide_overlay():
	panel.hide()
