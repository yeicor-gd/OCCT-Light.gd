@tool
extends Node3D
class_name OclMeshBuilder

## OCCT-based mesh builder for maze segments, parallelised via TaskScheduler.
##
## Reads the main path (Path3D) and auxiliary path (Path3D), plans chunked
## segments via ChunkBuilder, then dispatches each chunk as a WorkerThreadPool
## background task.  Results arrive out of order and are merged into the
## display nodes on the main thread as they become ready.
##
## Design:
##   - Each chunk gets its own independent OCCT graph.
##   - Worker threads build, sweep, and mesh the graph, then pack the raw
##     mesh data (transforms, surface arrays) into a Dictionary.
##   - Results are submitted via TaskScheduler.submit_result() (Mutex-
##     protected, direct call from worker thread) and collected by the
##     main thread in a frame-by-frame poll loop.
##   - After all results are collected, generated resources are persisted.
##
## Thread safety:
##   - GDExtension OCCT calls (OclGraphHandle operations, OclMesh.generate,
##     OclMeshToGodot.mesh_vertices/edges) operate on per-task graph handles
##     and are safe on worker threads.
##   - Face mesh extraction uses the existing OclMeshToGodot.mesh_faces()
##     API on the MAIN THREAD (via the submitted graph handle), because it
##     calls add_surface_from_arrays() which requires main-thread access.
##     The graph is built and meshed on the worker, so mesh_faces() on the
##     main thread reads cached triangulation data without regenerating it.
##   - Scene tree nodes (MultiMeshInstance3D, MeshInstance3D) are only
##     touched on the main thread.

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

## Main path node (MazePath) whose curve provides the sweep spine.
@export_node_path("Path3D") var main_path_node: NodePath
## Auxiliary path node whose curve provides sweep orientation (offset curve).
@export_node_path("Path3D") var aux_path_node: NodePath

@export_group("Wall Profile")

## Thickness of the track walls.
@export_range(0.0, 1.0) var wall_thickness := 0.05
## Wall height relative to ball radius. 0.3 means walls are 0.3 * ball_radius tall.
@export_range(0.0, 1.0) var wall_height := 0.3

## Profile strategy: 0 = fast (rectangle cut), 1 = cool (slot + trace).
@export_enum("Fast", "Cool") var profile_strategy: int = 1

@export_group("Chunking")

## Number of segments to merge into one OCCT graph. Higher values reduce sweep
## operations at the cost of larger per-chunk graphs.
## 1 = one graph per segment (original behaviour).
@export_range(1, 200, 1) var chunk_size: int = 8

## Maximum number of chunk results to accumulate before flushing to display
## nodes.  Higher values reduce GPU draw-call count but increase per-frame
## main-thread work.  0 = flush every result immediately.
@export_range(0, 200, 1) var merge_batch_size: int = 1

## Maximum number of WorkerThreadPool tasks to run simultaneously.
## 0 = unlimited (let the threadpool decide).  Set to 1 when the
## worker callable uses a non-thread-safe library (e.g. OCCT) to
## serialise calls while keeping the main thread responsive.
@export_range(0, 32, 1) var max_concurrent: int = 0

@export_group("Display")

## OCCT mesh tessellation options.
@export var mesh_options := OclMeshOptions.new()
## Show OCCT vertex points (spheres).
@export var show_vertices := true
## Show OCCT edge lines (cylinders).
@export var show_edges := true
## Show tessellated face surfaces.
@export var show_faces := true

@export_group("Persistence")

## Base path for saving generated mesh resources (e.g. res://generated/maze_meshes).
## Leave empty to keep resources in-memory only.
@export var resource_save_path := "res://demo/generated/maze_meshes"

@export_group("Actions")

@export_tool_button("Regenerate") var regenerate_ = regenerate

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

var _maze_generator: MazeGenerator
var _profile_cfg: ProfileBuilder.Config

## Guards against concurrent regenerate() calls.
var _is_regenerating: bool = false

## Reference to the current TaskScheduler so _exit_tree() can
## wait for outstanding worker tasks when the node is torn down.
var _scheduler: TaskScheduler = null

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

## Rebuild the profile config from current exported values.
func _ensure_config() -> void:
	if not _maze_generator or not is_instance_valid(_maze_generator):
		_maze_generator = _find_generator()
	_profile_cfg = ProfileBuilder.Config.new(
		_maze_generator.ball_radius if _maze_generator else 0.5,
		_maze_generator.ball_to_path_min_ratio if _maze_generator else 0.9,
		wall_thickness,
		wall_height,
	)

# -----------------------------------------------------------------------------
# Entry point (async)
# -----------------------------------------------------------------------------

func regenerate() -> void:
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

	# Rebuild the auxiliary curve from the main path.
	aux_path.curve = CurveUtils.build_auxiliary_curve(path.curve)

	# Clear previous display meshes.
	_clear_display()

	var segment_count: int = path.curve.point_count - 1
	print("[OclMeshBuilder] Generating ", segment_count, " segment(s) with ",
				"chunk_size=", chunk_size, ", merge_batch_size=", merge_batch_size,
				", max_concurrent=", max_concurrent, " ...")

	# Plan chunks.
	var chunker := ChunkBuilder.new()
	chunker.chunk_size = chunk_size
	var chunks: Array = chunker.plan_chunks(segment_count)
	if chunks.is_empty():
		print("[OclMeshBuilder] No segments to generate.")
		_is_regenerating = false
		return

	# Capture configuration once so worker closures don't re-evaluate member
	# variables (which would require the main-thread-only GDScript binding).
	var captured_cfg: ProfileBuilder.Config = _profile_cfg
	var captured_profile_strategy: int = profile_strategy
	var captured_mesh_options: OclMeshOptions = mesh_options
	var captured_show_vertices: bool = show_vertices
	var captured_show_edges: bool = show_edges
	var captured_show_faces: bool = show_faces
	var captured_path_curve: Curve3D = path.curve
	var captured_aux_curve: Curve3D = aux_path.curve

	# Create scheduler and store it for cleanup.
	var scheduler := TaskScheduler.new()
	scheduler.max_concurrent = max_concurrent
	_scheduler = scheduler

	# Accumulators for batched merge ("chunks of chunks").
	var vertex_batch: Array[PackedFloat64Array] = []
	var edge_batch: Array[PackedFloat64Array] = []
	var face_batch: Array[Array] = []

	# --------------------------------------------------------------
	# Dispatch every chunk as a background task.
	# --------------------------------------------------------------
	for chunk_cookie in chunks:
		var c: ChunkBuilder.Chunk = chunk_cookie as ChunkBuilder.Chunk
		scheduler.dispatch_task(func():
			# ---- runs on worker thread ----
			var result: Dictionary = _worker_build_chunk(
				c,
				captured_path_curve,
				captured_aux_curve,
				captured_cfg,
				captured_profile_strategy,
				captured_mesh_options,
				captured_show_vertices,
				captured_show_edges,
				captured_show_faces,
			)
			scheduler.submit_result(result)
		, false, "OclChunk")

	print("[OclMeshBuilder] Dispatched ", chunks.size(), " chunk(s). Polling...")

	# --------------------------------------------------------------
	# Helper: handle one result dictionary (main thread).
	# --------------------------------------------------------------
	var handle_result := func(result: Dictionary) -> void:
		var v: PackedFloat64Array = result.get("v", PackedFloat64Array()) as PackedFloat64Array
		var e: PackedFloat64Array = result.get("e", PackedFloat64Array()) as PackedFloat64Array
		var f_data: Array = result.get("f", []) as Array

		# Surface arrays are already pre-assembled on the worker thread.
		var f_surfaces: Array[Array] = []
		for sa_raw in f_data:
			var sa: Array = sa_raw as Array
			if sa.size() > 0:
				f_surfaces.append(sa)

		if merge_batch_size == 0:
			# No batching — apply immediately.
			if v.size() > 0:
				_append_vertex_transforms(v)
			if e.size() > 0:
				_append_edge_transforms(e)
			if f_surfaces.size() > 0:
				_append_face_surfaces(f_surfaces)
		else:
			# Accumulate and flush when batch is full.
			if v.size() > 0:
				vertex_batch.append(v)
			if e.size() > 0:
				edge_batch.append(e)
			if f_surfaces.size() > 0:
				# Flatten: f_surfaces is Array[Array] (list of surface arrays).
				# Append each surface array individually so _flush_batch
				# can pass them directly to add_surface_from_arrays.
				for s in f_surfaces:
					face_batch.append(s as Array)

			if (vertex_batch.size() >= merge_batch_size
					or edge_batch.size() >= merge_batch_size
					or face_batch.size() >= merge_batch_size):
				_flush_batch(vertex_batch, edge_batch, face_batch)

	# --------------------------------------------------------------
	# Main-thread poll loop.
	# --------------------------------------------------------------
	while true:
		scheduler.reap_completed()
		for res in scheduler.collect_all():
			handle_result.call(res as Dictionary)
		if not scheduler.is_busy():
			break
		await get_tree().process_frame
		# If _exit_tree() cleaned up while we were waiting, bail out.
		if not _is_regenerating:
			return

	# Final drain (any results submitted between last reap and loop exit).
	for res in scheduler.collect_all():
		handle_result.call(res as Dictionary)

	# Flush any remaining accumulated results.
	if merge_batch_size > 0:
		_flush_batch(vertex_batch, edge_batch, face_batch)

	print(
		"[OclMeshBuilder] All ", segment_count,
		" segments in ", chunks.size(), " chunk(s) generated in ",
		(Time.get_ticks_usec() - total_start) / 1000.0, " ms",
	)

	# Persist generated resources to disk.
	_persist_resources()

	_scheduler = null
	_is_regenerating = false

# =============================================================================
# Worker helpers — run on thread-pool threads
# =============================================================================

## Builds one chunk's graph, meshes it, and returns a Dictionary with
## the raw mesh data.  Always returns a Dictionary (possibly empty) so
## the scheduler never misses a submit_result call.
static func _worker_build_chunk(
	chunk: ChunkBuilder.Chunk,
	path_curve: Curve3D,
	aux_curve: Curve3D,
	cfg: ProfileBuilder.Config,
	p_strategy: int,
	mesh_opts: OclMeshOptions,
	do_vertices: bool,
	do_edges: bool,
	do_faces: bool,
) -> Dictionary:
	var result: Dictionary = {
		"v": PackedFloat64Array(),
		"e": PackedFloat64Array(),
		"f": [],
	}

	var chunker := ChunkBuilder.new()
	chunker.chunk_size = 1

	var graph = chunker.build_chunk_graph(
		chunk, path_curve, aux_curve, cfg, p_strategy,
	)
	if graph == null:
		push_error("OclMeshBuilder: build_chunk_graph returned null")
		return result

	if do_vertices:
		var mm := MultiMesh.new()
		var st: int = OclMeshToGodot.mesh_vertices(graph, mm, mesh_opts, null, 0.02) as OclCore.status
		if st == OclCore.OK:
			result["v"] = _extract_multimesh_transforms(mm)
		else:
			push_error("OclMeshBuilder: mesh_vertices failed: ", OclCore.status_to_string(st))

	if do_edges:
		var mm := MultiMesh.new()
		var st: int = OclMeshToGodot.mesh_edges(graph, mm, mesh_opts, null, 0.01) as OclCore.status
		if st == OclCore.OK:
			result["e"] = _extract_multimesh_transforms(mm)
		else:
			push_error("OclMeshBuilder: mesh_edges failed: ", OclCore.status_to_string(st))

	if do_faces:
		result["f"] = _export_face_data(graph, mesh_opts)

	OclTopo.graph_free(graph)
	return result

## Extracts all instance transforms from a MultiMesh into a flat
## PackedFloat64Array (16 floats per Transform3D, column-major).
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

## Worker-thread-safe: builds a combined surface array for all faces in
## |graph|.  Uses OclMeshToGodot.mesh_faces() to fill a local ArrayMesh,
## then extracts the raw surface arrays (no GDExtension Node objects
## created, only data).
## Returns an Array[Array] where each element is a pre-assembled surface
## Array suitable for add_surface_from_arrays().
static func _export_face_data(graph, opts: OclMeshOptions) -> Array:
	var mesh := ArrayMesh.new()
	var st: int = OclMeshToGodot.mesh_faces(
		graph, mesh, opts, null, false, false, false,
	) as OclCore.status
	if st != OclCore.OK:
		return []
	if mesh.get_surface_count() == 0:
		return []
	var arrays = mesh.surface_get_arrays(0)
	return [arrays]

# =============================================================================
# Cleanup
# =============================================================================

func _exit_tree() -> void:
	## If regeneration is in progress, wait for outstanding worker tasks
	## before the node (and its scene tree) are torn down.  This prevents
	## crashes where WorkerThreadPool tasks still reference objects that
	## have already been freed.
	if _scheduler != null and _scheduler.is_busy():
		_scheduler.sync_and_discard()
		_scheduler = null
		_is_regenerating = false

# =============================================================================
# Display helpers (main thread only)
# =============================================================================

func _clear_display() -> void:
	if show_vertices and has_node("Vertices"):
		$Vertices.multimesh.instance_count = 0
	if show_edges and has_node("Edges"):
		$Edges.multimesh.instance_count = 0
	if show_faces and has_node("Faces"):
		$Faces.mesh = ArrayMesh.new()

## Decode a Transform3D from column-major float16 layout.
static func _decode_transform(data: PackedFloat64Array, index: int) -> Transform3D:
	var base: int = index * 16
	var mbasis := Basis(
		Vector3(data[base + 0], data[base + 4], data[base + 8]),
		Vector3(data[base + 1], data[base + 5], data[base + 9]),
		Vector3(data[base + 2], data[base + 6], data[base + 10]),
	)
	var origin := Vector3(data[base + 12], data[base + 13], data[base + 14])
	return Transform3D(mbasis, origin)

## Merges an array of transform-batches into the destination MultiMesh.
##
## NOTE: Godot's MultiMesh.instance_count setter may reset the entire
## transform buffer, so we save and restore existing transforms.
static func _merge_transform_batches(dst: MultiMesh, batches: Array[PackedFloat64Array]) -> void:
	var total_instances: int = 0
	for b in batches:
		total_instances += int(b.size() / 16.0)

	if total_instances == 0:
		return

	var old_count: int = dst.instance_count
	var new_count: int = old_count + total_instances

	# Save existing transforms (instance_count setter may trash them).
	var saved: Array[Transform3D] = []
	saved.resize(old_count)
	for i in range(old_count):
		saved[i] = dst.get_instance_transform(i)

	# Increase instance count (may reset buffer).
	dst.instance_count = new_count

	# Restore old transforms.
	for i in range(old_count):
		dst.set_instance_transform(i, saved[i])

	# Write new transforms.
	var idx: int = old_count
	for b in batches:
		var n: int = int(b.size() / 16.0)
		for j in range(n):
			dst.set_instance_transform(idx, _decode_transform(b, j))
			idx += 1

## Appends raw vertex transforms to the display MultiMesh (no batch).
##
## NOTE: instance_count setter may reset buffer; saves/restores existing.
func _append_vertex_transforms(data: PackedFloat64Array) -> void:
	if not has_node("Vertices"):
		return
	var mm: MultiMesh = $Vertices.multimesh
	var old_count: int = mm.instance_count
	var n: int = int(data.size() / 16.0)
	if n == 0:
		return

	# Save existing transforms.
	var saved: Array[Transform3D] = []
	saved.resize(old_count)
	for i in range(old_count):
		saved[i] = mm.get_instance_transform(i)

	# Increase count (may reset buffer).
	mm.instance_count = old_count + n

	# Restore old transforms.
	for i in range(old_count):
		mm.set_instance_transform(i, saved[i])

	# Write new transforms.
	for i in range(n):
		mm.set_instance_transform(old_count + i, _decode_transform(data, i))

## Appends raw edge transforms to the display MultiMesh (no batch).
##
## NOTE: instance_count setter may reset buffer; saves/restores existing.
func _append_edge_transforms(data: PackedFloat64Array) -> void:
	if not has_node("Edges"):
		return
	var mm: MultiMesh = $Edges.multimesh
	var old_count: int = mm.instance_count
	var n: int = int(data.size() / 16.0)
	if n == 0:
		return

	# Save existing transforms.
	var saved: Array[Transform3D] = []
	saved.resize(old_count)
	for i in range(old_count):
		saved[i] = mm.get_instance_transform(i)

	# Increase count (may reset buffer).
	mm.instance_count = old_count + n

	# Restore old transforms.
	for i in range(old_count):
		mm.set_instance_transform(i, saved[i])

	# Write new transforms.
	for i in range(n):
		mm.set_instance_transform(old_count + i, _decode_transform(data, i))

## Appends raw face surfaces directly to the display ArrayMesh (no batch).
func _append_face_surfaces(surfaces: Array) -> void:
	if not has_node("Faces"):
		return
	for arrays in surfaces:
		var arr: Array = arrays as Array
		arr.resize(Mesh.ARRAY_MAX)
		$Faces.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

## Merges all currently accumulated batch data into the display nodes and
## clears the batches.
func _flush_batch(
	vertex_batch: Array[PackedFloat64Array],
	edge_batch: Array[PackedFloat64Array],
	face_batch: Array,
) -> void:
	if not vertex_batch.is_empty():
		if has_node("Vertices"):
			_merge_transform_batches($Vertices.multimesh, vertex_batch)
		vertex_batch.clear()

	if not edge_batch.is_empty():
		if has_node("Edges"):
			_merge_transform_batches($Edges.multimesh, edge_batch)
		edge_batch.clear()

	if not face_batch.is_empty():
		if has_node("Faces"):
			for arrays in face_batch:
				var arr: Array = arrays as Array
				arr.resize(Mesh.ARRAY_MAX)
				$Faces.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		face_batch.clear()

# -----------------------------------------------------------------------------
# Resource persistence (save-as-file pattern)
# -----------------------------------------------------------------------------

func _save_resource(resource: Resource, path: String) -> bool:
	var dir: String = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)

	var err: int = ResourceSaver.save(resource, path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("Failed to save %s: %s" % [path, error_string(err)])
		return false
	return true

func _persist_resources() -> void:
	if resource_save_path.is_empty():
		return

	var base: String = resource_save_path.trim_suffix("/")

	if show_faces and has_node("Faces") and $Faces.mesh:
		var p: String = base + "/faces.res"
		if _save_resource($Faces.mesh, p):
			$Faces.mesh = load(p)

	if show_vertices and has_node("Vertices") and $Vertices.multimesh:
		var p: String = base + "/vertices.res"
		if _save_resource($Vertices.multimesh, p):
			$Vertices.multimesh = load(p)

	if show_edges and has_node("Edges") and $Edges.multimesh:
		var p: String = base + "/edges.res"
		if _save_resource($Edges.multimesh, p):
			$Edges.multimesh = load(p)
