## Full in-game settings panel.
##
## Builds its UI entirely from code so it auto-adapts when exported properties
## change — no .tscn maintenance required.
##
## Tabs:
##   0 Maze (basic)    — seed, presets, rope-length slider, regenerate button + progress
##   1 Maze (advanced) — full JSON editor for all exported properties of Maze + children
##   2 Miscellaneous   — virtual controls toggle, audio mute, key bindings reference

extends MarginContainer
class_name GameSettings

const SETTINGS_PATH := "user://settings.cfg"

# ── State ─────────────────────────────────────────────────────────────────────
var _gen: MazeGenerator = null
var _progress_label: Label = null
var _json_edit: TextEdit = null
var _base_outer: float = -1.0
var _base_inner: float = -1.0
var _base_node_count: int = -1
var _config: ConfigFile = ConfigFile.new()
var _paths_ms: float = 0.0

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # pass through when hidden
	_load_config()
	_apply_initial_audio_state()
	_gen = _find_generator()
	if _gen:
		_base_outer = _gen.maze_outer_radius
		_base_inner = _gen.maze_inner_radius
		# Capture baseline node count from rope_physics
		var paths := _gen.get_node_or_null("Paths")
		var rp = paths.get("rope_physics")
		var nc = rp.get("node_count")
		_base_node_count = int(nc)
		# Connect generation signals for progress display
		_gen.paths_generation_started.connect(_on_paths_started)
		_gen.paths_generation_finished.connect(_on_paths_finished)
		_gen.mesh_generation_finished.connect(_on_mesh_finished)
		var meshes := _gen.get_node_or_null("Meshes")
		if meshes and meshes.has_signal("generation_started"):
			meshes.generation_started.connect(_on_generation_started)
			if meshes.has_signal("chunk_completed"):
				meshes.chunk_completed.connect(_on_chunk_completed)

	_build_ui()
	_auto_configure.call_deferred()


func _on_settings_button_pressed() -> void:
	visible = !visible
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
	get_tree().paused = visible
	if visible and _json_edit:
		_refresh_json()


func _on_close_settings_button_pressed() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().paused = false


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var tabs := get_node_or_null("Settings") as TabContainer
	assert(tabs != null, "GameSettings: expected a TabContainer child named 'Settings'")

	for i in range(tabs.get_tab_count() - 1, -1, -1):
		tabs.get_child(i).queue_free()

	_build_maze_tab(tabs)
	_build_advanced_tab(tabs)
	_build_misc_tab(tabs)


func _hrow(parent: Control) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(hb)
	return hb


func _label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# ── Maze (basic) tab ─────────────────────────────────────────────────────────

var len_slider := HSlider.new()
func _build_maze_tab(tabs: TabContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Maze (basic)"
	tabs.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	# ── Seed row ──────────────────────────────────────────────────────────────
	_label(vb, "Seed")
	var seed_row := _hrow(vb)
	var seed_edit := LineEdit.new()
	seed_edit.placeholder_text = "seed string"
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _gen: seed_edit.text = _gen.seed_source
	seed_edit.text_changed.connect(func(t: String):
		if _gen: _gen.seed_source = t)
	seed_row.add_child(seed_edit)
	_button(seed_row, "🎲", func(): _set_seed(_random_seed()); seed_edit.text = _gen.seed_source if _gen else "")
	_button(seed_row, "Daily",   func(): _set_seed(_daily_seed());  seed_edit.text = _gen.seed_source if _gen else "")
	_button(seed_row, "Weekly",  func(): _set_seed(_weekly_seed()); seed_edit.text = _gen.seed_source if _gen else "")
	_button(seed_row, "Monthly", func(): _set_seed(_monthly_seed()); seed_edit.text = _gen.seed_source if _gen else "")
	_button(seed_row, "Yearly",  func(): _set_seed(_yearly_seed()); seed_edit.text = _gen.seed_source if _gen else "")

	vb.add_child(HSeparator.new())

	# ── Presets ───────────────────────────────────────────────────────────────
	_label(vb, "Preset")
	var preset_row := _hrow(vb)
	_button(preset_row, "Normal", func(): _apply_preset("normal"))
	_button(preset_row, "Fast",   func(): _apply_preset("fast"))

	vb.add_child(HSeparator.new())

	# ── Rope length (log scale) ──────────────────────────────────────────────
	var len_label := _label(vb, "Rope Length: 100%")
	len_slider.min_value = 15.0
	len_slider.max_value = 1000.0
	len_slider.value = 100.0
	len_slider.step = 0.0  # continuous
	len_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	len_slider.tick_count = 7
	len_slider.ticks_on_borders = true
	vb.add_child(len_slider)
	len_slider.value_changed.connect(func(v: float):
		len_label.text = "Rope Length: %.0f%%" % v
		_apply_rope_length_no_regen(v))

	vb.add_child(HSeparator.new())

	# ── Progress ──────────────────────────────────────────────────────────────
	_progress_label = _label(vb, "")
	_progress_label.visible = false
	_progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# ── Regenerate ────────────────────────────────────────────────────────────
	_button(vb, "Regenerate Maze", func(): await _do_regenerate())


# ── Maze (advanced) tab ───────────────────────────────────────────────────────

func _build_advanced_tab(tabs: TabContainer) -> void:
	var vb_root := VBoxContainer.new()
	vb_root.name = "Maze (advanced)"
	vb_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(vb_root)

	_json_edit = TextEdit.new()
	_json_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_json_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_json_edit.custom_minimum_size = Vector2(0, 200)
	_json_edit.placeholder_text = "Properties JSON will appear here"
	vb_root.add_child(_json_edit)

	var btn_row := _hrow(vb_root)
	_button(btn_row, "Apply JSON", func(): await _apply_json())
	_button(btn_row, "Copy",       func(): DisplayServer.clipboard_set(_json_edit.text))
	_button(btn_row, "Paste & Apply",      func():
		_json_edit.text = DisplayServer.clipboard_get()
		await _apply_json())

	_refresh_json()


# ── Miscellaneous tab ─────────────────────────────────────────────────────────

func _build_misc_tab(tabs: TabContainer) -> void:
	var vb := VBoxContainer.new()
	vb.name = "Miscellaneous"
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.name = "Miscellaneous"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.add_child(vb)
	tabs.add_child(scroll)

	# ── Virtual Controls ──────────────────────────────────────────────────
	_label(vb, "Virtual Controls")
	var vc_row := _hrow(vb)
	var vc_info := Label.new()
	vc_info.text = "Show on-screen joystick & jump button"
	vc_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vc_row.add_child(vc_info)
	var vc_toggle := CheckButton.new()
	vc_toggle.button_pressed = _config.get_value("controls", "virtual_controls",
		OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"))
	vc_toggle.toggled.connect(_on_virtual_controls_toggled)
	vc_row.add_child(vc_toggle)

	vb.add_child(HSeparator.new())

	# ── Audio Mute ────────────────────────────────────────────────────────
	_label(vb, "Audio")
	var am_row := _hrow(vb)
	var am_info := Label.new()
	am_info.text = "Mute all audio"
	am_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	am_row.add_child(am_info)
	var am_toggle := CheckButton.new()
	am_toggle.button_pressed = _config.get_value("controls", "mute_audio", false)
	am_toggle.toggled.connect(_on_mute_audio_toggled)
	am_row.add_child(am_toggle)

	vb.add_child(HSeparator.new())

	# ── Key Bindings Reference ────────────────────────────────────────────
	var ref_label := Label.new()
	ref_label.text = "Keyboard/Gamepad:\n  WASD / Arrows \u2014 Move\n  Space \u2014 Jump\n  R \u2014 Respawn\n  IJKL \u2014 Camera\n\nTouch:\n  Left half \u2014 Joystick (move)\n  Right half \u2014 Drag (camera)"
	ref_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(ref_label)


func _on_virtual_controls_toggled(pressed: bool) -> void:
	_config.set_value("controls", "virtual_controls", pressed)
	_config.save(SETTINGS_PATH)
	_apply_virtual_controls(pressed)


func _apply_virtual_controls(enabled: bool) -> void:
	_apply_vc_recursive(get_tree().root, enabled)


func _apply_vc_recursive(node: Node, enabled: bool) -> void:
	if node is TouchJoystick:
		node.set_virtual_enabled(enabled)
	elif node is TouchJumpButton:
		node.set_virtual_enabled(enabled)
	for child in node.get_children():
		_apply_vc_recursive(child, enabled)


func _on_mute_audio_toggled(pressed: bool) -> void:
	_config.set_value("controls", "mute_audio", pressed)
	_config.save(SETTINGS_PATH)
	var audio := _find_audio_manager()
	if audio:
		audio.set_muted(pressed)


func _find_audio_manager() -> AudioManager:
	var p := get_parent()
	while p:
		var am := p.get_node_or_null("AudioManager")
		if am is AudioManager:
			return am as AudioManager
		p = p.get_parent()
	return null


# ── Seed helpers ──────────────────────────────────────────────────────────────

func _daily_seed() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]

func _random_seed() -> String:
	return "%08x" % randi()

func _weekly_seed() -> String:
	var d := Time.get_date_dict_from_system()
	var year: int = d["year"]
	var jan1 := Time.get_unix_time_from_datetime_dict({"year": year, "month": 1, "day": 1})
	var now := Time.get_unix_time_from_datetime_dict(d)
	var day_of_year := int((now - jan1) / 86400.0) + 1
	var jan1_iso_wday: int = (int(Time.get_datetime_dict_from_unix_time(jan1)["weekday"]) + 6) % 7
	var week_num: int = int((day_of_year + jan1_iso_wday + 6) / 7.0)
	return "%04d-W%02d" % [year, clampi(week_num, 1, 53)]

func _monthly_seed() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d" % [d["year"], d["month"]]

func _yearly_seed() -> String:
	return str(Time.get_date_dict_from_system()["year"])

func _set_seed(_seed: String) -> void:
	if _gen:
		_gen.seed_source = _seed


# ── Preset logic ──────────────────────────────────────────────────────────────

func _apply_preset(_name: String) -> void:
	assert(_gen != null, "GameSettings._apply_preset: MazeGenerator not found")
	var paths := _gen.get_node("Paths")
	var meshes := _gen.get_node("Meshes")
	match _name:
		"fast":
			# Fastest generation: no shortcuts, no obstacles, no geometry validation.
			if paths:
				paths.set("total_shortcuts", 0)
				paths.set("camber_amount", 2.0)
			if meshes:
				meshes.set("sweep_shortcuts", false)
				meshes.set("clean_shortcuts", false)
				meshes.set("obstacle_positive_frequency", 0.0)
				meshes.set("wall_height_noise_freq", 0.1)
				meshes.set("display_fancy", false)
				meshes.set("display_sweep_mode", 1)  # LOFT_RULED
				meshes.set("display_validate_geometry", false)
				meshes.set("physics_validate_geometry", false)
				meshes.set("display_edge_radius", 0.0)
				meshes.set("display_vertex_radius", 0.0)
				meshes.set("merge_batch_size", 32)
		"normal":
			# Match the editor-saved defaults (the @export values in the scripts).
			if paths:
				paths.set("total_shortcuts", 3)
				paths.set("camber_amount", 4.0)
			if meshes:
				meshes.set("sweep_shortcuts", true)
				meshes.set("clean_shortcuts", true)
				meshes.set("obstacle_positive_frequency", 0.1)
				meshes.set("wall_height_noise_freq", 0.05)
				meshes.set("display_fancy", true)
				meshes.set("display_sweep_mode", 0)  # SWEEP
				meshes.set("display_validate_geometry", true)
				meshes.set("physics_validate_geometry", false)
				meshes.set("display_edge_radius", -0.01)
				meshes.set("display_vertex_radius", -0.02)
				meshes.set("merge_batch_size", 16)
				meshes.set("obstacle_debug_mode", false)
	_refresh_json()
	_apply_rope_length_no_regen(len_slider.value)
	#_do_regenerate()


# ── Rope length ───────────────────────────────────────────────────────────────

func _apply_rope_length_no_regen(pct: float) -> void:
	assert(_gen != null, "GameSettings._apply_rope_length: MazeGenerator not found")

	const DEFAULT_SHORTCUTS := 2
	const SHORTCUT_NODE_FACTOR := 0.5 # Must match the ACTUAL average nodes generated per shortcut.

	var paths := _gen.get_node("Paths")
	var rp = paths.get("rope_physics")
	var shortcuts := int(paths.get("total_shortcuts"))

	var length_scale := pct / 100.0

	# Radius grows sub-linearly with rope length.
	#
	# Cube-root scaling makes the maze become cramped at large sizes,
	# while square-root scaling spreads it out too aggressively.
	# An exponent around 0.40 maintains a fairly consistent path density
	# across the supported range (50%–10000%).
	var radius_scale := pow(length_scale, 0.40)

	# Scale the playable area.
	_gen.maze_outer_radius = _base_outer * radius_scale
	_gen.maze_inner_radius = _base_inner * radius_scale

	# Keep the total rope length approximately constant after accounting
	# for shortcut ropes.
	var desired_total_nodes := (
		_base_node_count
		* length_scale
		* (1.0 + DEFAULT_SHORTCUTS * SHORTCUT_NODE_FACTOR)
	)

	var expected_shortcut_nodes := (
		_base_node_count
		* length_scale
		* SHORTCUT_NODE_FACTOR
		* shortcuts
	)

	var main_nodes := maxi(
		10,
		int(desired_total_nodes - expected_shortcut_nodes)
	)

	rp.set("node_count", main_nodes)

	print(
		"Rope: ", pct, "%",
		"  radius scale: ", radius_scale,
		"  main nodes: ", main_nodes,
		"  shortcuts: ", shortcuts,
		"  expected total: ", main_nodes + expected_shortcut_nodes,
		"  radius: ", _gen.maze_inner_radius, " → ", _gen.maze_outer_radius
	)


# ── Regenerate ────────────────────────────────────────────────────────────────

func _do_regenerate() -> void:
	assert(_gen != null, "GameSettings: cannot regenerate \u2014 MazeGenerator not found")
	if _progress_label:
		_progress_label.text = "Generating paths\u2026"
		_progress_label.visible = true
	_paths_ms = 0.0
	await _gen.regenerate_all(false)


# ── Progress callbacks ────────────────────────────────────────────────────────

var _total_chunks := 0
var _done_chunks := 0

func _on_paths_started() -> void:
	if _progress_label:
		_progress_label.text = "Generating paths\u2026"
		_progress_label.visible = true

func _on_paths_finished(elapsed_ms: float) -> void:
	_paths_ms = elapsed_ms
	if _progress_label:
		_progress_label.text = "Building geometry\u2026"

func _on_generation_started(total: int) -> void:
	_total_chunks = total
	_done_chunks = 0
	if _progress_label:
		_progress_label.text = "Building geometry\u2026 0 / %d chunks" % total
		_progress_label.visible = true

func _on_chunk_completed(_idx: int, _name: String, _ms: float) -> void:
	_done_chunks += 1
	if _progress_label and _total_chunks > 0:
		_progress_label.text = "Building geometry\u2026 %d / %d chunks" % [_done_chunks, _total_chunks]

func _on_mesh_finished(total_ms: float, paths_ms: float, mesh_ms: float) -> void:
	if _progress_label:
		_progress_label.text = "Done in %.1fs (paths: %.1fs, geometry: %.1fs)" % [
			total_ms / 1000.0, paths_ms / 1000.0, mesh_ms / 1000.0]


# ── JSON editor ───────────────────────────────────────────────────────────────

func _json_nodes() -> Array[Dictionary]:
	assert(_gen != null, "GameSettings._json_nodes: MazeGenerator not found")
	var result: Array[Dictionary] = []
	result.append({"key": "MazeGenerator", "node": _gen})
	result.append({"key": "Paths",         "node": _gen.get_node("Paths")})
	result.append({"key": "Meshes",        "node": _gen.get_node("Meshes")})
	return result


func _gather_exports(node: Node) -> Dictionary:
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


func _refresh_json() -> void:
	if not _json_edit: return
	var all := {}
	for entry in _json_nodes():
		all[entry["key"]] = _gather_exports(entry["node"])
	_json_edit.text = JSON.stringify(all, "\t")


func _apply_json() -> void:
	if not _json_edit: return
	var parsed = JSON.parse_string(_json_edit.text)
	if not parsed is Dictionary:
		push_warning("GameSettings: invalid JSON")
		return
	var node_map := {}
	for entry in _json_nodes():
		node_map[entry["key"]] = entry["node"]
	for key in parsed:
		if not node_map.has(key):
			continue
		var node: Node = node_map[key]
		var props: Dictionary = parsed[key]
		_apply_dict_to_obj(node, props)
	_refresh_json()
	await _do_regenerate()


func _apply_dict_to_obj(obj: Object, props: Dictionary) -> void:
	for pname in props:
		var val = props[pname]
		var cur = obj.get(pname)
		if cur is Material or cur is Texture2D:
			continue
		if val is Dictionary and cur is Resource:
			_apply_dict_to_obj(cur, val)
		else:
			obj.set(pname, val)


# ── Auto-configure from environment / URL hash ────────────────────────────────

func _auto_configure() -> void:
	var json_text := _read_auto_config()
	if json_text.is_empty():
		return
	var parsed = JSON.parse_string(json_text)
	if not parsed is Dictionary:
		push_warning("GameSettings: MAZE_CONFIG is not a valid JSON object")
		return
	var node_map := {}
	for entry in _json_nodes():
		node_map[entry["key"]] = entry["node"]
	for key in parsed:
		if not node_map.has(key):
			continue
		var node: Node = node_map[key]
		var props: Dictionary = parsed[key]
		_apply_dict_to_obj(node, props)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().paused = true
	if _json_edit:
		_refresh_json()
	await _do_regenerate()


func _read_auto_config() -> String:
	var env_val := OS.get_environment("MAZE_CONFIG")
	if not env_val.is_empty():
		return env_val
	if OS.has_feature("web"):
		var js_val: String = str(JavaScriptBridge.eval("window.location.hash.substring(1)", true))
		if not js_val.is_empty():
			return _parse_hash_config(js_val)
		var params: String = str(JavaScriptBridge.eval(
			"new URLSearchParams(window.location.search).get('config') || ''", true))
		if not params.is_empty():
			return params
	return ""


func _parse_hash_config(_hash: String) -> String:
	if _hash.begins_with("{"):
		return _hash
	var result := {}
	for pair in _hash.split("&", false):
		var kv := pair.split("=", 2)
		if kv.size() == 2:
			result[kv[0]] = kv[1]
	if result.is_empty():
		return ""
	return JSON.stringify(result)


# ── Config persistence ────────────────────────────────────────────────────────

func _load_config() -> void:
	_config.load(SETTINGS_PATH)


func apply_to_player(player: Node) -> void:
	var vc_enabled: bool = _config.get_value("controls", "virtual_controls",
		OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"))
	var joystick := _find_child_by_class(player, "TouchJoystick")
	if joystick:
		joystick.set_virtual_enabled(vc_enabled)
	var jump_btn := _find_child_by_class(player, "TouchJumpButton")
	if jump_btn:
		jump_btn.set_virtual_enabled(vc_enabled)


func _apply_initial_audio_state() -> void:
	var muted: bool = _config.get_value("controls", "mute_audio", false)
	var audio := _find_audio_manager()
	if audio:
		audio.set_muted(muted)


func _find_child_by_class(node: Node, cls: String) -> Node:
	if (cls == "TouchJoystick" and node is TouchJoystick) or \
	   (cls == "TouchJumpButton" and node is TouchJumpButton):
		return node
	for child in node.get_children():
		var result := _find_child_by_class(child, cls)
		if result:
			return result
	return null


# ── Tree walk ─────────────────────────────────────────────────────────────────

func _find_generator() -> MazeGenerator:
	var p := get_parent()
	while p:
		var maze := p.get_node_or_null("Maze")
		if maze is MazeGenerator:
			return maze as MazeGenerator
		p = p.get_parent()
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(""):
			if node is MazeGenerator:
				return node as MazeGenerator
	push_error("GameSettings: MazeGenerator not found in scene tree")
	return null
