@tool
extends Node3D

@export_node_path("Path3D") var path_node: NodePath
@export_tool_button("Generate") var generate_ := _generate
@onready var maze := $".."


# ==============================================================================
#  Lightweight data containers
# ==============================================================================

# Holds everything belonging to one Bezier segment's result.
# Each segment produces its own independent graph, so graphs stay tiny.
class SegmentGraph:
	var graph: OclGraphHandle
	var solid: OclNodeId

	func _init(g: OclGraphHandle, s: OclNodeId):
		graph = g
		solid = s


# Holds a reusable sweep profile (built once, referenced by many segments).
# Future: when cross-graph copy/import is available, segments can import this
# profile instead of building their own.
class SweepProfile:
	var graph: OclGraphHandle
	var profile_id: OclNodeId

	func _init(g: OclGraphHandle, p: OclNodeId):
		graph = g
		profile_id = p


# ==============================================================================
#  Conversion helpers
# ==============================================================================

func v3_to_p3(v3: Vector3) -> OclPoint3:
	var p3 := OclPoint3.new()
	p3.x = v3.x
	p3.y = v3.y
	p3.z = v3.z
	return p3


func v3_to_d3(v3: Vector3) -> OclDirection3:
	var p3 := OclDirection3.new()
	p3.x = v3.x
	p3.y = v3.y
	p3.z = v3.z
	return p3


func p3_to_v3(p3: OclPoint3) -> Vector3:
	return Vector3(p3.x, p3.y, p3.z)


func transform3d_to_occt_array(t: Transform3D) -> PackedFloat64Array:
	var b := t.basis
	var o := t.origin
	return PackedFloat64Array([
		# Row 0
		b.x.x, b.y.x, b.z.x, o.x,
		# Row 1
		b.x.y, b.y.y, b.z.y, o.y,
		# Row 2
		b.x.z, b.y.z, b.z.z, o.z,
	])


# ==============================================================================
#  Auxiliary curve – used to orient the sweep (debug visualisation)
# ==============================================================================

func _build_auxiliary_curve(base_curve: Curve3D) -> Curve3D:
	var res := Curve3D.new()
	var offset_amount := 0.15
	for i in range(base_curve.point_count):
		var p := base_curve.get_point_position(i)
		var forward: Vector3
		if i < base_curve.point_count - 1:
			forward = base_curve.get_point_out(i)
		else:
			forward = -base_curve.get_point_in(i)

		# Offset direction: perpendicular to both the forward direction and
		# the radial direction (gravity points toward origin, so the "floor"
		# plane is perpendicular to the radial).
		var right := _floor_perpendicular(forward, p)

		res.add_point(p + right * offset_amount)
		if i < base_curve.point_count - 1:
			res.set_point_out(i, base_curve.get_point_out(i))
		if i > 0:
			res.set_point_in(i, base_curve.get_point_in(i))
	return res


# Return a unit vector perpendicular to |forward| that lies in the "floor"
# plane — i.e. perpendicular to the radial direction of |point| from the
# origin  (gravity points toward the origin, so the floor is perpendicular
# to the gravity vector).
#
# When |forward| and the radial are parallel (path goes straight up/down)
# we fall back to any direction in the floor plane.
static func _floor_perpendicular(forward: Vector3, point: Vector3) -> Vector3:
	var radial := point.normalized()
	if radial.length_squared() < 0.0001:
		# Point is at the origin — pick a safe reference.
		radial = Vector3.UP

	var right := forward.cross(radial)
	if right.length_squared() < 0.0001:
		# Forward is parallel to radial — pick any direction in the floor plane.
		right = radial.cross(Vector3.UP)
		if right.length_squared() < 0.0001:
			right = radial.cross(Vector3.FORWARD)
	return right.normalized()


# ==============================================================================
#  Profile creation  (slot → split → transform → trace)
# ==============================================================================

# Build the sweep profile geometry inside a given graph.
# Returns the node id of the resulting profile shape.
#
# Segments can call this inside their own graph to obtain a profile, or a shared
# profile can be imported once cross-graph copy support lands.
func _build_profile_in_graph(graph: OclGraphHandle, path: Path3D) -> OclNodeId:
	# Slot (rounded rectangle)
	var slot_info := OclPrimSlotInfo.new()
	slot_info.length = maze.ball_radius / maze.ball_to_path_min_ratio
	slot_info.width = maze.ball_radius
	var slot_placement := OclAxis2Placement.new()
	slot_placement.x_dir = v3_to_d3(Vector3(0, 0, 1).normalized())
	slot_placement.x_dir_ref = v3_to_d3(Vector3(1, 0, 0).normalized())
	slot_info.placement = slot_placement
	var slot_id := OclNodeId.new()
	var status := OclPrimSketch.slot(graph, slot_info, slot_id) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	# Split by plane (keep negative Y)
	var split_info := OclTopoSplitByPlaneOptions.new()
	split_info.root = slot_id.bits
	split_info.keep = OclTopoAlgo.TOPO_SPLIT_KEEP_NEGATIVE
	split_info.normal = v3_to_d3(Vector3(0, 1, 0))
	var split_id := OclNodeId.new()
	status = OclTopoAlgo.make_split_by_plane(graph, split_info, graph, split_id) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	# Transform to align with the start of the path
	var spline_start := path.curve.sample_baked_with_rotation(0.0)
	var xform_info := OclTransform.new()
	xform_info.m = transform3d_to_occt_array(spline_start)
	var xform_id := OclNodeId.new()
	status = OclTopoAlgo.transformed(graph, split_id.bits, xform_info, graph, xform_id) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	# Trace to obtain a wire from the transformed shape
	var wire_iter := OclNodeIterHandle.new()
	status = OclTopo.graph_wire_iter_create(graph, wire_iter) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	var mwire := OclNodeId.new()
	status = OclTopo.node_iter_next(wire_iter, mwire) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	var trace_info := OclPrimTraceInfo.new()
	trace_info.path = mwire.bits
	trace_info.width = slot_info.length * 0.1
	var trace_id := OclNodeId.new()
	status = OclPrimSketch.trace(graph, trace_info, trace_id) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	# Remove the temporary wire (no longer needed after trace)
	status = OclTopoBuild.topo_remove_subgraph(graph, mwire.bits) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	OclTopo.node_iter_free(wire_iter)
	return trace_id


# ==============================================================================
#  Graph lifecycle
# ==============================================================================

func _create_graph() -> OclGraphHandle:
	var graph := OclGraphHandle.new()
	var status := OclTopo.graph_create(graph) as OclCore.status
	assert(status == OclCore.OK, "Got status " + str(OclCore.status_to_string(status)))
	return graph


# ==============================================================================
#  Low-level topology builders
# ==============================================================================

func _make_bezier_curve(
	graph: OclGraphHandle,
	p0: Vector3,
	c0: Vector3,
	c1: Vector3,
	p1: Vector3,
) -> OclRepId:
	var info := OclCurveBezierCreateInfo.new()
	info.poles = OclPoint3Array.from([
		v3_to_p3(p0),
		v3_to_p3(c0),
		v3_to_p3(c1),
		v3_to_p3(p1),
	])
	info.weights = PackedFloat64Array([1, 1, 1, 1])
	var rep := OclRepId.new()
	var status := OclCurves.create_bezier(graph, info, rep) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	return rep


func _make_vertex(graph: OclGraphHandle, point: Vector3) -> OclNodeId:
	var info := OclTopoMakeVertexInfo.new()
	info.point = v3_to_p3(point)
	var vertex := OclNodeId.new()
	var status := OclTopoBuild.topo_make_vertex(graph, info, vertex) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	return vertex


func _make_edge(
	graph: OclGraphHandle,
	curve: OclRepId,
	start_vertex: OclNodeId,
	end_vertex: OclNodeId,
) -> OclNodeId:
	var info := OclTopoMakeEdgeInfo.new()
	info.curve = curve.bits
	info.start_vertex = start_vertex.bits
	info.end_vertex = end_vertex.bits

	var first := OclDouble.new()
	var last := OclDouble.new()
	var status := OclCurves.parameter_range(graph, curve.bits, first, last) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	info.first = first.value
	info.last = last.value

	var edge := OclNodeId.new()
	status = OclTopoBuild.topo_make_edge(graph, info, edge) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	return edge


func _make_wire(graph: OclGraphHandle, oriented_edges: Array[OclOrientedNode]) -> OclNodeId:
	var info := OclTopoMakeWireInfo.new()
	info.edges = OclOrientedNodeArray.from(oriented_edges)
	var wire := OclNodeId.new()
	var status := OclTopoBuild.topo_make_wire(graph, info, wire) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	return wire


# ==============================================================================
#  Per-segment construction
# ==============================================================================

# Build a complete isolated graph for one Bezier segment.
#
# 1. Builds a bezier edge+wire from the main path curve for the spine.
# 2. Builds the same from |aux_curve| for the auxiliary spine (sweep orientation).
# 3. Places a rectangle profile at the segment start, oriented with Z = spine
#    tangent and Y = radial away-from-origin (up), so X = Z.cross(Y).
# 4. Sweeps the profile along the spine using the auxiliary spine for twist.
#
# |aux_curve| is the visually-verified offset curve from _build_auxiliary_curve.
#
# Returns a SegmentGraph that owns the graph and the resulting solid node.
func _build_segment_graph(index: int, path: Path3D, aux_curve: Curve3D) -> SegmentGraph:
	var graph := _create_graph()

	# ---- Helper to build an edge + wire for a single bezier segment -------
	var _build_wire_for_segment := func(graph: OclGraphHandle, curve3d: Curve3D, idx: int) -> OclNodeId:
		var p0: Vector3 = curve3d.get_point_position(idx)
		var p1: Vector3 = curve3d.get_point_position(idx + 1)
		var cl0: Vector3 = p0 + curve3d.get_point_out(idx)
		var cl1: Vector3 = p1 + curve3d.get_point_in(idx + 1)

		var bez := _make_bezier_curve(graph, p0, cl0, cl1, p1)
		var sv := _make_vertex(graph, p0)
		var ev := _make_vertex(graph, p1)
		var ed := _make_edge(graph, bez, sv, ev)

		var oriented := OclOrientedNode.new()
		oriented.id = ed.bits
		oriented.orientation = OclTopoRelation.ORIENTATION_FORWARD
		return _make_wire(graph, [oriented])

	# ---- Spine wire (main path) ----
	var spine_wire: OclNodeId = _build_wire_for_segment.call(graph, path.curve, index)

	# ---- Auxiliary spine wire (offset curve, visually verified in Godot) ----
	var aux_wire: OclNodeId = _build_wire_for_segment.call(graph, aux_curve, index)

	# ---- Sweep profile (rectangle) placed at the start of the segment ----
	var rect_info := OclPrimRectangleInfo.new()
	rect_info.width = 0.5
	rect_info.height = 0.1
	var rect_id := OclNodeId.new()
	OclPrimSketch.rectangle(graph, rect_info, rect_id)

	# Profile frame from the spine curve tangent and the radial "up".
	var spine_p0: Vector3 = path.curve.get_point_position(index)
	var forward: Vector3 = path.curve.get_point_out(index).normalized()
	var up: Vector3 = spine_p0.normalized()  # away from origin (gravity goes toward origin)

	# Right-handed frame: Z = forward, Y = up, X = Z.cross(Y).
	var z_axis := forward
	var y_axis := up
	var x_axis := z_axis.cross(y_axis)

	var xform := OclTransform.new()
	xform.m = PackedFloat64Array([
		x_axis.x, y_axis.x, z_axis.x, spine_p0.x,
		x_axis.y, y_axis.y, z_axis.y, spine_p0.y,
		x_axis.z, y_axis.z, z_axis.z, spine_p0.z,
	])

	var rect_placed := OclNodeId.new()
	var status := OclTopoAlgo.transformed(graph, rect_id.bits, xform, graph, rect_placed) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	## ---- Sweep ----
	#var sweep_info := OclPrimPipeShellInfo.new()
	#sweep_info.spine_wire = spine_wire.bits
	#sweep_info.auxiliary_spine_wire = aux_wire.bits
	#sweep_info.mode = OclPrimSweep.PIPE_MODE_AUXILIARY_SPINE
	#sweep_info.profiles = PackedInt64Array([rect_placed.bits])
	#var sweep_id := OclNodeId.new()
	#status = OclPrimSweep.pipe_shell(graph, sweep_info, sweep_id) as OclCore.status
	#assert(status == OclCore.OK,
		#"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	# ---- Sweep ----
	#var sweep_info := OclPrimPipeInfo.new()
	#sweep_info.spine_wire = spine_wire.bits
	#sweep_info.profile = rect_placed.bits
	#var sweep_id := OclNodeId.new()
	#status = OclPrimSweep.pipe(graph, sweep_info, sweep_id) as OclCore.status
	#assert(status == OclCore.OK,
		#"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	return SegmentGraph.new(graph, rect_placed)


# ==============================================================================
#  Meshing helpers  (transfer OCCT graph data into Godot display nodes)
# ==============================================================================

func _append_graph_vertices(graph: OclGraphHandle, multimesh: MultiMesh) -> void:
	var first_time := multimesh.instance_count == 0
	var temp_mm: MultiMesh
	if first_time:
		temp_mm = multimesh
	else:
		temp_mm = MultiMesh.new()
	var status := OclMeshToGodot.mesh_vertices(graph, temp_mm, null, null, 0.02) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	if not first_time:
		var base_index := multimesh.instance_count
		multimesh.instance_count += temp_mm.instance_count
		for i in range(temp_mm.instance_count):
			multimesh.set_instance_transform(base_index + i, temp_mm.get_instance_transform(i))


func _append_graph_edges(graph: OclGraphHandle, multimesh: MultiMesh) -> void:
	var first_time := multimesh.instance_count == 0
	var temp_mm: MultiMesh
	if first_time:
		temp_mm = multimesh
	else:
		temp_mm = MultiMesh.new()
	var status := OclMeshToGodot.mesh_edges(graph, temp_mm, null, null, 0.01) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	print("first_time: ", first_time)
	if not first_time:
		var base_index := multimesh.instance_count
		multimesh.instance_count += temp_mm.instance_count
		for i in range(temp_mm.instance_count):
			multimesh.set_instance_transform(base_index + i, temp_mm.get_instance_transform(i))


# Mesh every solid in |graph| via the STL export/import workaround and add each
# as a separate surface on |target|.
func _append_graph_faces(graph: OclGraphHandle, target: ArrayMesh) -> void:
	var iter := OclNodeIterHandle.new()
	var status := OclTopo.graph_solid_iter_create(graph, iter) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	while true:
		var root_id := OclNodeId.new()
		status = OclTopo.node_iter_next(iter, root_id) as OclCore.status
		if status == OclCore.NOT_FOUND:
			break
		assert(status == OclCore.OK,
			"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

		var stl_bytes := OclByteArray.new()
		status = OclDe.write_memory(graph, root_id.bits, "stl", stl_bytes) as OclCore.status
		assert(status == OclCore.OK, "Got status " + str(OclCore.status_to_string(status)))

		var faces_mesh = StlImporter.LoadFromBytes(stl_bytes.value)
		assert(!StlImporter.IsError(faces_mesh),
			"StlImporter failed with result " + str(faces_mesh))
		target.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES,
			faces_mesh.surface_get_arrays(0),
		)

	OclTopo.node_iter_free(iter)


func _clear_display_meshes() -> void:
	$Vertices.multimesh = MultiMesh.new()
	$Edges.multimesh = MultiMesh.new()
	$Faces.mesh = ArrayMesh.new()


# ==============================================================================
#  Entry point
# ==============================================================================

func _generate():
	var total_start := Time.get_ticks_usec()
	var path: Path3D = get_node(path_node)

	# Auxiliary curve for sweep profile orientation (also used as auxiliary spine wire).
	$AuxPath.curve = _build_auxiliary_curve(path.curve)

	# Prepare fresh display containers.
	_clear_display_meshes()

	var segment_count := 2 # path.curve.point_count - 1
	print("[OclManager] Generating ", segment_count, " segment(s)...")

	for i in range(segment_count):
		var seg_start := Time.get_ticks_usec()

		# --- Build the complete graph for this one Bezier segment ---
		var segment := _build_segment_graph(i, path, $AuxPath.curve)

		# --- Mesh immediately and append to combined display nodes ---
		_append_graph_vertices(segment.graph, $Vertices.multimesh)
		_append_graph_edges(segment.graph, $Edges.multimesh)
		_append_graph_faces(segment.graph, $Faces.mesh)

		# --- Free the per-segment graph (no longer needed) ---
		OclTopo.graph_free(segment.graph)

		var seg_ms := (Time.get_ticks_usec() - seg_start) / 1000.0
		print("[OclManager]  Segment ", i + 1, "/", segment_count, " done in ", seg_ms, " ms")

		# Future:
		#   emit_signal("generation_progress", i + 1, segment_count)
		#   yield(get_tree(), "idle_frame")   # allow live display refresh

	print("[OclManager] All ", segment_count, " segments generated in ",
		(Time.get_ticks_usec() - total_start) / 1000.0, " ms")
