@tool
class_name ChunkBuilder
extends RefCounted

## Plans and builds merged OCCT graphs that span multiple Bezier segments.
##
## Instead of building one tiny graph per segment, this helper batches a
## contiguous range of segments into a single OCCT graph, reducing the number
## of sweep operations and memory allocation overhead.
##
## End caps are built in their own separate graphs (no boolean fuse needed)
## and returned alongside the main sweep graph in the array.
##
## Usage:
##   var merger := ChunkBuilder.new()
##   merger.chunk_size = 4
##   var chunks = merger.plan_chunks(path.curve.point_count - 1)
##   for chunk in chunks:
##       var graphs = merger.build_chunk_graphs(chunk, path, aux_curve, profile_cfg, fancy_flag)
##       for graph in graphs:
##           # ... mesh each graph
##           OclTopo.graph_free(graph)

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

## How many segments to merge into one graph. 1 = no merging (current behaviour).
var chunk_size: int = 1

# -----------------------------------------------------------------------------
# Data
# -----------------------------------------------------------------------------

## Describes one contiguous range of segments.
class Chunk:
	var start_segment: int
	var end_segment: int  # exclusive

	func _init(s: int, e: int):
		start_segment = s
		end_segment = e

	func segment_count() -> int:
		return end_segment - start_segment


# -----------------------------------------------------------------------------
# Planning
# -----------------------------------------------------------------------------

## Divide |total_segments| into contiguous chunks of |chunk_size|.
func plan_chunks(total_segments: int) -> Array[Chunk]:
	var chunks: Array[Chunk] = []
	var i := 0
	while i < total_segments:
		var end := mini(i + chunk_size, total_segments)
		chunks.append(Chunk.new(i, end))
		i = end
	return chunks


# -----------------------------------------------------------------------------
# Building
# -----------------------------------------------------------------------------

## Build OCCT graphs for a chunk: one main sweep graph plus optional end-cap
## graphs (each cap in its own standalone graph).
##
## The main sweep graph is always first in the returned array.  If end caps
## are requested, they follow as additional entries (start cap first, then
## end cap).  Each graph is independent -- no boolean operations link them.
##
## Returns an array of graph handles (caller must mesh and free each).
func build_chunk_graphs(
	chunk: Chunk,
	path_curve: Curve3D,
	aux_curve: Curve3D,
	profile_cfg: ProfileBuilder.Config,
	fancy: bool,
	do_main_path: bool,
	add_start_cap: bool,
	add_end_cap: bool,
) -> Array[OclGraphHandle]:
	var graphs: Array[OclGraphHandle] = []
	var status: OclCore.status
	
	if do_main_path:
		var graph := GraphUtils.create_graph()

		# Build multi-segment spine wire (main path).
		var spine_edges: Array[PackedInt64Array] = [PackedInt64Array()]
		var spine_wire := _build_multi_wire(graph, path_curve, chunk, spine_edges)

		# Build multi-segment auxiliary wire (orientation).
		var aux_edges: Array[PackedInt64Array] = [PackedInt64Array()]
		var aux_wire := _build_multi_wire(graph, aux_curve, chunk, aux_edges)

		# Build profile for the sweep.
		var start_xf := CurveUtils.transform_at_index(path_curve, chunk.start_segment)
		var profiles := ProfileBuilder.build_profiles(graph, profile_cfg, start_xf, fancy)
		
		if Engine.is_editor_hint() and graph != null:
			GraphUtils.check_graph(graph)

		# Sweep the multi-edge spine wire with the profile wire(s).
		for p in profiles:
			var sweep_info := OclPrimPipeShellInfo.new()
			sweep_info.profiles = PackedInt64Array([p.bits])
			sweep_info.mode = OclPrimSweep.PIPE_MODE_AUXILIARY_SPINE
			sweep_info.spine_wire = spine_wire.bits
			sweep_info.auxiliary_spine_wire = aux_wire.bits
			#sweep_info.auxiliary_curvilinear_equivalence = 1
			sweep_info.make_solid = 1
			var sweep_id := OclNodeId.new()
			status = OclPrimSweep.pipe_shell(graph, sweep_info, sweep_id) as OclCore.status
			assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
		
		GraphUtils.delete_orphans(graph, [OclCore.KIND_SHELL], [OclCore.KIND_EDGE, OclCore.KIND_WIRE])

		# Clean up temporary sketches.
		for bits in spine_edges[0]:
			status = OclTopoBuild.topo_remove_subgraph(graph, bits) as OclCore.status
			assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
		status = OclTopoBuild.topo_remove_subgraph(graph, spine_wire.bits) as OclCore.status
		assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
		for bits in aux_edges[0]:
			status = OclTopoBuild.topo_remove_subgraph(graph, bits) as OclCore.status
			assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
		status = OclTopoBuild.topo_remove_subgraph(graph, aux_wire.bits) as OclCore.status
		assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
		
		if Engine.is_editor_hint() and graph != null:
			GraphUtils.check_graph(graph)
		
		graphs.append(graph)

	# Add caps as separate standalone graphs (no fuse/clone needed).
	if add_start_cap:
		var start_xf2 := CurveUtils.transform_at_index(path_curve, chunk.start_segment)
		var cap_graph := _build_cap_graph(profile_cfg, start_xf2, true, fancy)
		if cap_graph != null:
			graphs.append(cap_graph)

	if add_end_cap:
		var end_xf := CurveUtils.transform_at_index(path_curve, chunk.end_segment)
		var cap_graph := _build_cap_graph(profile_cfg, end_xf, false, fancy)
		if cap_graph != null:
			graphs.append(cap_graph)

	return graphs


# -----------------------------------------------------------------------------
# Standalone cap graph builder
# -----------------------------------------------------------------------------

## Build a standalone OCCT graph containing just a rounded end cap solid.
##
## For fancy mode: builds a U-shape face from the profile wire, cuts it in
## half, and revolves 180° around the Y axis to form a domed end cap.
## For core-only mode: revolves the inner pathway wire into an open face
## (not a solid) for physics collision.
##
## The profile is rebuilt fresh in the cap's own graph (nodes from the sweep
## graph cannot be referenced across graphs).
##
## The caller must mesh and free the returned graph.
static func _build_cap_graph(
	cfg: ProfileBuilder.Config,
	xf: Transform3D,
	is_start: bool,
	fancy: bool,
) -> OclGraphHandle:
	var graph := GraphUtils.create_graph()
	var profiles := ProfileBuilder.build_profiles(graph, cfg, xf, fancy)

	for profile in profiles:
		var face_info := OclPrimPlanarFaceInfo.new()
		face_info.outer_wire = profile.bits
		var face := OclNodeId.new()
		var status := OclPrimSketch.planar_face(graph, face_info, face) as OclCore.status
		assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
		
		var half_face := _cut_face_in_half(graph, face, xf, cfg)

		var axis_origin := xf.origin + xf.basis.y * 0.0001 # No clue why this offset is needed to avoid an error, but it does not affect the result...
		var axis := OcctConversionUtils.v3_to_axis1(axis_origin, xf.basis.y)
		var revol_info := OclPrimRevolInfo.new()
		revol_info.profile = half_face.bits
		revol_info.axis = axis
		revol_info.angle = PI if is_start else -PI
		revol_info.copy = 1
		var cap := OclNodeId.new()
		status = OclPrimSweep.revol(graph, revol_info, cap) as OclCore.status
		assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

		status = OclTopoBuild.topo_remove_subgraph(graph, half_face.bits) as OclCore.status
		assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	
	GraphUtils.delete_orphans(graph, [OclCore.KIND_SHELL], [OclCore.KIND_EDGE, OclCore.KIND_WIRE])

	if Engine.is_editor_hint():
		GraphUtils.check_graph(graph)

	return graph


## Cut a planar face in half using a thin box placed below the face centre.
## Returns the half-face node ID (the upper part of the original face).
static func _cut_face_in_half(
	graph: OclGraphHandle,
	face: OclNodeId,
	xf: Transform3D,
	cfg: ProfileBuilder.Config
) -> OclNodeId:
	var box_width := ((cfg.ball_radius / cfg.ball_to_path_min_ratio.x / 2) + cfg.wall_thickness) * 2

	var box_cut_info := OclPrimBoxInfo.new()
	box_cut_info.placement = OcctConversionUtils.transform3d_to_occt_placement(xf.translated_local(
		Vector3.DOWN * box_width))
	box_cut_info.dx = box_width
	box_cut_info.dy = box_width * 2
	box_cut_info.dz = 0.01

	var box_cut := OclNodeId.new()
	var st := OclPrimSolid.box(graph, box_cut_info, box_cut) as OclCore.status
	assert(st == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())])

	var half_face := OclNodeId.new()
	st = OclBool.cut(graph, PackedInt64Array([face.bits]), PackedInt64Array([box_cut.bits]), OclBoolOptions.new(), half_face) as OclCore.status
	assert(st == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())])

	# Remove the temporary box.
	st = OclTopoBuild.topo_remove_subgraph(graph, box_cut.bits) as OclCore.status
	assert(st == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())])

	return half_face


# -----------------------------------------------------------------------------
# Multi-wire builder
# -----------------------------------------------------------------------------

## Build a multi-segment wire from |curve3d| for all segments in |chunk|.
##
## Adjacent edges share their junction vertex so the wire is a single
## continuous chain rather than disconnected edge fragments.
static func _build_multi_wire(
	graph: OclGraphHandle,
	curve3d: Curve3D,
	chunk: Chunk,
	out_edges: Array[PackedInt64Array] = [],
) -> OclNodeId:
	var edges: Array[OclOrientedNode] = []
	var edge_bits := PackedInt64Array()
	var prev_vertex: OclNodeId = OclNodeId.new()

	for i in range(chunk.start_segment, chunk.end_segment):
		var p0: Vector3 = curve3d.get_point_position(i)
		var p1: Vector3 = curve3d.get_point_position(i + 1)
		var c0: Vector3 = p0 + curve3d.get_point_out(i)
		var c1: Vector3 = p1 + curve3d.get_point_in(i + 1)

		var bez := TopoBuilders.make_bezier_curve(graph, p0, c0, c1, p1)

		# First segment creates both vertices; later segments share the previous
		# segment's end vertex as their start vertex, maintaining wire continuity.
		var sv: OclNodeId
		if i == chunk.start_segment:
			sv = TopoBuilders.make_vertex(graph, p0)
		else:
			sv = prev_vertex

		var ev := TopoBuilders.make_vertex(graph, p1)
		prev_vertex = ev

		var ed := TopoBuilders.make_edge(graph, bez, sv, ev)

		var oriented := OclOrientedNode.new()
		oriented.id = ed.bits
		oriented.orientation = OclTopoRelation.ORIENTATION_FORWARD
		edges.append(oriented)
		edge_bits.append(ed.bits)

	if not out_edges.is_empty():
		out_edges[0] = edge_bits

	return TopoBuilders.make_wire(graph, edges)
