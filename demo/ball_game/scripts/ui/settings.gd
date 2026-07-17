extends MarginContainer


func _ready():
	visible = false


func _on_settings_button_pressed() -> void:
	visible = !visible


func _on_close_settings_button_pressed() -> void:
	visible = false
