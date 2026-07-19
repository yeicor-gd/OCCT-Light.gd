## Bottom-right attempt timer.
## Counts up from the last spawn, stops and changes colour on win or death,
## and resets when the player respawns.

extends Label
class_name TimerHud

const COLOR_RUNNING := Color(1.0, 1.0, 1.0, 0.85)
const COLOR_WIN     := Color(0.2, 1.0, 0.3, 1.0)
const COLOR_DEATH   := Color(1.0, 0.25, 0.2, 1.0)

var _running := false
var _deps_ready := false

var _spawner: Spawner = null
var _overlay_panel: Control = null
var _overlay_title: Label = null


func _ready() -> void:
	modulate = COLOR_RUNNING
	text = "0:00.000"
	_running = false
	_resolve_deps.call_deferred()


func _resolve_deps() -> void:
	# Spawner lives at World/Maze/Spawner.
	var root := get_tree().get_root()
	var maze := root.find_child("Maze", true, false)
	assert(maze != null, "TimerHud: cannot find Maze node in scene tree")
	_spawner = maze.get_node("Spawner") as Spawner
	assert(_spawner != null, "TimerHud: Maze/Spawner not found or wrong type")

	# UIOverlay lives at World/UI/UIOverlay.
	var ui_overlay_node := root.find_child("UIOverlay", true, false)
	assert(ui_overlay_node != null, "TimerHud: cannot find UIOverlay node")
	_overlay_panel = ui_overlay_node.get_node("CenterContainer/Panel") as Control
	assert(_overlay_panel != null, "TimerHud: UIOverlay/CenterContainer/Panel not found")
	_overlay_title = ui_overlay_node.get_node(
		"CenterContainer/Panel/MarginContainer/VBoxContainer/Title") as Label
	assert(_overlay_title != null, "TimerHud: could not find Title label inside UIOverlay")

	_deps_ready = true
	_running = true  # start counting from scene load


func _process(_delta: float) -> void:
	if not _deps_ready:
		return

	var panel_visible := _overlay_panel.visible

	if panel_visible and _running:
		# Overlay just appeared — freeze the timer.
		_running = false
		var secs := _elapsed_secs()
		_update_text(secs)
		modulate = COLOR_WIN if "won" in _overlay_title.text.to_lower() else COLOR_DEATH
		return

	if not panel_visible and not _running:
		# Overlay was hidden — respawn happened; restart.
		_running = true
		modulate = COLOR_RUNNING

	if _running:
		_update_text(_elapsed_secs())


func _elapsed_secs() -> float:
	return (Time.get_ticks_usec() - _spawner.start_usec) / 1_000_000.0


func _update_text(secs: float) -> void:
	var s := maxf(secs, 0.0)
	var minutes := int(s) / 60
	var seconds := int(s) % 60
	var ms := int(fmod(s, 1.0) * 1000.0)
	text = "%d:%02d.%03d" % [minutes, seconds, ms]
