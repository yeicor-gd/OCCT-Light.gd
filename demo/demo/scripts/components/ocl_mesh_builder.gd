@tool
extends Node3D
class_name OclMeshBuilder

## OCCT-based mesh builder for maze segments.
##
## Reads the main path (Path3D) and auxiliary path (Path3D), then for each
## Bezier segment builds a pipe-shell sweep using an extruded track profile.
## Results are accumulated into display nodes (Vertices, Edges, Faces).
## After generation, each resource is saved to a .res file so the .tscn
## references it externally instead of embedding the mesh data.
##
## Design:
##   - Each segment gets its own independent OCCT graph, keeping graphs tiny.
##   - Per-segment graphs are freed after their mesh data is appended.
##   - All heavy OCCT work is delegated to helper classes.

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

## Main path node (MazePath) whose curve provides the sweep spine.
@export_node_path("Path3D") var main_path_node: NodePath
## Auxiliary path node whose curve provides sweep orientation (offset curve).
@export_node_path("Path3D") var aux_path_node: NodePath

@export_group("Wall Profile")

## Thickness of the track walls.
@export_range(0.0, 1.0) var wall_thickness := 0.1
## Wall height relative to ball radius. 0.3 means walls are 0.3 * ball_radius tall.
@export_range(0.0, 1.0) var wall_height := 0.3

## Profile strategy: 0 = fast (rectangle cut), 1 = cool (slot + trace).
@export_enum("Fast", "Cool") var profile_strategy: int = 1

@export_group("Chunking")

## Number of segments to merge into one OCCT graph. Higher values reduce sweep
## operations at the cost of larger per-chunk graphs.
## 1 = one graph per segment (original behaviour).
## Auto-reduced for the last chunk when the segment count is not a multiple.
@export_range(1, 200, 1) var chunk_size: int = 5

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

# -----------------------------------------------------------------------------
# Initialisation
# -----------------------------------------------------------------------------

func _find_generator():
	var p = get_parent()
	while p:
		if p is MazeGenerator:
			return p
		p = p.get_parent()
	return null

## Rebuild the profile config from current exported values.
## Called every regenerate() so inspector changes take effect immediately.
func _ensure_config():
	if not _maze_generator or not is_instance_valid(_maze_generator):
		_maze_generator = _find_generator()
	_profile_cfg = ProfileBuilder.Config.new(
		_maze_generator.ball_radius if _maze_generator else 0.5,
		_maze_generator.ball_to_path_min_ratio if _maze_generator else 0.9,
		wall_thickness,
		wall_height,
	)

# -----------------------------------------------------------------------------
# Entry point
# -----------------------------------------------------------------------------

func regenerate():
	var total_start := Time.get_ticks_usec()

	var path: Path3D = get_node(main_path_node) if main_path_node else get_parent().get_node("Paths/MainPath")
	var aux_path: Path3D = get_node(aux_path_node) if aux_path_node else get_parent().get_node("Paths/MainPathBinormal")
	if not path or not aux_path:
		push_error("OclMeshBuilder: missing path references")
		return

	_ensure_config()

	# Rebuild the auxiliary curve from the main path.
	aux_path.curve = CurveUtils.build_auxiliary_curve(path.curve)

	# Clear previous display meshes.
	_clear_display()

	var segment_count := path.curve.point_count - 1
	print("[OclMeshBuilder] Generating ", segment_count, " segment(s) with chunk_size=", chunk_size, "...")

	var chunker := ChunkBuilder.new()
	chunker.chunk_size = chunk_size
	var chunks := chunker.plan_chunks(segment_count)

	for ci in range(chunks.size()):
		var chunk := chunks[ci]
		var chunk_start := Time.get_ticks_usec()

		# Build a single graph for this chunk (may span multiple segments).
		var graph := chunker.build_chunk_graph(
			chunk, path.curve, aux_path.curve, _profile_cfg, profile_strategy,
		)
		if not graph:
			push_error("OclMeshBuilder: build_chunk_graph returned null for chunk ", ci)
			continue

		# Mesh immediately and accumulate into display nodes.
		if show_vertices:
			_append_graph_vertices(graph, $Vertices.multimesh)
		if show_edges:
			_append_graph_edges(graph, $Edges.multimesh)
		if show_faces:
			_append_graph_faces(graph, $Faces.mesh)

		# Free the per-chunk graph.
		OclTopo.graph_free(graph)

		var chunk_ms := (Time.get_ticks_usec() - chunk_start) / 1000.0
		print("[OclMeshBuilder] Chunk ", ci + 1, "/", chunks.size(),
			" (segments ", chunk.start_segment, "-", chunk.end_segment,
			") done in ", chunk_ms, " ms")

		# Future: emit_signal("generation_progress", ci + 1, chunks.size())
		# Future: await get_tree().idle_frame  (for live display refresh)

	print(
		"[OclMeshBuilder] All ", segment_count,
		" segments in ", chunks.size(), " chunk(s) generated in ",
		(Time.get_ticks_usec() - total_start) / 1000.0, " ms",
	)

	# Persist generated resources to disk so the .tscn doesn't embed them.
	_persist_resources()

# -----------------------------------------------------------------------------
# Resource persistence (save-as-file pattern)
# -----------------------------------------------------------------------------

## Save |resource| to |path| as a compressed .res file.
## Creates parent directories if needed. Returns true on success.
func _save_resource(resource: Resource, path: String) -> bool:
	var dir := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)

	var err := ResourceSaver.save(resource, path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("Failed to save %s: %s" % [path, error_string(err)])
		return false
	return true

## Save each generated resource to disk, then reload and reassign
## so the scene references external files instead of embedded data.
func _persist_resources():
	if resource_save_path.is_empty():
		return  # in-memory only

	var base := resource_save_path.trim_suffix("/")

	if show_faces and has_node("Faces") and $Faces.mesh:
		var p := base + "/faces.res"
		if _save_resource($Faces.mesh, p):
			$Faces.mesh = load(p)

	if show_vertices and has_node("Vertices") and $Vertices.multimesh:
		var p := base + "/vertices.res"
		if _save_resource($Vertices.multimesh, p):
			$Vertices.multimesh = load(p)

	if show_edges and has_node("Edges") and $Edges.multimesh:
		var p := base + "/edges.res"
		if _save_resource($Edges.multimesh, p):
			$Edges.multimesh = load(p)

# -----------------------------------------------------------------------------
# Per-segment construction
# -----------------------------------------------------------------------------

## Build a complete isolated graph for one Bezier segment.
func _build_segment_graph(index: int, path: Path3D, aux_curve: Curve3D) -> SegmentData.SegmentGraph:
	var graph := GraphUtils.create_graph()

	# Profile at the segment start.
	var start_xf := CurveUtils.transform_at_index(path.curve, index)
	var start_profile: OclNodeId

	match profile_strategy:
		0:
			start_profile = ProfileBuilder.build_profile_fast(graph, _profile_cfg, start_xf)[0]
		1:
			start_profile = ProfileBuilder.build_profile_cool(graph, _profile_cfg, start_xf)[0]
		_:
			push_error("Unknown profile strategy: ", profile_strategy)
			return null

	# Spine wire (main path).
	var spine_wire := TopoBuilders.build_segment_wire(graph, path.curve, index)

	# Auxiliary spine wire (offset curve for orientation).
	var aux_wire := TopoBuilders.build_segment_wire(graph, aux_curve, index)

	# Sweep.
	var sweep_info := OclPrimPipeShellInfo.new()
	sweep_info.profiles = PackedInt64Array([start_profile.bits])
	sweep_info.spine_wire = spine_wire.bits
	sweep_info.mode = OclPrimSweep.PIPE_MODE_AUXILIARY_SPINE
	sweep_info.auxiliary_spine_wire = aux_wire.bits
	sweep_info.auxiliary_curvilinear_equivalence = 1
	sweep_info.make_solid = 1
	var sweep_id := OclNodeId.new()
	var status := OclPrimSweep.pipe_shell(graph, sweep_info, sweep_id) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())],
	)

	if Engine.is_editor_hint():
		GraphUtils.check_graph(graph)

	return SegmentData.SegmentGraph.new(graph, OclNodeId.new())

# -----------------------------------------------------------------------------
# Display helpers
# -----------------------------------------------------------------------------

func _clear_display():
	if show_vertices and has_node("Vertices"):
		$Vertices.multimesh.instance_count = 0
	if show_edges and has_node("Edges"):
		$Edges.multimesh.instance_count = 0
	if show_faces and has_node("Faces"):
		$Faces.mesh = ArrayMesh.new()

func _append_multimesh(dst: MultiMesh, src: MultiMesh) -> void:
	var base := dst.instance_count
	var transforms: Array[Transform3D] = []
	transforms.resize(base)
	for i in base:
		transforms[i] = dst.get_instance_transform(i)

	dst.instance_count = base + src.instance_count

	for i in base:
		dst.set_instance_transform(i, transforms[i])
	for i in src.instance_count:
		dst.set_instance_transform(base + i, src.get_instance_transform(i))

func _append_graph_vertices(graph: OclGraphHandle, multimesh: MultiMesh) -> void:
	var tmp := MultiMesh.new()
	var status := OclMeshToGodot.mesh_vertices(graph, tmp, mesh_options, null, 0.02) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())],
	)
	_append_multimesh(multimesh, tmp)

func _append_graph_edges(graph: OclGraphHandle, multimesh: MultiMesh) -> void:
	var tmp := MultiMesh.new()
	var status := OclMeshToGodot.mesh_edges(graph, tmp, mesh_options, null, 0.01) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())],
	)
	_append_multimesh(multimesh, tmp)

## Mesh every solid in |graph| via the STL export/import workaround and add
## each as a separate surface on |target|.
func _append_graph_faces(graph: OclGraphHandle, target: ArrayMesh) -> void:
	var iter := OclNodeIterHandle.new()
	var status := OclTopo.graph_solid_iter_create(graph, iter) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())],
	)

	while true:
		var root_id := OclNodeId.new()
		status = OclTopo.node_iter_next(iter, root_id) as OclCore.status
		if status == OclCore.NOT_FOUND:
			break
		assert(status == OclCore.OK,
			"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())],
		)
		
		status = OclMesh.generate(graph, PackedInt64Array([root_id.bits]), mesh_options)
		assert(status == OclCore.OK,
			"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())],
		)

		var stl_bytes := OclByteArray.new()
		status = OclDe.write_memory(graph, root_id.bits, "stl", stl_bytes) as OclCore.status
		assert(status == OclCore.OK,
			"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())],
		)

		var faces_mesh = StlImporter.LoadFromBytes(stl_bytes.value)
		assert(
			not StlImporter.IsError(faces_mesh),
			"StlImporter failed with result %s" % str(faces_mesh),
		)
		target.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES,
			faces_mesh.surface_get_arrays(0),
		)

	OclTopo.node_iter_free(iter)
