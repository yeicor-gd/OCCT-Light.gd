@tool
extends Node3D
class_name MazeObstacles

## Standalone obstacle generation node.
## Generates positive obstacles (boxes or scripted shapes) along all path pairs,
## independent of the tube mesh generation.
## Uses TaskScheduler + WorkerThreadPool for parallel OCCT geometry build.

@export_group("Obstacles")

## Frequency of positive obstacles along the track (obstacles per segment unit).
@export_range(0.0, 0.5, 0.01) var obstacle_positive_frequency: float = 0.1
## Seed offset for obstacle randomisation.
@export var obstacle_seed_offset: int = 0
## Debug mode: always adds boxes instead of obstacle shapes, for visualising placement.
@export var obstacle_debug_mode: bool = false
## Debug: max rotation multiplier [0-1] applied to obstacle placement (0 = axis-aligned, 1 = full).
@export_range(0.0, 1.0, 0.01) var obstacle_debug_max_rotation: float = 1.0
## Debug: max offset multiplier [0-1] applied to obstacle placement.
@export var obstacle_debug_max_offset: Vector2 = Vector2(1.0, 1.0)
## Debug: min offset multiplier [0-1] applied to force minimum displacement.
@export var obstacle_debug_min_offset: Vector2 = Vector2(0.0, 0.0)

@export_group("Appearance")
## Optional material override for obstacle faces (uses faces material from Meshes if null).
@export var obstacle_material: Material
## Optional material override for obstacle edges (uses edges material from Meshes if null).
@export var obstacle_edges_material: Material
## Optional material override for obstacle vertices (uses vertices material from Meshes if null).
@export var obstacle_vertices_material: Material
## Display edge radius (< 0 = fixed, 0 = disabled).
@export var obstacle_edge_radius: float = -0.01
## Display vertex radius (< 0 = fixed, 0 = disabled).
@export var obstacle_vertex_radius: float = -0.02
## Number of longitudinal rings for edge cylinders (0 = use Mesher value).
@export_range(0, 16, 1) var obstacle_edge_rings: int = 0
## Number of latitudinal rings for vertex spheres (0 = use Mesher value).
@export_range(0, 16, 1) var obstacle_vertex_rings: int = 0

@export_group("Physics")
## Generate collision shapes from obstacle face triangles.
@export var physics_show_faces: bool = true

@export_group("Concurrency")

## Maximum number of worker threads for obstacle generation (0 = unlimited).
@export var max_concurrent: int = 0

@export_group("Persistence")

## Base path for saving generated obstacle resources. Empty = memory-only.
@export var resource_save_path := "res://ball_game/generated/maze_obstacles"

@export_tool_button("Regenerate Obstacles") var regen_ = func(): _build_obstacles()

# State — resolved from sibling Meshes (OclMeshBuilder) at build time.
var _wall_height_cdf: Curve
var _wall_height_noise: FastNoiseLite
var _is_regenerating: bool = false

func _ready():
	pass

func _exit_tree() -> void:
	_is_regenerating = false

func _ensure_wall_height_cdf(source: Curve):
	if source == null:
		source = Curve.new()
		source.add_point(Vector2(0.0, 0.0))
		source.add_point(Vector2(0.5, 0.8))
		source.add_point(Vector2(1.0, 1.5))
	_wall_height_cdf = source

func _sample_wall_height(noise_input: float) -> float:
	if not is_finite(noise_input):
		return 0.8
	var n := _wall_height_noise.get_noise_1d(noise_input)
	if not is_finite(n):
		return 0.8
	var t := clampf(n * 0.5 + 0.5, 0.0, 1.0)
	var h := _wall_height_cdf.sample(t)
	if not is_finite(h):
		return 0.8
	return h

func _build_obstacles(sync: bool = false):
	if _is_regenerating:
		push_warning("MazeObstacles: regeneration already in progress, skipping.")
		return
	_is_regenerating = true

	var start_time := Time.get_ticks_usec()

	# Idempotent: remove all existing children immediately (not queue_free).
	for child in get_children():
		remove_child(child)
		child.free()

	var gen := _find_generator()
	assert(gen != null, "MazeObstacles: MazeGenerator parent not found")
	var paths := gen.get_node_or_null("Paths")
	assert(paths != null, "MazeObstacles: MazeGenerator/Paths node not found")
	var main_path := paths.get_node_or_null("MainPath") as Path3D
	assert(main_path != null, "MazeObstacles: Paths/MainPath node not found")
	var main_aux := paths.get_node_or_null("MainPathBinormal") as Path3D
	assert(main_aux != null, "MazeObstacles: Paths/MainPathBinormal node not found")

	# Read shared config from the canonical source — OclMeshBuilder (Meshes).
	var meshes := gen.get_node_or_null("Meshes") as OclMeshBuilder
	assert(meshes != null, "MazeObstacles: MazeGenerator/Meshes node not found")
	var wall_thickness: float = meshes.wall_thickness
	var wall_height_noise_freq: float = meshes.wall_height_noise_freq
	var display_options: OclMeshOptions = meshes.display_options
	var display_faces_material: Material = meshes.display_faces_material
	var display_edges_material: Material = meshes.display_edges_material
	var display_vertices_material: Material = meshes.display_vertices_material
	var eff_edge_rings: int = obstacle_edge_rings if obstacle_edge_rings > 0 else meshes.edge_rings
	var eff_vertex_rings: int = obstacle_vertex_rings if obstacle_vertex_rings > 0 else meshes.vertex_rings

	# Intermediate container — all generated children go here so that
	# _persist_resources can save them as a single .scn (keeping subresources
	# out of the local .tscn).
	var container := Node3D.new()
	container.name = "Generated"
	add_child(container)
	if Engine.is_editor_hint():
		container.owner = get_tree().edited_scene_root if is_inside_tree() else null

	if obstacle_positive_frequency <= 0.0:
		print("[MazeObstacles] Frequency is 0, skipping.")
		_is_regenerating = false
		return

	var obstacle_scripts := _discover_obstacle_scripts()
	if obstacle_scripts.is_empty():
		print("[MazeObstacles] No obstacle scripts found.")
		_is_regenerating = false
		return

	var profile_cfg := ProfileBuilder.Config.new(
		gen.ball_radius,
		gen.ball_to_path_min_ratio,
		wall_thickness,
	)

	_ensure_wall_height_cdf(meshes.wall_height_cdf)
	_wall_height_noise = FastNoiseLite.new()
	_wall_height_noise.seed = gen.seed_value + obstacle_seed_offset
	_wall_height_noise.frequency = wall_height_noise_freq
	_wall_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	# Collect path pairs.
	var path_pairs := _collect_path_pairs(paths)

	# ── Phase 1: precompute all placements (main thread — curve sampling is NOT thread-safe) ──
	var work_items: Array[Dictionary] = []
	var total_obstacles := 0

	for pair in path_pairs:
		var path_curve: Curve3D = pair["path"].curve
		var aux_curve: Curve3D = pair["aux"].curve
		var pair_name: String = pair["name"]
		var seg_count := path_curve.point_count - 1
		if seg_count <= 0:
			continue

		# Precompute per-segment wall heights.
		var pair_baked_len := path_curve.get_baked_length()
		var segment_wall_heights := PackedFloat32Array()
		segment_wall_heights.resize(path_curve.point_count)
		for si in range(path_curve.point_count):
			var t := float(si) / float(maxi(path_curve.point_count - 1, 1))
			segment_wall_heights[si] = _sample_wall_height(t * pair_baked_len)

		var num_obstacles := maxi(1, int(seg_count * obstacle_positive_frequency))
		var br: float = profile_cfg.ball_radius
		var bd: float = 2.0 * br
		var ratio := profile_cfg.ball_to_path_min_ratio
		var inner_hw: float = bd / ratio.x * 0.5
		var inner_h: float = bd / ratio.y
		var clearance: float = inner_hw - br
		var max_floor_h: float = br * 0.4
		var max_wall_d: float = clearance

		var rng := RandomNumberGenerator.new()
		rng.seed = gen.seed_value + obstacle_seed_offset + pair_name.length() * 7919

		for obs_i in range(num_obstacles):
			var t_val := (obs_i + 0.5) / num_obstacles
			var seg_idx := int(t_val * seg_count)
			seg_idx = clampi(seg_idx, 0, path_curve.point_count - 2)
			# transform_at_index only reads control points — safe for main thread.
			var xf := CurveUtils.transform_at_index(path_curve, seg_idx, aux_curve)

			var wall_h: float = clampf(segment_wall_heights[seg_idx], 0.0, 1.0)
			var wh_clamped: float = minf(wall_h, 1.0) * inner_h

			var surface: int = [Surface.FLOOR, Surface.LEFT_WALL, Surface.RIGHT_WALL][rng.randi() % 3]

			var local_pos := Vector3.ZERO
			var aabb_size := Vector3.ZERO
			var local_normal := Vector3(0, 1, 0)
			var angle: float = rng.randf() * TAU * obstacle_debug_max_rotation
			var cos_a: float = cos(angle)
			var sin_a: float = sin(angle)

			match surface:
				Surface.FLOOR:
					var h: float = rng.randf_range(0.2, 0.5) * max_floor_h
					var sx: float = rng.randf_range(0.3, 0.8) * br
					var sz: float = rng.randf_range(0.3, 0.8) * br
					aabb_size = Vector3(sx, h, sz)
					var lateral_x: float = sx * abs(cos_a) + sz * abs(sin_a)
					var min_ox: float = minf(0.0, minf(sx * cos_a, minf(sz * sin_a, sx * cos_a + sz * sin_a)))
					var cx_max: float = inner_hw - lateral_x * 0.5
					var x_frac: float = clampf(rng.randf_range(obstacle_debug_min_offset.x, obstacle_debug_max_offset.x), 0.0, 1.0)
					var cx: float = x_frac * cx_max * (1.0 if rng.randi() % 2 == 0 else -1.0)
					var y_pos: float = -br
					local_pos = Vector3(cx - min_ox - lateral_x * 0.5, y_pos, 0.0)
				Surface.LEFT_WALL, Surface.RIGHT_WALL:
					var h: float = rng.randf_range(0.3, 0.8) * minf(wh_clamped, br * 0.6)
					var protrusion: float = rng.randf_range(0.5, 1.0) * max_wall_d
					var length: float = rng.randf_range(0.6, 1.0) * br
					aabb_size = Vector3(protrusion, h, length)
					var eff_x: float = protrusion * abs(cos_a) + length * abs(sin_a)
					if eff_x > clearance:
						var s: float = clearance / eff_x
						protrusion *= s
						length *= s
						aabb_size = Vector3(protrusion, h, length)
						eff_x = clearance
					var min_ox: float = minf(0.0, minf(protrusion * cos_a, minf(length * sin_a, protrusion * cos_a + length * sin_a)))
					var cx: float
					if surface == Surface.LEFT_WALL:
						cx = -(inner_hw + br) * 0.5
					else:
						cx = (inner_hw + br) * 0.5
					var y_range: float = wh_clamped - h
					var y_frac: float = clampf(rng.randf_range(obstacle_debug_min_offset.y, obstacle_debug_max_offset.y), 0.0, 1.0) if y_range > 0 else 0.5
					var y_pos: float = -br + y_frac * y_range
					local_pos = Vector3(cx - min_ox - eff_x * 0.5, y_pos, 0.0)

			var rot_basis := Basis(local_normal.normalized(), angle)
			var obs_xf := xf.translated_local(local_pos)
			obs_xf.basis = xf.basis * rot_basis
			var obs_aabb := AABB(Vector3.ZERO, aabb_size)

			# Skip zero-volume obstacles (can happen with extreme random params).
			if aabb_size.x <= 0.0 or aabb_size.y <= 0.0 or aabb_size.z <= 0.0:
				continue

			work_items.append({
				"xf": obs_xf,
				"aabb": obs_aabb,
				"node_name": "%s_Obs%d" % [pair_name if pair_name else "Main", total_obstacles],
			})
			total_obstacles += 1

	if work_items.is_empty():
		print("[MazeObstacles] No obstacles to build.")
		_is_regenerating = false
		return

	# ── Phase 2 + 3: dispatch workers and poll on main thread ──
	print("[MazeObstacles] Dispatching %d obstacles across WorkerThreadPool. Polling..." % work_items.size())

	# Capture member/config variables for worker closures (avoids main-thread-only bindings).
	var captured_debug_mode: bool = obstacle_debug_mode
	var captured_scripts: Array[Script] = obstacle_scripts
	var captured_opts: OclMeshOptions = display_options
	var captured_edge_radius: float = obstacle_edge_radius
	var captured_vert_radius: float = obstacle_vertex_radius

	var scheduler := TaskScheduler.new(sync)
	scheduler.max_concurrent = max_concurrent

	for item in work_items:
		var captured_xf: Transform3D = item["xf"]
		var captured_aabb: AABB = item["aabb"]
		var captured_name: String = item["node_name"]
		scheduler.dispatch_task(func():
			var result: Dictionary = _worker_build_obstacle(
				captured_xf, captured_aabb,
				captured_debug_mode, captured_scripts,
				captured_opts, captured_edge_radius, captured_vert_radius,
			)
			result["node_name"] = captured_name
			scheduler.submit_result(result)
		, false, "Obstacle")

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
	var all_face_tris := PackedVector3Array()

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
		var pf: PackedVector3Array = result.get("pf", PackedVector3Array())
		if pf.size() >= 3:
			all_face_tris.append_array(pf)

	var has_faces := not all_face_surfaces.is_empty()
	var has_edges := all_edge_xforms.size() > 0
	var has_verts := all_vert_xforms.size() > 0
	var has_physics := all_face_tris.size() >= 3

	# --- Merged faces node ---
	if has_faces or has_physics:
		var faces_root: Node3D
		if has_physics:
			faces_root = StaticBody3D.new()
		else:
			faces_root = Node3D.new()
		faces_root.name = "Faces"
		container.add_child(faces_root, true)
		if Engine.is_editor_hint():
			faces_root.owner = get_tree().edited_scene_root if is_inside_tree() else null

		if has_physics:
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(all_face_tris)
			var cs := CollisionShape3D.new()
			cs.name = "CollisionFaces"
			cs.shape = shape
			faces_root.add_child(cs, true)
			if Engine.is_editor_hint():
				cs.owner = get_tree().edited_scene_root if is_inside_tree() else null

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
			var obs_mat: Material = obstacle_material if obstacle_material else display_faces_material
			if obs_mat:
				am.surface_set_material(0, obs_mat)
			var mi := MeshInstance3D.new()
			mi.name = "FacesMesh"
			mi.mesh = am
			faces_root.add_child(mi, true)
			if Engine.is_editor_hint():
				mi.owner = get_tree().edited_scene_root if is_inside_tree() else null

	# --- Merged edges node ---
	if has_edges:
		var edges_node := Node3D.new()
		edges_node.name = "Edges"
		container.add_child(edges_node, true)
		if Engine.is_editor_hint():
			edges_node.owner = get_tree().edited_scene_root if is_inside_tree() else null

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var cyl := CylinderMesh.new()
		cyl.height = 1.0
		cyl.radial_segments = eff_edge_rings
		cyl.rings = eff_edge_rings
		cyl.cap_top = false
		cyl.cap_bottom = false
		var e_mat: Material = obstacle_edges_material if obstacle_edges_material else display_edges_material
		if e_mat:
			cyl.surface_set_material(0, e_mat)
		mm.mesh = cyl
		var n := int(all_edge_xforms.size() / 16.0)
		if n > 0:
			mm.instance_count = n
			for i in range(n):
				mm.set_instance_transform(i, OclMeshBuilder._decode_transform(all_edge_xforms, i))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "EdgesMesh"
		mmi.multimesh = mm
		edges_node.add_child(mmi, true)
		if Engine.is_editor_hint():
			mmi.owner = get_tree().edited_scene_root if is_inside_tree() else null

	# --- Merged vertices node ---
	if has_verts:
		var verts_node := Node3D.new()
		verts_node.name = "Vertices"
		container.add_child(verts_node, true)
		if Engine.is_editor_hint():
			verts_node.owner = get_tree().edited_scene_root if is_inside_tree() else null

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var sph := SphereMesh.new()
		sph.radius = 1.0
		sph.radial_segments = eff_vertex_rings
		sph.rings = eff_vertex_rings
		var v_mat: Material = obstacle_vertices_material if obstacle_vertices_material else display_vertices_material
		if v_mat:
			sph.surface_set_material(0, v_mat)
		mm.mesh = sph
		var n := int(all_vert_xforms.size() / 16.0)
		if n > 0:
			mm.instance_count = n
			for i in range(n):
				mm.set_instance_transform(i, OclMeshBuilder._decode_transform(all_vert_xforms, i))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "VerticesMesh"
		mmi.multimesh = mm
		verts_node.add_child(mmi, true)
		if Engine.is_editor_hint():
			mmi.owner = get_tree().edited_scene_root if is_inside_tree() else null

	print("[MazeObstacles] Built %d obstacles in %.2f ms" % [total_obstacles, (Time.get_ticks_usec() - start_time) / 1000.0])

	if Engine.is_editor_hint():
		_persist_resources()
	_is_regenerating = false


# =============================================================================
# Worker function  (runs on WorkerThreadPool threads)
# =============================================================================

## Builds one obstacle's OCCT geometry and tessellates it.
## Returns a Dictionary with serialized mesh data suitable for batching:
##   "f"  : Array of surface arrays (face mesh data)
##   "e"  : PackedFloat64Array of edge transforms
##   "v"  : PackedFloat64Array of vertex transforms
##   "pf" : PackedVector3Array of face triangles for physics
static func _worker_build_obstacle(
	obs_xf: Transform3D,
	obs_aabb: AABB,
	debug_mode: bool,
	obstacle_scripts: Array[Script],
	opts: OclMeshOptions,
	edge_radius: float,
	vertex_radius: float,
) -> Dictionary:
	var result: Dictionary = {
		"f": [],
		"e": PackedFloat64Array(),
		"v": PackedFloat64Array(),
		"pf": PackedVector3Array(),
	}

	# Create a fresh graph for this obstacle.
	var graph = GraphUtils.create_graph()
	var obs_bits: PackedInt64Array
	var status: OclCore.status
	if debug_mode:
		var box_info := OclPrimBoxInfo.new()
		box_info.placement = OcctConversionUtils.transform3d_to_occt_placement(obs_xf)
		box_info.dx = obs_aabb.size.x
		box_info.dy = obs_aabb.size.y
		box_info.dz = obs_aabb.size.z
		var box_id := OclNodeId.new()
		status = OclPrimSolid.box(graph, box_info, box_id) as OclCore.status
		if status != OclCore.OK:
			OclTopo.graph_free(graph)
			return result
		obs_bits = PackedInt64Array([box_id.get_bits()])
	else:
		# Pick a random obstacle script. Use a hash of the transform for determinism.
		var idx := hash(Vector4(obs_xf.origin.x, obs_xf.origin.y, obs_xf.origin.z, obs_aabb.size.x)) % obstacle_scripts.size()
		obs_bits = obstacle_scripts[idx].build(graph, obs_aabb, obs_xf)

	if obs_bits.is_empty():
		OclTopo.graph_free(graph)
		return result

	# --- Face mesh → extract surface arrays ---
	var tmp_am := ArrayMesh.new()
	status = OclMeshToGodot.mesh_faces(graph, tmp_am, opts, null, true, false, false) as OclCore.status
	if status == OclCore.OK:
		result["f"] = _extract_surface_arrays(tmp_am)

	# --- Edge transforms ---
	if edge_radius != 0.0:
		var e_mm := MultiMesh.new()
		if OclMeshToGodot.mesh_edges(graph, e_mm, opts, null, edge_radius) == OclCore.OK:
			result["e"] = _extract_multimesh_transforms(e_mm)

	# --- Vertex transforms ---
	if vertex_radius != 0.0:
		var v_mm := MultiMesh.new()
		if OclMeshToGodot.mesh_vertices(graph, v_mm, opts, null, vertex_radius) == OclCore.OK:
			result["v"] = _extract_multimesh_transforms(v_mm)

	# --- Face triangles for physics ---
	result["pf"] = OclMeshToGodot.extract_face_triangles(graph, opts, null)

	OclTopo.graph_free(graph)
	return result


# Surface type for obstacle placement.
enum Surface { FLOOR, LEFT_WALL, RIGHT_WALL }


func _collect_path_pairs(paths: Node3D) -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	var path: Path3D = paths.get_node_or_null("MainPath") as Path3D
	var aux_path: Path3D = paths.get_node_or_null("MainPathBinormal") as Path3D
	if path and aux_path:
		pairs.append({ "name": "", "path": path, "aux": aux_path })

	for child in paths.get_children():
		if not child is Path3D:
			continue
		var cn := str(child.name)
		if cn.begins_with("Shortcut") and not cn.ends_with("Binormal"):
			var sc_aux_name := cn + "Binormal"
			var sc_aux := paths.get_node_or_null(sc_aux_name) as Path3D
			if sc_aux:
				pairs.append({ "name": cn + "_", "path": child, "aux": sc_aux })
	return pairs


func _discover_obstacle_scripts() -> Array[Script]:
	var scripts: Array[Script] = []
	var dir := DirAccess.open("res://ball_game/scripts/components/obstacles")
	if dir != null:
		dir.list_dir_begin()
		while true:
			var fname := dir.get_next()
			if fname == "":
				break
			if dir.current_is_dir():
				continue
			if not fname.begins_with("obstacle_") or not fname.ends_with(".gd"):
				continue
			if fname == "obstacle_base.gd" or fname == "obstacle_index.gd":
				continue
			var path := "res://ball_game/scripts/components/obstacles/" + fname
			var script := load(path)
			if script is Script and script.has_method("build"):
				scripts.append(script)
		dir.list_dir_end()
		return scripts
	var entries := ObstacleIndex.get_all()
	for e in entries:
		scripts.append(e["script"])
	return scripts


func _find_generator() -> MazeGenerator:
	var p = get_parent()
	while p:
		if p is MazeGenerator:
			return p
		p = p.get_parent()
	push_error("MazeObstacles: MazeGenerator ancestor not found in parent chain")
	return null


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
	var parent := container.get_parent()
	if parent == null:
		return
	var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var instance := packed.instantiate()
	instance.name = "Generated"

	var idx := container.get_index()
	parent.remove_child(container)
	parent.add_child(instance)
	parent.move_child(instance, idx)
	# Keep the parent's owner (like ocl_mesh_builder) so PackedScene.pack keeps
	# the instance as an ext_resource reference.  edited_scene_root is null
	# during headless exports, which used to drop obstacles/markers entirely.
	instance.owner = parent.owner


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


# =============================================================================
# Worker helpers (static, shared with MazeMarkers)
# =============================================================================

## Extract face surface arrays from an ArrayMesh for later merging.
static func _extract_surface_arrays(am: ArrayMesh) -> Array:
	var result: Array = []
	for surf_idx in range(am.get_surface_count()):
		var arrays := am.surface_get_arrays(surf_idx)
		arrays.resize(Mesh.ARRAY_MAX)
		result.append(arrays)
	return result


## Encode all instance transforms from a MultiMesh into a PackedFloat64Array
## (16 doubles per transform, column-major Basis + origin).
static func _extract_multimesh_transforms(mm: MultiMesh) -> PackedFloat64Array:
	var n: int = mm.instance_count
	if n == 0:
		return PackedFloat64Array()
	var out: PackedFloat64Array = PackedFloat64Array()
	out.resize(n * 16)
	for i in range(n):
		var t: Transform3D = mm.get_instance_transform(i)
		var b: Basis = t.basis
		var o: Vector3 = t.origin
		var base: int = i * 16
		out[base + 0]  = b.x.x
		out[base + 1]  = b.y.x
		out[base + 2]  = b.z.x
		out[base + 3]  = 0.0
		out[base + 4]  = b.x.y
		out[base + 5]  = b.y.y
		out[base + 6]  = b.z.y
		out[base + 7]  = 0.0
		out[base + 8]  = b.x.z
		out[base + 9]  = b.y.z
		out[base + 10] = b.z.z
		out[base + 11] = 0.0
		out[base + 12] = o.x
		out[base + 13] = o.y
		out[base + 14] = o.z
		out[base + 15] = 1.0
	return out
