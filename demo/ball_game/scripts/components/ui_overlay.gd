extends CanvasLayer
class_name UIOverlay

enum GameState { IDLE, WON, LOST }

@onready var panel: PanelContainer = $CenterContainer/Panel
@onready var title: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/Title
@onready var message: RichTextLabel = $CenterContainer/Panel/MarginContainer/VBoxContainer/Message
@onready var hint: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/Hint

var _state: GameState = GameState.IDLE
var _share_button: Button = null


func _ready() -> void:
	hide_overlay()
	_share_button = Button.new()
	_share_button.text = "Share Challenge"
	_share_button.visible = false
	var vbox := $CenterContainer/Panel/MarginContainer/VBoxContainer
	vbox.add_child(_share_button)
	_share_button.pressed.connect(_on_share_pressed)

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
	if _state != GameState.IDLE:
		return
	_state = GameState.LOST
	title.text = "You lost!"
	message.visible = false
	_share_button.visible = false
	_show_common()

func show_game_won(time_secs: float):
	if _state != GameState.IDLE:
		return
	_state = GameState.WON
	title.text = "You won! 🏆"
	message.visible = true
	message.text = "Time: %.3f seconds" % time_secs
	_share_button.visible = true
	_share_button.text = "Share Challenge"
	_show_common()

func reset_state():
	_state = GameState.IDLE
	hide_overlay()

func hide_overlay():
	panel.hide()
	if _share_button:
		_share_button.visible = false


func _on_share_pressed() -> void:
	var maze := get_tree().root.find_child("Maze", true, false)
	if not maze or not (maze is MazeGenerator):
		return

	var config := {}
	config["MazeGenerator"] = _gather_node_exports(maze)
	if maze.has_node("Paths"):
		config["Paths"] = _gather_node_exports(maze.get_node("Paths"))
	if maze.has_node("Meshes"):
		config["Meshes"] = _gather_node_exports(maze.get_node("Meshes"))
	if maze.has_node("Obstacles"):
		config["Obstacles"] = _gather_node_exports(maze.get_node("Obstacles"))

	var base_url := "https://yeicor-gd.github.io/OCCT-Light.gd/gdext-tests.html"
	if OS.has_feature("web") and not OS.has_feature("desktop"):
		var current_url: String = str(JavaScriptBridge.eval("window.location.href.split('#')[0]", true))
		if not current_url.is_empty() and current_url.begins_with("http"):
			base_url = current_url
	var settings := get_tree().root.find_child("GameSettings", true, false)
	var url: String
	if settings and settings.is_default_config():
		url = base_url + "#ball_game_config="
	else:
		var json_str := JSON.stringify(config)
		var compressed := json_str.to_utf8_buffer()
		compressed = compressed.compress(FileAccess.COMPRESSION_GZIP)
		url = base_url + "#ball_game_config=" + _base64url_encode(compressed)

	var time_text := message.text
	var challenge := "Can you beat my time of %s in this maze?\n%s" % [time_text, url]
	DisplayServer.clipboard_set(challenge)
	_share_button.text = "Copied!"
	await get_tree().create_timer(2.0).timeout
	_share_button.text = "Share Challenge"


func _gather_node_exports(node: Node) -> Dictionary:
	var result := {}
	for p in node.get_property_list():
		var usage: int = p.get("usage", 0)
		if not ((usage & PROPERTY_USAGE_STORAGE) and (usage & PROPERTY_USAGE_EDITOR)):
			continue
		var _name: String = p["name"]
		if _name.begins_with("_") or _name == "script":
			continue
		var val = node.get(_name)
		if val is Resource:
			result[_name] = _serialize_resource(val)
		elif val is Object:
			continue
		else:
			result[_name] = val
	return result


func _serialize_resource(res: Resource) -> Dictionary:
	var result := {}
	for p in res.get_property_list():
		var usage: int = p.get("usage", 0)
		if not ((usage & PROPERTY_USAGE_STORAGE) and (usage & PROPERTY_USAGE_EDITOR)):
			continue
		var _name: String = p["name"]
		if _name.begins_with("_") or _name == "script":
			continue
		var val = res.get(_name)
		if val is Object:
			continue
		else:
			result[_name] = val
	return result


const _B64URL := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

func _base64url_encode(data: PackedByteArray) -> String:
	var result := ""
	var i := 0
	var n := data.size()
	while i + 2 < n:
		var b0 := data[i]
		var b1 := data[i + 1]
		var b2 := data[i + 2]
		result += _B64URL[b0 >> 2]
		result += _B64URL[((b0 & 3) << 4) | (b1 >> 4)]
		result += _B64URL[((b1 & 15) << 2) | (b2 >> 6)]
		result += _B64URL[b2 & 63]
		i += 3
	if i < n:
		var b0 := data[i]
		if i + 1 < n:
			var b1 := data[i + 1]
			result += _B64URL[b0 >> 2]
			result += _B64URL[((b0 & 3) << 4) | (b1 >> 4)]
			result += _B64URL[(b1 & 15) << 2]
		else:
			result += _B64URL[b0 >> 2]
			result += _B64URL[(b0 & 3) << 4]
	return result
