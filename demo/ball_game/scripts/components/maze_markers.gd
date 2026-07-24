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

@export_group("Concurrency")

## Maximum number of worker threads for marker generation (0 = unlimited).
@export var max_concurrent: int = 0

@export_group("Persistence")

## Base path for saving generated marker resources. Empty = memory-only.
@export var resource_save_path := "res://ball_game/generated/maze_markers"

@export_tool_button("Regenerate Markers") var regen_ = func(): _build_markers()

var _resolved_font: String = ""
var _is_regenerating: bool = false

func _ready():
	_resolved_font = _resolve_font()

func _exit_tree() -> void:
	_is_regenerating = false

func _build_markers(sync: bool = false):
	if _is_regenerating:
		push_warning("MazeMarkers: regeneration already in progress, skipping.")
		return
	_is_regenerating = true

	var start_time := Time.get_ticks_usec()

	# Idempotent: remove all existing children immediately (not queue_free).
	for child in get_children():
		remove_child(child)
		child.free()

	var gen := _find_generator()
	if gen == null:
		push_error("MazeMarkers: MazeGenerator parent not found")
		_is_regenerating = false
		return
	var paths = gen.get_node_or_null("Paths")
	if paths == null:
		push_error("MazeMarkers: MazeGenerator/Paths node not found")
		_is_regenerating = false
		return

	var main_path = paths.get_node_or_null("MainPath") as Path3D
	var aux_path = paths.get_node_or_null("MainPathBinormal") as Path3D
	if main_path == null or aux_path == null:
		push_error("MazeMarkers: Paths/MainPath or Paths/MainPathBinormal node not found")
		_is_regenerating = false
		return
	var curve = main_path.curve
	var aux_curve = aux_path.curve
	if curve == null or curve.point_count < 2:
		push_error("MazeMarkers: MainPath curve is null or has fewer than 2 points")
		_is_regenerating = false
		return

	var total_len = curve.get_baked_length()
	assert(total_len > 0.0, "MazeMarkers: MainPath curve has zero length")

	# Read shared config from the canonical source — OclMeshBuilder (Meshes).
	var meshes := gen.get_node_or_null("Meshes") as OclMeshBuilder
	var display_options: OclMeshOptions = meshes.display_options if meshes else OclMeshOptions.new()
	var eff_faces_material: Material = marker_faces_material if marker_faces_material else (meshes.display_faces_material if meshes else null)
	var eff_edges_material: Material = marker_edges_material if marker_edges_material else (meshes.display_edges_material if meshes else null)
	var eff_vertices_material: Material = marker_vertices_material if marker_vertices_material else (meshes.display_vertices_material if meshes else null)
	var eff_edge_rings: int = marker_edge_rings if marker_edge_rings > 0 else (meshes.edge_rings if meshes else 4)
	var eff_vertex_rings: int = marker_vertex_rings if marker_vertex_rings > 0 else (meshes.vertex_rings if meshes else 4)

	# Intermediate container — all generated markers go here so that
	# _persist_resources can save them as a single .scn.
	var container := Node3D.new()
	container.name = "Generated"
	add_child(container)
	if Engine.is_editor_hint():
		container.owner = get_tree().edited_scene_root if is_inside_tree() else null

	# ── Phase 1: precompute all placements (main thread — curve sampling is NOT thread-safe) ──
	var work_items: Array[Dictionary] = []

	# Main path markers at regular intervals (skip 0% and 100%).
	_collect_interval_items(work_items, curve, aux_curve, total_len, 0.0, 100.0)

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

			var sc_total_len := sc_curve.get_baked_length()
			_collect_interval_items(work_items, sc_curve, sc_aux_curve, sc_total_len, start_pct, end_pct)

	if work_items.is_empty():
		print("[MazeMarkers] No markers to build.")
		_is_regenerating = false
		return

	# ── Phase 2 + 3: dispatch workers and poll on main thread ──
	print("[MazeMarkers] Dispatching %d markers across WorkerThreadPool. Polling..." % work_items.size())

	# Capture member/config variables for worker closures (avoids main-thread-only bindings).
	var captured_font: String = _resolved_font
	var captured_text_height: float = text_height
	var captured_opts: OclMeshOptions = display_options
	var captured_edge_radius: float = marker_edge_radius
	var captured_vert_radius: float = marker_vertex_radius

	var scheduler := TaskScheduler.new(sync)
	scheduler.max_concurrent = max_concurrent

	for item in work_items:
		var captured_xf: Transform3D = item["xf"]
		var captured_label: String = item["label"]
		scheduler.dispatch_task(func():
			var result: Dictionary = _worker_build_marker(
				captured_xf, captured_label,
				captured_font, captured_text_height,
				captured_opts, captured_edge_radius, captured_vert_radius,
			)
			scheduler.submit_result(result)
		, false, "Marker")

	# Collect all results from workers.
	var results: Array[Dictionary] = []
	while true:
		scheduler.reap_completed()
		for res in scheduler.collect_all():
			results.append(res as Dictionary)
		if not scheduler.is_busy():
			break
		await get_tree().process_frame

	for res in scheduler.collect_all():
		results.append(res as Dictionary)

	# ── Phase 4: batch all results into merged geometry (main thread) ──
	var all_face_surfaces: Array = []
	var all_edge_xforms := PackedFloat64Array()
	var all_vert_xforms := PackedFloat64Array()

	for result in results:
		var f: Array = result.get("f", [])
		if not f.is_empty():
			all_face_surfaces.append_array(f)
		var e: PackedFloat64Array = result.get("e", PackedFloat64Array())
		if not e.is_empty():
			all_edge_xforms.append_array(e)
		var v: PackedFloat64Array = result.get("v", PackedFloat64Array())
		if not v.is_empty():
			all_vert_xforms.append_array(v)

	var has_faces := not all_face_surfaces.is_empty()
	var has_edges := all_edge_xforms.size() > 0
	var has_verts := all_vert_xforms.size() > 0

	# --- Merged faces node ---
	if has_faces:
		var merged: Array
		if all_face_surfaces.size() == 1:
			merged = all_face_surfaces[0]
			merged.resize(Mesh.ARRAY_MAX)
		else:
			merged = OclMeshToGodot.merge_surface_arrays(all_face_surfaces)
			merged.resize(Mesh.ARRAY_MAX)
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged)
		if eff_faces_material:
			am.surface_set_material(0, eff_faces_material)
		var mi := MeshInstance3D.new()
		mi.name = "MarkersMesh"
		mi.mesh = am
		container.add_child(mi, true)
		if Engine.is_editor_hint():
			mi.owner = get_tree().edited_scene_root if is_inside_tree() else null

	# --- Merged edges node ---
	if has_edges:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var cyl := CylinderMesh.new()
		cyl.height = 1.0
		cyl.radial_segments = eff_edge_rings
		cyl.rings = eff_edge_rings
		cyl.cap_top = false
		cyl.cap_bottom = false
		if eff_edges_material:
			cyl.surface_set_material(0, eff_edges_material)
		mm.mesh = cyl
		var n := int(all_edge_xforms.size() / 16.0)
		if n > 0:
			mm.instance_count = n
			for i in range(n):
				mm.set_instance_transform(i, OclMeshBuilder._decode_transform(all_edge_xforms, i))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "EdgesMesh"
		mmi.multimesh = mm
		container.add_child(mmi, true)
		if Engine.is_editor_hint():
			mmi.owner = get_tree().edited_scene_root if is_inside_tree() else null

	# --- Merged vertices node ---
	if has_verts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var sph := SphereMesh.new()
		sph.radius = 1.0
		sph.radial_segments = eff_edge_rings
		sph.rings = eff_vertex_rings
		if eff_vertices_material:
			sph.surface_set_material(0, eff_vertices_material)
		mm.mesh = sph
		var n := int(all_vert_xforms.size() / 16.0)
		if n > 0:
			mm.instance_count = n
			for i in range(n):
				mm.set_instance_transform(i, OclMeshBuilder._decode_transform(all_vert_xforms, i))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "VerticesMesh"
		mmi.multimesh = mm
		container.add_child(mmi, true)
		if Engine.is_editor_hint():
			mmi.owner = get_tree().edited_scene_root if is_inside_tree() else null

	print("[MazeMarkers] Built markers every %.0f%% in %.2f ms" % [interval_pct, (Time.get_ticks_usec() - start_time) / 1000.0])

	if Engine.is_editor_hint():
		_persist_resources()
	_is_regenerating = false


# =============================================================================
# Placement precomputation (main thread)
# =============================================================================

## Collect work items at every multiple of [interval_pct] in (pct_min, pct_max).
## [total_len] is the baked length of [curve] (spine).
func _collect_interval_items(
	items: Array[Dictionary],
	curve: Curve3D, aux_curve: Curve3D,
	total_len: float,
	pct_min: float, pct_max: float,
) -> void:
	var pct := ceilf(pct_min / interval_pct) * interval_pct
	if pct <= pct_min + 0.01:
		pct += interval_pct
	while pct < pct_max - 0.01:
		var frac := (pct - pct_min) / (pct_max - pct_min)
		var bl := total_len * frac
		var aux_bl := CurveUtils.aux_baked_for_spine(curve, aux_curve, bl) if aux_curve else 0.0
		# transform_at_baked only reads bake cache — safe on main thread.
		var xf := CurveUtils.transform_at_baked(curve, bl, true, aux_curve, aux_bl)
		items.append({
			"xf": xf,
			"label": "%.0f%%" % pct,
		})
		pct += interval_pct


# =============================================================================
# Worker function  (runs on WorkerThreadPool threads)
# =============================================================================

## Builds one marker's OCCT text geometry and tessellates it.
## Returns a Dictionary with serialized mesh data suitable for batching:
##   "f" : Array of surface arrays (face mesh data)
##   "e" : PackedFloat64Array of edge transforms
##   "v" : PackedFloat64Array of vertex transforms
static func _worker_build_marker(
	xf: Transform3D,
	label: String,
	font_path: String,
	text_height: float,
	opts: OclMeshOptions,
	edge_radius: float,
	vertex_radius: float,
) -> Dictionary:
	var result: Dictionary = {
		"f": [],
		"e": PackedFloat64Array(),
		"v": PackedFloat64Array(),
	}

	if font_path.is_empty():
		return result

	var graph = GraphUtils.create_graph()

	var info = OclTextInfo.new()
	info.set_utf8_text(label)
	info.set_height(text_height)
	info.set_font_path(font_path)
	info.set_font_aspect(OclText.TEXT_FONT_ASPECT_BOLD)
	info.set_horizontal_align(OclText.TEXT_HALIGN_CENTER)
	info.set_vertical_align(OclText.TEXT_VALIGN_CENTER)
	info.set_placement(OcctConversionUtils.transform3d_to_occt_placement(xf))

	var faces_id = OclNodeId.new()
	var st = OclText.make_faces(graph, info, faces_id)
	if st != OclCore.OK:
		OclTopo.graph_free(graph)
		return result

	# Extrude the text face into a solid via prism.
	var prism_info := OclPrimPrismInfo.new()
	prism_info.profile = faces_id.bits
	prism_info.direction = OcctConversionUtils.v3_to_ov3(xf.basis.z * 0.05)
	prism_info.copy = 1
	var extrude_id = OclNodeId.new()
	st = OclPrimSweep.prism(graph, prism_info, extrude_id)
	if st != OclCore.OK:
		OclTopo.graph_free(graph)
		return result

	OclTopoBuild.topo_remove_subgraph(graph, faces_id.bits)
	GraphUtils.delete_orphans(graph, [OclCore.KIND_SOLID], [OclCore.KIND_FACE])

	# --- Face mesh → extract surface arrays ---
	var tmp_am := ArrayMesh.new()
	st = OclMeshToGodot.mesh_faces(graph, tmp_am, opts, null, true, false, false)
	if st == OclCore.OK:
		result["f"] = MazeObstacles._extract_surface_arrays(tmp_am)

	# --- Edge transforms ---
	if edge_radius != 0.0:
		var e_mm := MultiMesh.new()
		if OclMeshToGodot.mesh_edges(graph, e_mm, opts, null, edge_radius) == OclCore.OK:
			result["e"] = MazeObstacles._extract_multimesh_transforms(e_mm)

	# --- Vertex transforms ---
	if vertex_radius != 0.0:
		var v_mm := MultiMesh.new()
		if OclMeshToGodot.mesh_vertices(graph, v_mm, opts, null, vertex_radius) == OclCore.OK:
			result["v"] = MazeObstacles._extract_multimesh_transforms(v_mm)

	OclTopo.graph_free(graph)
	return result


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
	push_error("MazeMarkers: MazeGenerator ancestor not found in parent chain")
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
