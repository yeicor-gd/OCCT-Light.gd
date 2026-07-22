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
var _preset_fast_btn: Button = null
var _preset_normal_btn: Button = null
var _preset_custom_btn: Button = null
var _preset_group: ButtonGroup = null

# ── Generation overlay ───────────────────────────────────────────────────────
var _gen_overlay: MarginContainer = null
var _gen_label: Label = null
var _gen_bar: ProgressBar = null
var _gen_orbit_time: float = 0.0
var _gen_orbit_active: bool = false
var _gen_orbit_center: Vector3 = Vector3.ZERO
var _gen_orbit_radius: float = 0.0

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
		var paths := _gen.get_node("Paths")
		var rp = paths.get("rope_physics")
		var nc = rp.get("node_count")
		_base_node_count = int(nc)
		# Connect generation signals for progress display
		_gen.paths_generation_started.connect(_on_paths_started)
		_gen.paths_generation_finished.connect(_on_paths_finished)
		_gen.mesh_generation_finished.connect(_on_mesh_finished)
		var meshes := _gen.get_node("Meshes")
		if meshes.has_signal("generation_started"):
			meshes.generation_started.connect(_on_generation_started)
			if meshes.has_signal("chunk_completed"):
				meshes.chunk_completed.connect(_on_chunk_completed)

	_build_ui()
	_apply_preset("fast")

	# Find generation overlay nodes (added in ui.tscn)
	_gen_overlay = get_node_or_null("../GenerationOverlay") as MarginContainer
	if _gen_overlay:
		_gen_label = _gen_overlay.get_node("VBox/ProgressLabel") as Label
		_gen_bar = _gen_overlay.get_node("VBox/ProgressBar") as ProgressBar

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
	_preset_group = ButtonGroup.new()

	_preset_fast_btn = Button.new()
	_preset_fast_btn.text = "Fast"
	_preset_fast_btn.toggle_mode = true
	_preset_fast_btn.button_group = _preset_group
	_preset_fast_btn.pressed.connect(func(): _apply_preset("fast"))
	preset_row.add_child(_preset_fast_btn)

	_preset_normal_btn = Button.new()
	_preset_normal_btn.text = "Normal"
	_preset_normal_btn.toggle_mode = true
	_preset_normal_btn.button_group = _preset_group
	_preset_normal_btn.pressed.connect(func(): _apply_preset("normal"))
	preset_row.add_child(_preset_normal_btn)

	_preset_custom_btn = Button.new()
	_preset_custom_btn.text = "Custom"
	_preset_custom_btn.toggle_mode = true
	_preset_custom_btn.button_group = _preset_group
	_preset_custom_btn.pressed.connect(func(): (get_node("Settings") as TabContainer).current_tab = 1)  # Maze (advanced)
	preset_row.add_child(_preset_custom_btn)

	_preset_fast_btn.button_pressed = true  # Default

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
	_button(btn_row, "Apply JSON", func():
		(get_node("Settings") as TabContainer).current_tab = 0
		await _apply_json())
	_button(btn_row, "Copy",       func(): DisplayServer.clipboard_set(_json_edit.text))
	_button(btn_row, "Paste & Apply",      func():
		_json_edit.text = DisplayServer.clipboard_get()
		(get_node("Settings") as TabContainer).current_tab = 0
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

	# ── Native download hint (web only) ───────────────────────────────────
	if OS.has_feature("web"):
		var web_hint := Label.new()
		web_hint.text = "For better performance, download the native version for your platform:"
		web_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(web_hint)
		var link := LinkButton.new()
		link.text = "https://github.com/yeicor-gd/OCCT-Light.gd/actions"
		link.uri = "https://github.com/yeicor-gd/OCCT-Light.gd/actions"
		vb.add_child(link)
		vb.add_child(HSeparator.new())

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
	elif node is TouchRestartButton:
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
	push_error("GameSettings: AudioManager not found in scene tree")
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
	var obstacles := _gen.get_node("Obstacles")
	var markers := _gen.get_node("Markers")
	match _name:
		"fast":
			# Fastest generation: no shortcuts, no obstacles, no geometry validation.
			paths.set("total_shortcuts", 0)
			paths.set("camber_amount", 2.0)
			meshes.set("sweep_shortcuts", false)
			meshes.set("clean_shortcuts", false)
			meshes.set("wall_height_noise_freq", 0.1)
			meshes.set("display_fancy", false)
			meshes.set("display_sweep_mode", 1)  # LOFT_RULED
			meshes.set("display_validate_geometry", false)
			meshes.set("physics_validate_geometry", false)
			meshes.set("display_edge_radius", 0.0)
			meshes.set("display_vertex_radius", 0.0)
			meshes.set("merge_batch_size", 32)
			obstacles.set("obstacle_positive_frequency", 0.0)
			markers.set("marker_edge_radius", 0.0)
			markers.set("marker_vertex_radius", 0.0)
		"normal":
			# Match the editor-saved defaults (the @export values in the scripts).
			paths.set("total_shortcuts", 3)
			paths.set("camber_amount", 4.0)
			meshes.set("sweep_shortcuts", true)
			meshes.set("clean_shortcuts", true)
			meshes.set("wall_height_noise_freq", 0.05)
			meshes.set("display_fancy", true)
			meshes.set("display_sweep_mode", 0)  # SWEEP
			meshes.set("display_validate_geometry", true)
			meshes.set("physics_validate_geometry", false)
			meshes.set("display_edge_radius", -0.01)
			meshes.set("display_vertex_radius", -0.02)
			meshes.set("merge_batch_size", 16)
			obstacles.set("obstacle_positive_frequency", 0.1)
			obstacles.set("obstacle_debug_mode", false)
	_refresh_json()
	_apply_rope_length_no_regen(len_slider.value)
	_detect_preset()
	#_do_regenerate()


func _detect_preset() -> void:
	if not _gen or not _preset_fast_btn:
		return
	var paths := _gen.get_node("Paths")
	var meshes := _gen.get_node("Meshes")
	var obstacles := _gen.get_node("Obstacles")
	var markers := _gen.get_node("Markers")

	var matches_fast: bool = (
		int(paths.get("total_shortcuts")) == 0 and
		absf(paths.get("camber_amount") - 2.0) < 0.001 and
		meshes.get("sweep_shortcuts") == false and
		meshes.get("clean_shortcuts") == false and
		absf(meshes.get("wall_height_noise_freq") - 0.1) < 0.001 and
		meshes.get("display_fancy") == false and
		int(meshes.get("display_sweep_mode")) == 1 and
		meshes.get("display_validate_geometry") == false and
		meshes.get("physics_validate_geometry") == false and
		absf(meshes.get("display_edge_radius") - 0.0) < 0.001 and
		absf(meshes.get("display_vertex_radius") - 0.0) < 0.001 and
		int(meshes.get("merge_batch_size")) == 32 and
		absf(obstacles.get("obstacle_positive_frequency") - 0.0) < 0.001 and
		absf(markers.get("marker_edge_radius") - 0.0) < 0.001 and
		absf(markers.get("marker_vertex_radius") - 0.0) < 0.001
	)

	var matches_normal: bool = (
		int(paths.get("total_shortcuts")) == 3 and
		absf(paths.get("camber_amount") - 4.0) < 0.001 and
		meshes.get("sweep_shortcuts") == true and
		meshes.get("clean_shortcuts") == true and
		absf(meshes.get("wall_height_noise_freq") - 0.05) < 0.001 and
		meshes.get("display_fancy") == true and
		int(meshes.get("display_sweep_mode")) == 0 and
		meshes.get("display_validate_geometry") == true and
		meshes.get("physics_validate_geometry") == false and
		absf(meshes.get("display_edge_radius") - (-0.01)) < 0.001 and
		absf(meshes.get("display_vertex_radius") - (-0.02)) < 0.001 and
		int(meshes.get("merge_batch_size")) == 16 and
		absf(obstacles.get("obstacle_positive_frequency") - 0.1) < 0.001
	)

	if matches_fast:
		_preset_fast_btn.button_pressed = true
	elif matches_normal:
		_preset_normal_btn.button_pressed = true
	else:
		_preset_custom_btn.button_pressed = true


func is_default_config() -> bool:
	if not _gen:
		return false
	var paths := _gen.get_node("Paths")
	var meshes := _gen.get_node("Meshes")
	var obstacles := _gen.get_node("Obstacles")
	var markers := _gen.get_node("Markers")
	return (
		int(paths.get("total_shortcuts")) == 0 and
		absf(paths.get("camber_amount") - 2.0) < 0.001 and
		meshes.get("sweep_shortcuts") == false and
		meshes.get("clean_shortcuts") == false and
		absf(meshes.get("wall_height_noise_freq") - 0.1) < 0.001 and
		meshes.get("display_fancy") == false and
		int(meshes.get("display_sweep_mode")) == 1 and
		meshes.get("display_validate_geometry") == false and
		meshes.get("physics_validate_geometry") == false and
		absf(meshes.get("display_edge_radius") - 0.0) < 0.001 and
		absf(meshes.get("display_vertex_radius") - 0.0) < 0.001 and
		int(meshes.get("merge_batch_size")) == 32 and
		absf(obstacles.get("obstacle_positive_frequency") - 0.0) < 0.001 and
		absf(markers.get("marker_edge_radius") - 0.0) < 0.001 and
		absf(markers.get("marker_vertex_radius") - 0.0) < 0.001
	)


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

func _do_regenerate(orbit: bool = true) -> void:
	assert(_gen != null, "GameSettings: cannot regenerate \u2014 MazeGenerator not found")
	_paths_ms = 0.0
	_total_chunks = 0
	_done_chunks = 0

	if orbit:
		_start_gen_overlay("Generating paths\u2026", -1.0)
		_start_camera_orbit()
	else:
		if _progress_label:
			_progress_label.text = "Generating paths\u2026"
			_progress_label.visible = true

	await _gen.regenerate_all(false)

	if orbit:
		_finish_camera_orbit()
		_show_gen_overlay_done()
		await get_tree().create_timer(0.6).timeout
		_hide_gen_overlay()


func _start_gen_overlay(text: String, percent: float) -> void:
	if not _gen_overlay:
		return
	# Hide settings panel while generating.
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().paused = false
	_gen_overlay.visible = true
	if _gen_label:
		_gen_label.text = text
	if _gen_bar:
		if percent < 0.0:
			_gen_bar.indeterminate = true
			_gen_bar.value = 50.0
		else:
			_gen_bar.indeterminate = false
			_gen_bar.value = percent


func _update_gen_overlay(text: String, percent: float) -> void:
	if not _gen_overlay or not _gen_overlay.visible:
		return
	if _gen_label:
		_gen_label.text = text
	if _gen_bar:
		if percent < 0.0:
			if not _gen_bar.indeterminate:
				_gen_bar.indeterminate = true
				_gen_bar.value = 50.0
		else:
			_gen_bar.indeterminate = false
			_gen_bar.value = percent


func _show_gen_overlay_done() -> void:
	_update_gen_overlay(
		"Done in %.1fs (paths: %.1fs, geometry: %.1fs)" % [
			(_paths_ms + _last_mesh_ms) / 1000.0,
			_paths_ms / 1000.0,
			_last_mesh_ms / 1000.0],
		100.0)


func _hide_gen_overlay() -> void:
	if _gen_overlay:
		_gen_overlay.visible = false


# ── Camera orbit during generation ────────────────────────────────────────────

func _start_camera_orbit() -> void:
	var world := _gen.get_parent_node_3d()
	if not world:
		return

	# Hide the decorative rotatable scene; keep Maze visible.
	var rot_scene := world.get_node_or_null("RotatableScene") as Node3D
	if rot_scene:
		rot_scene.visible = false

	# Hide player during orbit.
	var player := world.get_node_or_null("Player") as Node3D
	if player:
		player.visible = false

	# Position camera for orbit.
	var cam_rig := _find_camera_rig()
	if not cam_rig:
		return
	cam_rig.orbit_mode = true

	_gen_orbit_center = Vector3.ZERO
	_gen_orbit_radius = _gen.maze_outer_radius * 1.8
	_gen_orbit_time = 0.0
	_gen_orbit_active = true

	# Start from back, looking at origin.
	cam_rig.global_position = _gen_orbit_center + Vector3(0, 0, _gen_orbit_radius)
	cam_rig.look_at(_gen_orbit_center, Vector3.UP)


func _finish_camera_orbit() -> void:
	_gen_orbit_active = false

	var world := _gen.get_parent_node_3d()
	if world:
		var player := world.get_node_or_null("Player") as Node3D
		if player:
			player.visible = true
		var rot_scene := world.get_node_or_null("RotatableScene") as Node3D
		if rot_scene:
			rot_scene.visible = false

	var cam_rig := _find_camera_rig()
	if cam_rig:
		cam_rig.orbit_mode = false


func _find_camera_rig() -> CameraRig:
	var world := _gen.get_parent_node_3d()
	if not world:
		return null
	var player := world.get_node_or_null("Player") as Node3D
	if not player:
		return null
	return player.get_node_or_null("CameraRig") as CameraRig


func _process(delta: float) -> void:
	if not _gen_orbit_active:
		return
	_gen_orbit_time += delta * 0.4

	var cam_rig := _find_camera_rig()
	if not cam_rig:
		return

	# Smooth orbit: sweep 120 degrees around the sphere.
	var angle := _gen_orbit_time
	var pos := _gen_orbit_center + Vector3(
		sin(angle) * _gen_orbit_radius,
		_gen_orbit_radius * 0.3,
		cos(angle) * _gen_orbit_radius
	)
	cam_rig.global_position = cam_rig.global_position.lerp(pos, 5.0 * delta)
	cam_rig.look_at(_gen_orbit_center, Vector3.UP)


# ── Progress callbacks ────────────────────────────────────────────────────────

var _total_chunks := 0
var _done_chunks := 0
var _last_mesh_ms := 0.0

func _on_paths_started() -> void:
	_update_gen_overlay("Generating paths\u2026", -1.0)
	if _progress_label:
		_progress_label.text = "Generating paths\u2026"
		_progress_label.visible = true

func _on_paths_finished(elapsed_ms: float) -> void:
	_paths_ms = elapsed_ms
	_update_gen_overlay("Building geometry\u2026", -1.0)
	if _progress_label:
		_progress_label.text = "Building geometry\u2026"

func _on_generation_started(total: int) -> void:
	_total_chunks = total
	_done_chunks = 0
	_update_gen_overlay("Building geometry\u2026 0 / %d chunks" % total, 0.0)
	if _progress_label:
		_progress_label.text = "Building geometry\u2026 0 / %d chunks" % total
		_progress_label.visible = true

func _on_chunk_completed(_idx: int, _name: String, _ms: float) -> void:
	_done_chunks += 1
	if _total_chunks > 0:
		var pct := float(_done_chunks) / float(_total_chunks) * 100.0
		_update_gen_overlay(
			"Building geometry\u2026 %d / %d chunks" % [_done_chunks, _total_chunks],
			pct)
	if _progress_label and _total_chunks > 0:
		_progress_label.text = "Building geometry\u2026 %d / %d chunks" % [_done_chunks, _total_chunks]

func _on_mesh_finished(total_ms: float, paths_ms: float, mesh_ms: float) -> void:
	_last_mesh_ms = mesh_ms
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
	result.append({"key": "Obstacles",     "node": _gen.get_node("Obstacles")})
	result.append({"key": "Markers",       "node": _gen.get_node("Markers")})
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
	await _do_regenerate(true)
	_detect_preset()


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
	# "" = no hash at all → normal startup, no auto-play.
	# "null" = hash present but empty value → use default map, skip regen.
	# "<json>" = hash present with config → apply config, regenerate.
	if json_text == "":
		return

	var has_config := json_text != "null" and not json_text.is_empty()

	if has_config:
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
		if _json_edit:
			_refresh_json()
		_detect_preset()
		# Regenerate with full overlay + camera orbit.
		await _do_regenerate(true)
	else:
		# Empty hash → default map, just show overlay briefly + respawn.
		_start_gen_overlay("Preparing\u2026", 100.0)
		await get_tree().create_timer(0.4).timeout
		_hide_gen_overlay()

	# Auto-play: sync positions, respawn, jump timer forward.
	if _gen:
		var death_area := _gen.get_node_or_null("DeathArea")
		if death_area and death_area.has_method("_sync_from_parent"):
			death_area._sync_from_parent()
		var end_area := _gen.get_node_or_null("EndArea")
		if end_area and end_area.has_method("_sync_from_parent"):
			end_area._sync_from_parent()
		var spawner := _gen.get_node_or_null("Spawner") as Spawner
		if spawner:
			spawner._sync_from_parent()
			spawner.respawn()
			spawner.start_usec = Time.get_ticks_usec() - 1000000  # 1 s head-start


func _read_auto_config() -> String:
	var env_val := OS.get_environment("MAZE_CONFIG")
	if not env_val.is_empty():
		return env_val
	if OS.has_feature("web"):
		var js_hash: String = str(JavaScriptBridge.eval("window.location.hash.substring(1)", true))
		if not js_hash.is_empty():
			return _parse_hash_config(js_hash)
	return ""


func _parse_hash_config(_hash: String) -> String:
	if _hash.begins_with("ball_game_config="):
		var payload := _hash.substr(17)  # len("ball_game_config=")
		if payload.is_empty():
			return "null"  # Signal: hash present, use defaults.
		return _decompress_config(payload)
	return ""


func _decompress_config(b64: String) -> String:
	var data := _base64url_decode(b64)
	if data.is_empty():
		return ""
	var decompressed := data.decompress(65536, FileAccess.COMPRESSION_GZIP)
	if decompressed.is_empty():
		push_warning("GameSettings: failed to decompress config")
		return ""
	return decompressed.get_string_from_utf8()


const _B64URL_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

func _base64url_decode(encoded: String) -> PackedByteArray:
	var lookup := {}
	for i in range(_B64URL_CHARS.length()):
		lookup[_B64URL_CHARS[i]] = i
	var result := PackedByteArray()
	var bits := 0
	var buf := 0
	for c in encoded:
		if not lookup.has(c):
			continue
		buf = (buf << 6) | lookup[c]
		bits += 6
		if bits >= 8:
			bits -= 8
			result.append((buf >> bits) & 0xFF)
	return result


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
	var restart_btn := _find_child_by_class(player, "TouchRestartButton")
	if restart_btn:
		restart_btn.set_virtual_enabled(vc_enabled)


func _apply_initial_audio_state() -> void:
	var muted: bool = _config.get_value("controls", "mute_audio", false)
	var audio := _find_audio_manager()
	if audio:
		audio.set_muted(muted)


func _find_child_by_class(node: Node, cls: String) -> Node:
	if (cls == "TouchJoystick" and node is TouchJoystick) or \
	   (cls == "TouchJumpButton" and node is TouchJumpButton) or \
	   (cls == "TouchRestartButton" and node is TouchRestartButton):
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
