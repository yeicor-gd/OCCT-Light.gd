@tool
extends Node3D
class_name OclMeshBuilder

## OCCT-based mesh builder for maze segments, parallelised via TaskScheduler.
##
## Reads the main path (Path3D) and auxiliary path (Path3D), plans chunked
## segments via ChunkBuilder, then dispatches each chunk as a WorkerThreadPool
## background task.  Results arrive out of order and are assembled into a
## per-chunk Node3D hierarchy on the main thread.
##
## Chunk scene hierarchy:
##   ChunkN (Node3D)
##     Faces (StaticBody3D if physics enabled, Node3D otherwise)
##       FacesCollision (CollisionShape3D, if physics)
##       FacesMesh (MeshInstance3D, if display)
##     Edges (StaticBody3D if physics enabled, Node3D otherwise)
##       EdgesMesh (MultiMeshInstance3D, if display)
##       _occtl_edge_N (CollisionShape3D, if physics)
##     Vertices (StaticBody3D if physics enabled, Node3D otherwise)
##       VerticesMesh (MultiMeshInstance3D, if display)
##       _occtl_vertex_N (CollisionShape3D, if physics)
##
## Chunk root is always a plain Node3D (not a static body).  Only the
## feature sub-nodes (Vertices / Edges / Faces) MAY be StaticBody3D.
##
## Chunk subtrees are persisted as .scn (binary) PackedScene files for
## clean caching.
##
## Display and physics each have independent OclMeshOptions and fancy
## profile flags so you can tune quality vs. performance independently.

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

## Main path node (MazePath) whose curve provides the sweep spine.
@export_node_path("Path3D") var main_path_node: NodePath
## Auxiliary path node whose curve provides sweep orientation (offset curve).
@export_node_path("Path3D") var aux_path_node: NodePath

@export_group("Design")

## Thickness of the track walls.
@export_range(0.0, 1.0) var wall_thickness := 0.05
## Wall height relative to ball radius.
@export_range(0.0, 1.0) var wall_height := 0.3
## Whether to actually build the inner path (for debugging).
@export var main_path := true
## Add rounded end caps at the start and end of the track.
@export var end_caps := true

@export_group("Chunking")

## Number of segments to merge into one OCCT graph.
@export_range(1, 200, 1) var chunk_size: int = 8

## Maximum number of chunk results to accumulate before flushing.
@export_range(0, 200, 1) var merge_batch_size: int = 1

## Maximum concurrent WorkerThreadPool tasks. 0 = unlimited.
@export_range(0, 32, 1) var max_concurrent: int = 0

@export_group("Display")

## OCCT mesh tessellation options for DISPLAY (visual) geometry.
@export var display_options := OclMeshOptions.new()
## Apply 2D fillets to smooth profile corners (fancy mode) for display.
@export var display_fancy := true
## Show tessellated face surfaces.
@export var display_show_faces := true
## Display edges as cylinders (== 0 = disabled, <0 = fixed size).
@export var display_edge_radius: float = 0.01
## Display vertices as spheres (== 0 = disabled, <0 = fixed size).
@export var display_vertex_radius: float = 0.02
## Material for faces
@export var display_faces_material: Material
## Material for edges
@export var display_edges_material: Material
## Material for faces
@export var display_vertices_material: Material

@export_group("Physics")

## OCCT mesh tessellation options for PHYSICS (collision) geometry.
@export var physics_options := OclMeshOptions.new()
## Apply 2D fillets to smooth profile corners (fancy mode) for physics.
@export var physics_fancy := false
## Generate collision shapes for faces.
@export var physics_show_faces := true
## Generate collision shapes for edges (== 0 = disabled, <0 = fixed size).
@export var physics_edge_radius: float = 0.01
## Generate collision shapes for vertices (== 0 = disabled, <0 = fixed size).
@export var physics_vertex_radius: float = 0.02

@export_group("Persistence")

## Base path for saving generated resources. Empty = memory-only.
@export var resource_save_path := "res://demo/generated/maze_meshes"

@export_group("Actions")

@export_tool_button("Regenerate") var regenerate_ = regenerate

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

var _maze_generator: MazeGenerator
var _profile_cfg: ProfileBuilder.Config
var _is_regenerating: bool = false
var _scheduler: TaskScheduler = null
var _chunk_results: Array[Dictionary] = []

# -----------------------------------------------------------------------------
# Initialisation
# -----------------------------------------------------------------------------

func _find_generator() -> MazeGenerator:
	var p: Node = get_parent()
	while p:
		if p is MazeGenerator:
			return p as MazeGenerator
		p = p.get_parent()
	return null

func _ensure_config() -> void:
	_maze_generator = _find_generator()
	_profile_cfg = ProfileBuilder.Config.new(
		_maze_generator.ball_radius,
		_maze_generator.ball_to_path_min_ratio,
		wall_thickness,
		wall_height,
	)

## Return the scene root for setting node owners.
##
## In the editor tree this is get_tree().edited_scene_root.
## During export the instantiated nodes are not in the tree, so we walk up
## to the topmost ancestor (the instantiated PackedScene root).
func _scene_root() -> Node:
	if is_inside_tree():
		return get_tree().edited_scene_root
	var n: Node = get_parent()
	while n and n.get_parent():
		n = n.get_parent()
	return n

# -----------------------------------------------------------------------------
# Entry point (async)
# -----------------------------------------------------------------------------

func regenerate(sync: bool) -> void:
	if _is_regenerating:
		push_warning("OclMeshBuilder: regeneration already in progress, skipping.")
		return
	_is_regenerating = true

	var total_start: int = Time.get_ticks_usec()

	var path: Path3D = get_node(main_path_node) if main_path_node else get_parent().get_node("Paths/MainPath")
	var aux_path: Path3D = get_node(aux_path_node) if aux_path_node else get_parent().get_node("Paths/MainPathBinormal")
	if not path or not aux_path:
		push_error("OclMeshBuilder: missing path references")
		_is_regenerating = false
		return

	_ensure_config()
	aux_path.curve = CurveUtils.build_auxiliary_curve(path.curve)
	_clear_all_chunks()

	var segment_count: int = path.curve.point_count - 1
	print("[OclMeshBuilder] Generating ", segment_count, " segment(s) with ",
				"chunk_size=", chunk_size, ", merge_batch_size=", merge_batch_size,
				", max_concurrent=", max_concurrent, " ...")

	var chunker := ChunkBuilder.new()
	chunker.chunk_size = chunk_size
	var chunks: Array = chunker.plan_chunks(segment_count)
	if chunks.is_empty():
		print("[OclMeshBuilder] No segments to generate.")
		_is_regenerating = false
		return

	# Capture config for worker threads (avoids main-thread-only bindings).
	var captured_cfg: ProfileBuilder.Config = _profile_cfg
	var captured_display_fancy: bool = display_fancy
	var captured_physics_fancy: bool = physics_fancy
	var captured_display_opts: OclMeshOptions = display_options
	var captured_physics_opts: OclMeshOptions = physics_options
	var captured_path_curve: Curve3D = path.curve
	var captured_aux_curve: Curve3D = aux_path.curve

	var captured_main_path := main_path
	var captured_end_caps: bool = end_caps

	var captured_display_show_faces: bool = display_show_faces
	var captured_display_edge_radius: float = display_edge_radius
	var captured_display_vertex_radius: float = display_vertex_radius
	var captured_physics_show_faces: bool = physics_show_faces
	var captured_physics_edge_radius: float = physics_edge_radius
	var captured_physics_vertex_radius: float = physics_vertex_radius

	var scheduler := TaskScheduler.new(sync)
	scheduler.max_concurrent = max_concurrent
	_scheduler = scheduler
	_chunk_results.clear()

	# Dispatch every chunk as a background task.
	var total_chunks := chunks.size()
	for chunk_idx in range(total_chunks):
		var c: ChunkBuilder.Chunk = chunks[chunk_idx] as ChunkBuilder.Chunk
		var idx := chunk_idx
		var is_first := idx == 0
		var is_last := idx == total_chunks - 1
		scheduler.dispatch_task(func():
			var result: Dictionary = _worker_build_chunk(
				idx, c,
				captured_path_curve, captured_aux_curve,
				captured_cfg,
				captured_display_fancy, captured_physics_fancy,
				captured_display_opts, captured_physics_opts,
				captured_display_show_faces, captured_display_edge_radius, captured_display_vertex_radius,
				captured_physics_show_faces, captured_physics_edge_radius, captured_physics_vertex_radius,
				captured_main_path,
				captured_end_caps,
				is_first, is_last,
			)
			scheduler.submit_result(result)
		, false, "OclChunk")

	print("[OclMeshBuilder] Dispatched ", chunks.size(), " chunk(s). Polling...")

	while true:
		scheduler.reap_completed()
		for res in scheduler.collect_all():
			_handle_result(res as Dictionary)
		if not scheduler.is_busy():
			break
		await get_tree().process_frame
		if not _is_regenerating:
			return

	for res in scheduler.collect_all():
		_handle_result(res as Dictionary)

	if merge_batch_size > 0 and not _chunk_results.is_empty():
		_flush_batch()

	print("[OclMeshBuilder] All ", segment_count, " segments in ", chunks.size(),
			" chunk(s) generated in ", (Time.get_ticks_usec() - total_start) / 1000.0, " ms")

	_persist_resources()
	_scheduler = null
	_is_regenerating = false

# =============================================================================
# Worker helpers  (thread-pool threads)
# =============================================================================

static func _worker_build_chunk(
	chunk_idx: int, chunk: ChunkBuilder.Chunk,
	path_curve: Curve3D, aux_curve: Curve3D,
	cfg: ProfileBuilder.Config,
	cdisplay_fancy: bool, cphysics_fancy: bool,
	display_opts: OclMeshOptions, physics_opts: OclMeshOptions,
	do_display_faces: bool,
	cdisplay_edge_radius: float, cdisplay_vertex_radius: float,
	do_physics_faces: bool,
	cphysics_edge_radius: float, cphysics_vertex_radius: float,
	do_main_path: bool,
	do_end_caps: bool,
	is_first_chunk: bool, is_last_chunk: bool,
) -> Dictionary:
	var result: Dictionary = {
		"idx": chunk_idx,
		# Display
		"v": PackedFloat64Array(),
		"e": PackedFloat64Array(),
		"f": [],
		# Physics
		"pv": PackedFloat64Array(),
		"pe": PackedFloat64Array(),
		"pf": PackedVector3Array(),
	}

	var has_display_edges := cdisplay_edge_radius != 0.0
	var has_display_vertices := cdisplay_vertex_radius != 0.0
	var has_physics_edges := cphysics_edge_radius != 0.0
	var has_physics_vertices := cphysics_vertex_radius != 0.0

	var any_display := do_display_faces or has_display_edges or has_display_vertices
	var any_physics := do_physics_faces or has_physics_edges or has_physics_vertices
	if not any_display and not any_physics:
		return result

	# Only add end caps if enabled AND at global track ends.
	var add_start_cap := do_end_caps and is_first_chunk
	var add_end_cap := do_end_caps and is_last_chunk

	# Build display graphs and extract display data.
	var display_graphs: Array[OclGraphHandle] = []
	if any_display:
		display_graphs = _build_and_extract(
			chunk, path_curve, aux_curve, cfg, cdisplay_fancy,
			display_opts,
			has_display_vertices, has_display_edges, do_display_faces,
			cdisplay_vertex_radius, cdisplay_edge_radius, result, true,
			do_main_path, add_start_cap, add_end_cap
		)

	for g in display_graphs:
		OclTopo.graph_free(g)

	# Physics extraction.
	if not any_physics:
		return result

	# Assume different profile for physics -- build a separate graph array.
	var phys_graphs := _build_and_extract(
		chunk, path_curve, aux_curve, cfg, cphysics_fancy,
		physics_opts,
		has_physics_vertices, has_physics_edges, do_physics_faces,
		cphysics_vertex_radius, cphysics_edge_radius, result, false,
		do_main_path, add_start_cap, add_end_cap
	)
	
	for g in phys_graphs:
		OclTopo.graph_free(g)
		
	return result

static func _build_and_extract(
	chunk: ChunkBuilder.Chunk,
	path_curve: Curve3D, aux_curve: Curve3D,
	cfg: ProfileBuilder.Config, fancy: bool,
	mesh_opts: OclMeshOptions,
	do_vertices: bool, do_edges: bool, do_faces: bool,
	v_radius: float, e_radius: float,
	result: Dictionary, is_display: bool,
	do_main_path: bool, add_start_cap: bool, add_end_cap: bool
) -> Array[OclGraphHandle]:
	var prefix: String = "" if is_display else "p"

	var chunker := ChunkBuilder.new()
	var graphs := chunker.build_chunk_graphs(chunk, path_curve, aux_curve, cfg, fancy, do_main_path, add_start_cap, add_end_cap)
	if graphs.is_empty():
		push_error("OclMeshBuilder: build_chunk_graphs returned empty")
		return graphs

	for graph_i in range(graphs.size()):
		var graph := graphs[graph_i]
		if do_vertices:
			var mm := MultiMesh.new()
			var st: int = OclMeshToGodot.mesh_vertices(graph, mm, mesh_opts, null, v_radius) as OclCore.status
			if st == OclCore.OK:
				var xforms := _extract_multimesh_transforms(mm)
				var key := prefix + "v"
				result[key] = (result.get(key, PackedFloat64Array()) as PackedFloat64Array) + xforms
			else:
				push_error("OclMeshBuilder: mesh_vertices failed: ", OclCore.status_to_string(st))

		if do_edges:
			var mm := MultiMesh.new()
			var st: int = OclMeshToGodot.mesh_edges(graph, mm, mesh_opts, null, e_radius) as OclCore.status
			if st == OclCore.OK:
				var xforms := _extract_multimesh_transforms(mm)
				var key := prefix + "e"
				result[key] = (result.get(key, PackedFloat64Array()) as PackedFloat64Array) + xforms
			else:
				push_error("OclMeshBuilder: mesh_edges failed: ", OclCore.status_to_string(st))

		if do_faces:
			if is_display:
				# FIXME(bad profile): XXX: Need to reverse faces in case of first graph and fancy mode.
				var face_arr := _export_face_data(graph, mesh_opts)
				if not face_arr.is_empty():
					result["f"] = (result.get("f", []) as Array) + face_arr
			else:
				var tris := OclMeshToGodot.extract_face_triangles(graph, mesh_opts, null)
				result["pf"] = (result.get("pf", PackedVector3Array()) as PackedVector3Array) + tris

	return graphs

static func _export_face_data(graph, opts: OclMeshOptions) -> Array:
	var mesh := ArrayMesh.new()
	var st: int = OclMeshToGodot.mesh_faces(graph, mesh, opts, null, true, true, true) as OclCore.status
	if st != OclCore.OK:
		return []
	if mesh.get_surface_count() == 0:
		return []
	var arrays = mesh.surface_get_arrays(0)
	return [arrays]

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

static func _decode_transform(data: PackedFloat64Array, index: int) -> Transform3D:
	var base: int = index * 16
	var mbasis := Basis(
		Vector3(data[base + 0], data[base + 4], data[base + 8]),
		Vector3(data[base + 1], data[base + 5], data[base + 9]),
		Vector3(data[base + 2], data[base + 6], data[base + 10]),
	)
	var origin := Vector3(data[base + 12], data[base + 13], data[base + 14])
	return Transform3D(mbasis, origin)

# =============================================================================
# Cleanup
# =============================================================================

func _exit_tree() -> void:
	if _scheduler != null and _scheduler.is_busy():
		_scheduler.sync_and_discard()
		_scheduler = null
		_is_regenerating = false

func _clear_all_chunks() -> void:
	var to_remove: Array[Node] = []
	for child in get_children():
		if child is Node3D and str(child.name).begins_with("Chunk"):
			to_remove.append(child)
	for n in to_remove:
		n.queue_free()
	_chunk_results.clear()

# =============================================================================
# Result handling (main thread)
# =============================================================================

func _handle_result(result: Dictionary) -> void:
	_chunk_results.append(result)
	if merge_batch_size == 0 or _chunk_results.size() >= merge_batch_size:
		_flush_batch()

func _flush_batch() -> void:
	if _chunk_results.is_empty():
		return
	for result in _chunk_results:
		_apply_chunk(result)
	_chunk_results.clear()

func _apply_chunk(result: Dictionary) -> void:
	var idx: int = result.get("idx", 0)

	# Helper to get or create the per-chunk root node (plain Node3D).
	var ensure_chunk_root := func() -> Node3D:
		var node_name := "Chunk" + str(idx)
		var existing := get_node_or_null(node_name) as Node3D
		if existing != null:
			return existing

		var root: Node3D = Node3D.new()
		root.name = node_name
		add_child(root, true)
		if Engine.is_editor_hint():
			root.set_owner(_scene_root())
		return root

	# Helper to get or create a named child under the chunk root.
	# The features child MAY be a StaticBody3D when physics is enabled,
	# otherwise a plain Node3D.
	var ensure_child := func(parent: Node, child_name: String, _has_display: bool, has_physics: bool) -> Node3D:
		var existing := parent.get_node_or_null(child_name) as Node3D
		if existing != null:
			return existing

		var child: Node3D
		if has_physics:
			child = StaticBody3D.new()
		else:
			child = Node3D.new()
		child.name = child_name
		parent.add_child(child, true)
		if Engine.is_editor_hint():
			child.set_owner(_scene_root())
		return child

	var chunk_root: Node3D = ensure_chunk_root.call()

	# --- Faces ---
	var f_surfaces: Array = result.get("f", []) as Array
	var pf_tris: PackedVector3Array = result.get("pf", PackedVector3Array()) as PackedVector3Array
	var has_faces_display := not f_surfaces.is_empty()
	var has_faces_physics := pf_tris.size() >= 3

	if has_faces_display or has_faces_physics:
		var features_root: Node3D = ensure_child.call(chunk_root, "Faces", has_faces_display, has_faces_physics)

		# --- Face collision shape ---
		if has_faces_physics:
			var cs_name := "CollisionFaces"
			var old_cs := features_root.get_node_or_null(cs_name) as CollisionShape3D
			if old_cs != null:
				old_cs.queue_free()

			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(pf_tris)
			var cs := CollisionShape3D.new()
			cs.name = cs_name
			cs.shape = shape
			features_root.add_child(cs, true)
			if Engine.is_editor_hint():
				cs.set_owner(_scene_root())

		# --- Face mesh ---
		if has_faces_display:
			var mesh_name := "FacesMesh"
			var mi := features_root.get_node_or_null(mesh_name) as MeshInstance3D
			if mi == null:
				mi = MeshInstance3D.new()
				mi.name = mesh_name
				features_root.add_child(mi, true)
				if Engine.is_editor_hint():
					mi.set_owner(_scene_root())

			if f_surfaces.size() == 1:
				var arr: Array = f_surfaces[0] as Array
				arr.resize(Mesh.ARRAY_MAX)
				var am := ArrayMesh.new()
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				mi.mesh = am
			else:
				# Merge multiple surfaces into one via C++.
				var merged := OclMeshToGodot.merge_surface_arrays(f_surfaces)
				merged.resize(Mesh.ARRAY_MAX)
				var am := ArrayMesh.new()
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged)
				mi.mesh = am

			mi.mesh.surface_set_material(0, display_faces_material)

	# --- Edges ---
	var e_transforms: PackedFloat64Array = result.get("e", PackedFloat64Array()) as PackedFloat64Array
	var pe_transforms: PackedFloat64Array = result.get("pe", PackedFloat64Array()) as PackedFloat64Array
	var has_edges_display := e_transforms.size() > 0
	var has_edges_physics := pe_transforms.size() > 0

	if has_edges_display or has_edges_physics:
		var features_root: Node3D = ensure_child.call(chunk_root, "Edges", has_edges_display, has_edges_physics)

		if has_edges_display:
			var mm_name := "EdgesMesh"
			var mmi := features_root.get_node_or_null(mm_name) as MultiMeshInstance3D
			if mmi == null:
				mmi = MultiMeshInstance3D.new()
				mmi.name = mm_name
				features_root.add_child(mmi, true)
				if Engine.is_editor_hint():
					mmi.set_owner(_scene_root())

			var existing_mm := mmi.multimesh
			if existing_mm == null or not existing_mm.get_mesh().is_valid():
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				var slices := _slices_from_angle(display_options.angle)
				var cyl := CylinderMesh.new()
				cyl.height = 1.0
				cyl.radial_segments = slices
				cyl.rings = 1
				cyl.cap_top = false
				cyl.cap_bottom = false
				mm.mesh = cyl
				mmi.multimesh = mm
				existing_mm = mm
			existing_mm.mesh.surface_set_material(0, display_edges_material)

			var n := int(e_transforms.size() / 16.0)
			if n > 0:
				existing_mm.instance_count = n
				for i in range(n):
					existing_mm.set_instance_transform(i, _decode_transform(e_transforms, i))

		if has_edges_physics:
			_clear_collision_children(features_root, "_occtl_edge_")
			var n := int(pe_transforms.size() / 16.0)
			for i in range(n):
				var t := _decode_transform(pe_transforms, i)
				var radius := t.basis.x.length()
				var seg_len := t.basis.y.length()
				if radius < 0.0001:
					continue
				var cs := CollisionShape3D.new()
				var shape := CapsuleShape3D.new()
				shape.radius = radius
				shape.height = maxf(0.001, seg_len - 2.0 * radius)
				cs.shape = shape
				var mbasis := Basis(
					t.basis.x.normalized(),
					t.basis.y.normalized(),
					t.basis.z.normalized(),
				)
				cs.transform = Transform3D(mbasis, t.origin)
				cs.name = "_occtl_edge_" + str(i)
				features_root.add_child(cs, true)
				if Engine.is_editor_hint():
					cs.set_owner(_scene_root())

	# --- Vertices ---
	var v_transforms: PackedFloat64Array = result.get("v", PackedFloat64Array()) as PackedFloat64Array
	var pv_transforms: PackedFloat64Array = result.get("pv", PackedFloat64Array()) as PackedFloat64Array
	var has_vertices_display := v_transforms.size() > 0
	var has_vertices_physics := pv_transforms.size() > 0

	if has_vertices_display or has_vertices_physics:
		var features_root: Node3D = ensure_child.call(chunk_root, "Vertices", has_vertices_display, has_vertices_physics)

		if has_vertices_display:
			var mm_name := "VerticesMesh"
			var mmi := features_root.get_node_or_null(mm_name) as MultiMeshInstance3D
			if mmi == null:
				mmi = MultiMeshInstance3D.new()
				mmi.name = mm_name
				features_root.add_child(mmi, true)
				if Engine.is_editor_hint():
					mmi.set_owner(_scene_root())

			var existing_mm := mmi.multimesh
			if existing_mm == null or not existing_mm.get_mesh().is_valid():
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				var slices := _slices_from_angle(display_options.angle)
				var sph := SphereMesh.new()
				sph.radius = 1.0
				sph.radial_segments = slices
				sph.rings = maxi(int(slices / 2.0), 2)
				mm.mesh = sph
				mmi.multimesh = mm
				existing_mm = mm
			existing_mm.mesh.surface_set_material(0, display_vertices_material)

			var n := int(v_transforms.size() / 16.0)
			if n > 0:
				existing_mm.instance_count = n
				for i in range(n):
					existing_mm.set_instance_transform(i, _decode_transform(v_transforms, i))

		if has_vertices_physics:
			_clear_collision_children(features_root, "_occtl_vertex_")
			var n := int(pv_transforms.size() / 16.0)
			for i in range(n):
				var t := _decode_transform(pv_transforms, i)
				var radius := t.basis.x.length()
				if radius < 0.0001:
					continue
				var cs := CollisionShape3D.new()
				var shape := SphereShape3D.new()
				shape.radius = radius
				cs.shape = shape
				cs.transform = Transform3D(Basis.IDENTITY, t.origin)
				cs.name = "_occtl_vertex_" + str(i)
				features_root.add_child(cs, true)
				if Engine.is_editor_hint():
					cs.set_owner(_scene_root())

func _clear_collision_children(parent: Node, prefix: String) -> void:
	var to_remove: Array[Node] = []
	for child in parent.get_children():
		if child is CollisionShape3D and str(child.name).begins_with(prefix):
			to_remove.append(child)
	for n in to_remove:
		n.queue_free()

static func _slices_from_angle(angle: float) -> int:
	var safe := maxf(angle, 0.001)
	return maxi(4, int(roundf(PI / safe)) + 2)

# -----------------------------------------------------------------------------
# Resource persistence
# -----------------------------------------------------------------------------

func _persist_resources() -> void:
	if resource_save_path.is_empty():
		return

	var base: String = resource_save_path.trim_suffix("/")
	var dir_abs := ProjectSettings.globalize_path(base)
	DirAccess.make_dir_recursive_absolute(dir_abs)

	for branch in get_children().duplicate():
		if not (branch is Node3D and str(branch.name).begins_with("Chunk")):
			push_warning("Unexpected child of OclManager", branch)
			continue

		var path: String = base + "/" + str(branch.name) + ".scn"
		
		save_branch(branch, path)
		
		var parent = branch.get_parent()
		var index = branch.get_index()
		var bname = branch.name

		var packed = load(path) as PackedScene
		var instance := packed.instantiate()

		instance.name = bname

		parent.remove_child(branch)
		parent.add_child(instance)
		parent.move_child(instance, index)

		instance.owner = parent.owner # or whatever is appropriate

func save_branch(branch: Node, path: String) -> Error:
	for child in branch.get_children():
		_set_owner_recursive(child, branch)

	var packed := PackedScene.new()
	var err := packed.pack(branch)
	if err != OK:
		return err

	return ResourceSaver.save(packed, path)


func _set_owner_recursive(node: Node, mowner: Node):
	node.owner = mowner
	for child in node.get_children():
		_set_owner_recursive(child, mowner)
