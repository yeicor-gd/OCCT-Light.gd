@tool
extends EditorPlugin

var export_plugin: EditorExportPlugin

func _enter_tree() -> void:
	export_plugin = preload("uid://b236curw5icqo").new()
	add_export_plugin(export_plugin)

func _exit_tree() -> void:
	if export_plugin:
		remove_export_plugin(export_plugin)
