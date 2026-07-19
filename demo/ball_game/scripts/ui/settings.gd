## Full in-game settings panel.
##
## Builds its UI entirely from code so it auto-adapts when exported properties
## change — no .tscn maintenance required.
##
## Tabs:
##   0 Maze    — seed, presets, rope-length slider, regenerate button + progress
##   1 Advanced — full JSON editor for all exported properties of Maze + children
##   2 Controls — placeholder

extends MarginContainer
class_name GameSettings

# ── State ─────────────────────────────────────────────────────────────────────
var _gen: MazeGenerator = null
var _progress_label: Label = null
var _json_edit: TextEdit = null
var _base_outer: float = 20.0
var _base_inner: float = 10.0
var _base_node_count: int = 100

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # pass through when hidden
	_gen = _find_generator()
	if _gen:
		_base_outer = _gen.maze_outer_radius
		_base_inner = _gen.maze_inner_radius
		# Capture baseline node count from rope_physics
		var paths := _gen.get_node_or_null("Paths")
		if paths:
			var rp = paths.get("rope_physics")
			if rp:
				var nc = rp.get("node_count")
				if nc != null:
					_base_node_count = int(nc)
		# Connect generation signals for progress display
		var meshes := _gen.get_node_or_null("Meshes")
		if meshes and meshes.has_signal("generation_started"):
			meshes.generation_started.connect(_on_generation_started)
			meshes.generation_finished.connect(_on_generation_finished)
			if meshes.has_signal("chunk_completed"):
				meshes.chunk_completed.connect(_on_chunk_completed)

	_build_ui()


func _on_settings_button_pressed() -> void:
	visible = !visible
	# Block touch input to game while settings are open; pass through when hidden.
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
	if visible and _json_edit:
		_refresh_json()


func _on_close_settings_button_pressed() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var tabs := get_node_or_null("Settings") as TabContainer
	assert(tabs != null, "GameSettings: expected a TabContainer child named 'Settings'")

	# Remove the old placeholder tabs and rebuild
	for i in range(tabs.get_tab_count() - 1, -1, -1):
		tabs.get_child(i).queue_free()

	_build_maze_tab(tabs)
	_build_advanced_tab(tabs)
	_build_controls_tab(tabs)


func _vbox(parent: Control, label_text: String = "") -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = label_text if label_text != "" else "Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vb := VBoxContainer.new()
	vb.name = "VBox"
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	parent.add_child(scroll)
	return vb


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


func _build_maze_tab(tabs: TabContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Maze"
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
	_button(seed_row, "Daily",   func(): _set_seed(_daily_seed());  seed_edit.text = _gen.seed_source if _gen else "")
	_button(seed_row, "Weekly",  func(): _set_seed(_weekly_seed()); seed_edit.text = _gen.seed_source if _gen else "")
	_button(seed_row, "Monthly", func(): _set_seed(_monthly_seed()); seed_edit.text = _gen.seed_source if _gen else "")
	_button(seed_row, "Yearly",  func(): _set_seed(_yearly_seed()); seed_edit.text = _gen.seed_source if _gen else "")

	vb.add_child(HSeparator.new())

	# ── Presets ───────────────────────────────────────────────────────────────
	_label(vb, "Preset")
	var preset_row := _hrow(vb)
	_button(preset_row, "Fast",      func(): _apply_preset("fast"))
	_button(preset_row, "Normal",    func(): _apply_preset("normal"))
	_button(preset_row, "Cinematic", func(): _apply_preset("cinematic"))

	vb.add_child(HSeparator.new())

	# ── Rope length ───────────────────────────────────────────────────────────
	var len_label := _label(vb, "Rope Length: 100%")
	var len_slider := HSlider.new()
	len_slider.min_value = 20.0
	len_slider.max_value = 300.0
	len_slider.value = 100.0
	len_slider.step = 5.0
	len_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(len_slider)
	len_slider.value_changed.connect(func(v: float):
		len_label.text = "Rope Length: %.0f%%" % v
		_apply_rope_length(v))

	vb.add_child(HSeparator.new())

	# ── Progress ──────────────────────────────────────────────────────────────
	_progress_label = _label(vb, "")
	_progress_label.visible = false

	# ── Regenerate ────────────────────────────────────────────────────────────
	_button(vb, "Regenerate Maze", func(): _do_regenerate())


func _build_advanced_tab(tabs: TabContainer) -> void:
	var vb_root := VBoxContainer.new()
	vb_root.name = "Advanced"
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
	_button(btn_row, "Apply JSON", func(): _apply_json())
	_button(btn_row, "Copy",       func(): DisplayServer.clipboard_set(_json_edit.text))
	_button(btn_row, "Paste",      func():
		_json_edit.text = DisplayServer.clipboard_get()
		_apply_json())

	_refresh_json()


func _build_controls_tab(tabs: TabContainer) -> void:
	var vb_root := VBoxContainer.new()
	vb_root.name = "Controls"
	tabs.add_child(vb_root)
	var lbl := Label.new()
	lbl.text = "Keyboard/Gamepad:\n  WASD / Arrows — Move\n  Space — Jump\n  R — Respawn\n  IJKL — Camera\n\nTouch:\n  Left half — Joystick (move)\n  Right half — Drag (camera)"
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb_root.add_child(lbl)


# ── Seed helpers ──────────────────────────────────────────────────────────────

func _daily_seed() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]

func _weekly_seed() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-W%02d" % [d["year"], d["weekday"]]

func _monthly_seed() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d" % [d["year"], d["month"]]

func _yearly_seed() -> String:
	return str(Time.get_date_dict_from_system()["year"])

func _set_seed(seed: String) -> void:
	if _gen:
		_gen.seed_source = seed


# ── Preset logic ──────────────────────────────────────────────────────────────

func _apply_preset(name: String) -> void:
	assert(_gen != null, "GameSettings._apply_preset: MazeGenerator not found")
	var paths := _gen.get_node("Paths")
	var meshes := _gen.get_node("Meshes")
	match name:
		"fast":
			# Fastest generation: no shortcuts, no obstacles, no geometry validation.
			# Loft+non-fancy only, validation disabled so only hard OCCT errors cause retries.
			if paths:
				paths.set("total_shortcuts", 0)
				paths.set("camber_amount", 2.0)
			if meshes:
				meshes.set("sweep_shortcuts", false)
				meshes.set("clean_shortcuts", false)
				meshes.set("obstacle_positive_frequency", 0.0)
				meshes.set("obstacle_negative_frequency", 0.0)
				meshes.set("wall_height_noise_freq", 0.1)
				meshes.set("display_fancy", false)
				meshes.set("display_sweep_mode", 1)  # LOFT_RULED
				meshes.set("display_validate_geometry", false)
				meshes.set("physics_validate_geometry", false)
				meshes.set("display_edge_radius", 0.0)
				meshes.set("display_vertex_radius", 0.0)
				meshes.set("merge_batch_size", 32)
		"normal":
			# Balanced: shortcuts + obstacles, sweep+fancy for display, validation enabled.
			if paths:
				paths.set("total_shortcuts", 2)
				paths.set("camber_amount", 4.0)
			if meshes:
				meshes.set("sweep_shortcuts", true)
				meshes.set("clean_shortcuts", true)
				meshes.set("obstacle_positive_frequency", 0.05)
				meshes.set("obstacle_negative_frequency", 0.05)
				meshes.set("wall_height_noise_freq", 0.05)
				meshes.set("display_fancy", true)
				meshes.set("display_sweep_mode", 0)  # SWEEP
				meshes.set("display_validate_geometry", true)
				meshes.set("physics_validate_geometry", false)
				meshes.set("display_edge_radius", 0.01)
				meshes.set("display_vertex_radius", 0.02)
				meshes.set("merge_batch_size", 16)
		"cinematic":
			# Maximum quality: more shortcuts, obstacles, full validation including self-intersection.
			if paths:
				paths.set("total_shortcuts", 4)
				paths.set("camber_amount", 6.0)
			if meshes:
				meshes.set("sweep_shortcuts", true)
				meshes.set("clean_shortcuts", true)
				meshes.set("obstacle_positive_frequency", 0.1)
				meshes.set("obstacle_negative_frequency", 0.08)
				meshes.set("wall_height_noise_freq", 0.03)
				meshes.set("display_fancy", true)
				meshes.set("display_sweep_mode", 0)  # SWEEP
				meshes.set("physics_fancy", true)
				meshes.set("display_validate_geometry", true)
				meshes.set("physics_validate_geometry", true)
				meshes.set("display_edge_radius", 0.01)
				meshes.set("display_vertex_radius", 0.02)
				meshes.set("merge_batch_size", 8)


# ── Rope length ───────────────────────────────────────────────────────────────

func _apply_rope_length(pct: float) -> void:
	assert(_gen != null, "GameSettings._apply_rope_length: MazeGenerator not found")
	var scale := pct / 100.0
	_gen.maze_outer_radius = _base_outer * scale
	_gen.maze_inner_radius = _base_inner * scale
	# Scale rope node count proportionally using the baseline captured at startup
	var paths := _gen.get_node_or_null("Paths")
	if paths:
		var rp = paths.get("rope_physics")
		if rp:
			rp.set("node_count", maxi(10, int(_base_node_count * scale)))


# ── Regenerate ────────────────────────────────────────────────────────────────

func _do_regenerate() -> void:
	assert(_gen != null, "GameSettings: cannot regenerate — MazeGenerator not found")
	if _progress_label:
		_progress_label.text = "Regenerating…"
		_progress_label.visible = true
	_gen.regenerate_all(false)


# ── Progress callbacks ────────────────────────────────────────────────────────

var _total_chunks := 0
var _done_chunks := 0

func _on_generation_started(total: int) -> void:
	_total_chunks = total
	_done_chunks = 0
	if _progress_label:
		_progress_label.text = "Building… 0 / %d chunks" % total
		_progress_label.visible = true

func _on_chunk_completed(_idx: int, _name: String, _ms: float) -> void:
	_done_chunks += 1
	if _progress_label and _total_chunks > 0:
		_progress_label.text = "Building… %d / %d chunks" % [_done_chunks, _total_chunks]

func _on_generation_finished(total_ms: float, total: int, failed: int) -> void:
	if _progress_label:
		var msg := "Done in %.1f s (%d chunks" % [total_ms / 1000.0, total]
		if failed > 0: msg += ", %d failed" % failed
		msg += ")"
		_progress_label.text = msg


# ── JSON editor ───────────────────────────────────────────────────────────────

## Nodes whose exported properties are included in the JSON editor.
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
		# Only export properties that are actually stored and editor-visible
		if not ((usage & PROPERTY_USAGE_STORAGE) and (usage & PROPERTY_USAGE_EDITOR)):
			continue
		var name: String = p["name"]
		if name.begins_with("_") or name == "script":
			continue
		var val = node.get(name)
		# Skip objects/resources (too complex for JSON round-trip)
		if val is Object:
			continue
		result[name] = val
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
		for pname in props:
			node.set(pname, props[pname])


# ── Tree walk ─────────────────────────────────────────────────────────────────

func _find_generator() -> MazeGenerator:
	# Walk up siblings: Settings → MarginContainer → UI (Control) → World.
	# Maze is a sibling of UI under World.
	var p := get_parent()
	while p:
		var maze := p.get_node_or_null("Maze")
		if maze is MazeGenerator:
			return maze as MazeGenerator
		p = p.get_parent()
	# Fallback: scan the whole tree (covers unusual scene structures).
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(""):
			if node is MazeGenerator:
				return node as MazeGenerator
	push_error("GameSettings: MazeGenerator not found in scene tree")
	return null
