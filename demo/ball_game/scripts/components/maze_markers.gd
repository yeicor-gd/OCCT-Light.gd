@tool
extends Node3D
class_name MazeMarkers

@export_range(1.0, 50.0, 1.0) var interval_pct: float = 10.0
@export var text_height: float = 1.0
@export var font_path: String = "res://ball_game/fonts/SourceCodePro-Regular.ttf"

@export_group("Appearance")
## Optional material override for marker faces (uses faces material from Meshes if null).
@export var marker_faces_material: Material
## Optional material override for marker edges (uses edges material from Meshes if null).
@export var marker_edges_material: Material
## Optional material override for marker vertices (uses vertices material from Meshes if null).
@export var marker_vertices_material: Material
## Display edge radius for marker edges (< 0 = fixed, 0 = disabled).
@export var marker_edge_radius: float = 0.0
## Display vertex radius for marker vertices (< 0 = fixed, 0 = disabled).
@export var marker_vertex_radius: float = 0.0
## Number of longitudinal rings for edge cylinders (0 = use Mesher value).
@export_range(0, 16, 1) var marker_edge_rings: int = 0
## Number of latitudinal rings for vertex spheres (0 = use Mesher value).
@export_range(0, 16, 1) var marker_vertex_rings: int = 0

@export_group("Persistence")

## Base path for saving generated marker resources. Empty = memory-only.
@export var resource_save_path := "res://ball_game/generated/maze_markers"

@export_tool_button("Regenerate Markers") var regen_ = func(): _build_markers()

var _resolved_font: String = ""
# Resolved from Mesher at build time.
var _display_options: OclMeshOptions
var _eff_faces_material: Material
var _eff_edges_material: Material
var _eff_vertices_material: Material
var _eff_edge_rings: int
var _eff_vertex_rings: int

func _ready():
	_resolved_font = _resolve_font()

func _build_markers():
	var start_time := Time.get_ticks_usec()

	# Idempotent: remove all existing children immediately (not queue_free).
	for child in get_children():
		remove_child(child)
		child.free()

	var gen := _find_generator()
	if gen == null: return
	var paths = gen.get_node_or_null("Paths")
	if paths == null: return

	var main_path = paths.get_node_or_null("MainPath") as Path3D
	var aux_path = paths.get_node_or_null("MainPathBinormal") as Path3D
	if main_path == null or aux_path == null: return
	var curve = main_path.curve
	var aux_curve = aux_path.curve
	if curve == null or curve.point_count < 2: return

	var total_len = curve.get_baked_length()
	assert(total_len > 0.0, "MazeMarkers: MainPath curve has zero length")

	# Read shared config from the canonical source — OclMeshBuilder (Meshes).
	var meshes := gen.get_node_or_null("Meshes") as OclMeshBuilder
	_display_options = meshes.display_options if meshes else OclMeshOptions.new()
	_eff_faces_material = marker_faces_material if marker_faces_material else (meshes.display_faces_material if meshes else null)
	_eff_edges_material = marker_edges_material if marker_edges_material else (meshes.display_edges_material if meshes else null)
	_eff_vertices_material = marker_vertices_material if marker_vertices_material else (meshes.display_vertices_material if meshes else null)
	_eff_edge_rings = marker_edge_rings if marker_edge_rings > 0 else (meshes.edge_rings if meshes else 4)
	_eff_vertex_rings = marker_vertex_rings if marker_vertex_rings > 0 else (meshes.vertex_rings if meshes else 4)

	# Intermediate container — all generated markers go here so that
	# _persist_resources can save them as a single .scn.
	var container := Node3D.new()
	container.name = "Generated"
	add_child(container)
	if Engine.is_editor_hint():
		container.owner = get_tree().edited_scene_root if is_inside_tree() else null

	# Main path markers at regular intervals (skip 0% and 100%).
	var aux_total_len: float = aux_curve.get_baked_length() if aux_curve else 0.0
	_place_interval_markers(container, curve, aux_curve, aux_total_len, total_len, 0.0, 100.0)

	# Shortcut path markers — labeled with main-path percentages.
	var rope_physics: OclDemoOnlyRopePhysics = paths.get("rope_physics")
	for child in paths.get_children():
		if not child is Path3D:
			continue
		var cn := str(child.name)
		if cn.begins_with("Shortcut") and not cn.ends_with("Binormal"):
			var sc_curve: Curve3D = child.curve
			if sc_curve == null or sc_curve.point_count < 2:
				continue
			var sc_aux_node := paths.get_node_or_null(cn + "Binormal") as Path3D
			var sc_aux_curve: Curve3D = sc_aux_node.curve if sc_aux_node else null

			# Compute start/end percentages on the main rope.
			var sc_idx := cn.substr(7).to_int()
			var anchor_s := rope_physics.get_shortcut_start_anchor(sc_idx)
			var anchor_e := rope_physics.get_shortcut_end_anchor(sc_idx)
			assert(anchor_s >= 0 and anchor_s <= curve.point_count, "SC_IDX: %d -- anchor_s: %s (rebuild paths?)" % [sc_idx, anchor_s])
			var start_pct = _find_closest_baked_length(curve, curve.get_point_position(anchor_s)) / total_len * 100.0
			assert(anchor_e >= 0 and anchor_e <= curve.point_count, "SC_IDX: %d -- anchor_s: %s (rebuild paths?)" % [sc_idx, anchor_e])
			var end_pct = _find_closest_baked_length(curve, curve.get_point_position(anchor_e)) / total_len * 100.0

			# Place markers at round percentages of the main path that fall
			# strictly between the anchor endpoints, positioned along the
			# shortcut curve.
			var sc_total_len := sc_curve.get_baked_length()
			var sc_aux_total_len := sc_aux_curve.get_baked_length() if sc_aux_curve else 0.0
			_place_interval_markers(container, sc_curve, sc_aux_curve, sc_aux_total_len, sc_total_len, start_pct, end_pct)

	print("[MazeMarkers] Built markers every %.0f%% in %.2f ms" % [interval_pct, (Time.get_ticks_usec() - start_time) / 1000.0])

	if Engine.is_editor_hint():
		_persist_resources()


## Place markers at every multiple of [interval_pct] in (pct_min, pct_max).
## [total_len] is the baked length of [curve] (spine).  [aux_total_len]
## is the baked length of the auxiliary curve — used to sample the aux
## at the same progress as the spine so the binormal stays correct.
func _place_interval_markers(parent: Node3D, curve: Curve3D, aux_curve: Curve3D,
		aux_total_len: float, total_len: float,
		pct_min: float, pct_max: float) -> void:
	var pct := ceilf(pct_min / interval_pct) * interval_pct
	if pct <= pct_min + 0.01:
		pct += interval_pct
	while pct < pct_max - 0.01:
		var frac := pct / 100.0
		var bl := total_len * frac
		var aux_bl := aux_total_len * frac if aux_curve else 0.0
		var xf := CurveUtils.transform_at_baked(curve, bl, true, aux_curve, aux_bl)
		_build_marker(parent, xf, "%.0f%%" % pct)
		pct += interval_pct


func _build_marker(parent: Node3D, xf: Transform3D, label: String):
	if _resolved_font.is_empty():
		return

	var graph = GraphUtils.create_graph()

	var info = OclTextInfo.new()
	info.set_utf8_text(label)
	info.set_height(text_height)
	info.set_font_path(_resolved_font)
	info.set_font_aspect(OclText.TEXT_FONT_ASPECT_BOLD)
	info.set_horizontal_align(OclText.TEXT_HALIGN_CENTER)
	info.set_vertical_align(OclText.TEXT_VALIGN_CENTER)
	info.set_placement(OcctConversionUtils.transform3d_to_occt_placement(xf))

	var faces_id = OclNodeId.new()
	var st = OclText.make_faces(graph, info, faces_id)
	assert(st == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())])

	# Extrude the text face into a solid via prism.
	var prism_info := OclPrimPrismInfo.new()
	prism_info.profile = faces_id.bits
	prism_info.direction = OcctConversionUtils.v3_to_ov3(xf.basis.z * 0.05)
	prism_info.copy = 1
	var extrude_id = OclNodeId.new()
	st = OclPrimSweep.prism(graph, prism_info, extrude_id)
	assert(st == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())])

	st = OclTopoBuild.topo_remove_subgraph(graph, faces_id.bits)
	assert(st == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())])

	GraphUtils.delete_orphans(graph, [OclCore.KIND_SOLID], [OclCore.KIND_FACE])

	# Mesh options — use Mesher settings for consistency.
	var opts = OclMeshOptions.new()
	opts.set_deflection(_display_options.deflection if _display_options else 0.02)
	opts.set_angle(_display_options.angle if _display_options else 0.3)

	# --- Face mesh ---
	var am = ArrayMesh.new()
	st = OclMeshToGodot.mesh_faces(graph, am, opts, null, true, false, false)
	assert(st == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())])

	if _eff_faces_material:
		am.surface_set_material(0, _eff_faces_material)

	var mi := MeshInstance3D.new()
	mi.name = "Marker_%s" % label.replace("%", "pct")
	mi.mesh = am
	parent.add_child(mi)
	if Engine.is_editor_hint():
		mi.owner = get_tree().edited_scene_root if is_inside_tree() else null

	# --- Edge mesh ---
	if marker_edge_radius != 0.0 and _eff_edges_material:
		var e_mm := MultiMesh.new()
		if OclMeshToGodot.mesh_edges(graph, e_mm, opts, null, marker_edge_radius) == OclCore.OK and e_mm.instance_count > 0:
			var cyl := CylinderMesh.new()
			cyl.height = 1.0
			cyl.radial_segments = _eff_edge_rings
			cyl.rings = _eff_edge_rings
			cyl.cap_top = false
			cyl.cap_bottom = false
			cyl.surface_set_material(0, _eff_edges_material)
			e_mm.mesh = cyl
			var e_mmi := MultiMeshInstance3D.new()
			e_mmi.name = "Edges_%s" % label.replace("%", "pct")
			e_mmi.multimesh = e_mm
			parent.add_child(e_mmi)
			if Engine.is_editor_hint():
				e_mmi.owner = get_tree().edited_scene_root if is_inside_tree() else null

	# --- Vertex mesh ---
	if marker_vertex_radius != 0.0 and _eff_vertices_material:
		var v_mm := MultiMesh.new()
		if OclMeshToGodot.mesh_vertices(graph, v_mm, opts, null, marker_vertex_radius) == OclCore.OK and v_mm.instance_count > 0:
			var sph := SphereMesh.new()
			sph.radius = 1.0
			sph.radial_segments = _eff_edge_rings
			sph.rings = _eff_vertex_rings
			sph.surface_set_material(0, _eff_vertices_material)
			v_mm.mesh = sph
			var v_mmi := MultiMeshInstance3D.new()
			v_mmi.name = "Vertices_%s" % label.replace("%", "pct")
			v_mmi.multimesh = v_mm
			parent.add_child(v_mmi)
			if Engine.is_editor_hint():
				v_mmi.owner = get_tree().edited_scene_root if is_inside_tree() else null

	OclTopo.graph_free(graph)


func _find_closest_baked_length(curve: Curve3D, target_pos: Vector3) -> float:
	var baked_len := curve.get_baked_length()
	if baked_len < 0.001:
		return 0.0
	var best_len := 0.0
	var best_dist := INF
	var steps := 32
	for i in range(steps + 1):
		var frac := float(i) / float(steps)
		var bl := frac * baked_len
		var pos := curve.sample_baked(bl)
		var d := pos.distance_squared_to(target_pos)
		if d < best_dist:
			best_dist = d
			best_len = bl
	# Refine locally around the best sample.
	var lo := clampf(best_len - baked_len / float(steps), 0.0, baked_len)
	var hi := clampf(best_len + baked_len / float(steps), 0.0, baked_len)
	for i in range(16 + 1):
		var bl := lerpf(lo, hi, float(i) / 16.0)
		var pos := curve.sample_baked(bl)
		var d := pos.distance_squared_to(target_pos)
		if d < best_dist:
			best_dist = d
			best_len = bl
	return best_len

func _find_generator() -> MazeGenerator:
	var p = get_parent()
	while p:
		if p is MazeGenerator:
			return p
		p = p.get_parent()
	return null

func _resolve_font() -> String:
	# Prefer the configured path (supports res:// and user://).
	var p := ProjectSettings.globalize_path(font_path)
	if FileAccess.file_exists(p):
		return p
	# Fallback: system font path.
	var fallback := "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf"
	if FileAccess.file_exists(fallback):
		return fallback
	return ""


# -----------------------------------------------------------------------------
# Resource persistence
# -----------------------------------------------------------------------------

func _persist_resources() -> void:
	if resource_save_path.is_empty():
		return

	var base := resource_save_path.trim_suffix("/")
	var dir_abs := ProjectSettings.globalize_path(base)
	DirAccess.make_dir_recursive_absolute(dir_abs)

	var container := get_node_or_null("Generated") as Node3D
	if container == null:
		return

	var path := base + "/Generated.scn"
	_save_branch(container, path)

	# Hot-swap: replace the in-memory container with the persisted instance.
	var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var instance := packed.instantiate()
	instance.name = "Generated"

	var idx := container.get_index()
	remove_child(container)
	add_child(instance)
	move_child(instance, idx)
	instance.owner = get_tree().edited_scene_root if is_inside_tree() else null


func _save_branch(branch: Node, path: String) -> Error:
	for child in branch.get_children():
		_set_owner_recursive(child, branch)
	var packed := PackedScene.new()
	var err := packed.pack(branch)
	if err != OK:
		return err
	return ResourceSaver.save(packed, path)


func _set_owner_recursive(node: Node, mowner: Node) -> void:
	node.owner = mowner
	for child in node.get_children():
		_set_owner_recursive(child, mowner)
