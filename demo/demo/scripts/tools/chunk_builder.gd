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
## When clean_shortcuts is enabled and the chunk contains junction points
## (where a shortcut meets the main path), an inner hollow-profile sweep
## is built and boolean-cut at each junction to create connected openings.

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

## How many segments to merge into one graph. 1 = no merging (current behaviour).
var chunk_size: int = 1

## Debug: fuse cutter solids instead of cutting, so they remain visible.
var debug_fuse_junctions: bool = false

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
## When |clean_shortcuts| is true and |chunk_junctions| is non-empty,
## an inner-profile sweep is built and boolean-cut at each junction point
## to create connected openings between the main path and shortcuts.
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
	chunk_junctions_to_clean: Array
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
		var profiles := ProfileBuilder.build_profiles(graph, profile_cfg, start_xf, fancy, false)
		
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
		
		# --- Clean shortcuts: build inner sweep and boolean-cut at junctions ---
		if not chunk_junctions_to_clean.is_empty():
			_apply_junction_cuts(graph, profile_cfg, fancy, chunk_junctions_to_clean, debug_fuse_junctions)

		graphs.append(graph)

	# Add caps as separate standalone graphs (no fuse/clone needed).
	if add_start_cap:
		var start_xf2 := CurveUtils.transform_at_index(path_curve, chunk.start_segment)
		var cap_graph := _build_cap_graph(profile_cfg, start_xf2, true, fancy)
		if cap_graph != null:
			if not chunk_junctions_to_clean.is_empty():
				_apply_junction_cuts(cap_graph, profile_cfg, fancy, chunk_junctions_to_clean, debug_fuse_junctions)
			graphs.append(cap_graph)

	if add_end_cap:
		var end_xf := CurveUtils.transform_at_index(path_curve, chunk.end_segment)
		var cap_graph := _build_cap_graph(profile_cfg, end_xf, false, fancy)
		if cap_graph != null:
			if not chunk_junctions_to_clean.is_empty():
				_apply_junction_cuts(cap_graph, profile_cfg, fancy, chunk_junctions_to_clean, debug_fuse_junctions)
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
	var profiles := ProfileBuilder.build_profiles(graph, cfg, xf, fancy, false)

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
# Junction boolean-cut helpers
# -----------------------------------------------------------------------------

## Build an inner-profile cutter solid from a section of |other_curve|.
##
## Sweeps the inner (hollow) profile along the other path's spine+aux wires
## for the given segment range.  Returns [cutter_solid_id, edge_bits, wire_bits]
## where the latter two are temporary topology to remove after the boolean cut.
static func _build_inner_cutter_sweep(
	graph: OclGraphHandle,
	other_curve: Curve3D,
	other_aux_curve: Curve3D,
	profile_cfg: ProfileBuilder.Config,
	fancy: bool,
	segment_start: int,
	segment_end: int,  # exclusive
) -> Array:
	var cutter_chunk := Chunk.new(segment_start, segment_end)

	# Build spine wire from other path.
	var spine_edges: Array[PackedInt64Array] = [PackedInt64Array()]
	var spine_wire := _build_multi_wire(graph, other_curve, cutter_chunk, spine_edges)

	# Build auxiliary wire from other path.
	var aux_edges: Array[PackedInt64Array] = [PackedInt64Array()]
	var aux_wire := _build_multi_wire(graph, other_aux_curve, cutter_chunk, aux_edges)

	# Build inner profile at the start of the section.
	var start_xf := CurveUtils.transform_at_index(other_curve, segment_start)
	var profiles := ProfileBuilder.build_profiles(graph, profile_cfg, start_xf, fancy, true)

	# Sweep inner profile along the wires.
	var cutter_solid := OclNodeId.new()
	for p in profiles:
		var sweep_info := OclPrimPipeShellInfo.new()
		sweep_info.profiles = PackedInt64Array([p.bits])
		sweep_info.mode = OclPrimSweep.PIPE_MODE_AUXILIARY_SPINE
		sweep_info.spine_wire = spine_wire.bits
		sweep_info.auxiliary_spine_wire = aux_wire.bits
		sweep_info.make_solid = 1
		var status := OclPrimSweep.pipe_shell(graph, sweep_info, cutter_solid) as OclCore.status
		assert(status == OclCore.OK, "cutter sweep failed: %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	# Collect temporary topology bits for cleanup.
	var all_edge_bits := PackedInt64Array()
	all_edge_bits.append_array(spine_edges[0])
	all_edge_bits.append_array(aux_edges[0])

	var all_wire_bits := PackedInt64Array()
	all_wire_bits.append(spine_wire.bits)
	all_wire_bits.append(aux_wire.bits)

	return [cutter_solid, all_edge_bits, all_wire_bits]


## Apply boolean cuts at shortcut junction points.
##
## For each junction, builds an inner-profile cutter solid from the other path's
## curve and boolean-cuts it from the main sweep solid.  The graph is modified
## in place: the original sweep solid is replaced by the cut result.
static func _apply_junction_cuts(
	graph: OclGraphHandle,
	profile_cfg: ProfileBuilder.Config,
	fancy: bool,
	chunk_junctions: Array,
	debug_fuse: bool = false,
) -> void:
	if chunk_junctions.is_empty():
		return

	# Find the main sweep solid (should be the only solid after the outer sweep).
	var solid_ids := GraphUtils._collect_ids(graph, OclCore.KIND_SOLID)
	if solid_ids.is_empty():
		push_error("ChunkBuilder: no solid found for junction cuts")
		return
	var sweep_solid := OclNodeId.new()
	sweep_solid.bits = solid_ids[0] as int

	for junc in chunk_junctions:
		var other_curve: Curve3D = junc["other_curve"]
		var other_aux_curve: Curve3D = junc["other_aux_curve"]
		var seg_start: int = junc["other_segment_start"]
		var seg_end: int = junc["other_segment_end"]

		# Clamp to valid range.
		seg_start = maxi(0, seg_start)
		seg_end = mini(other_curve.point_count - 1, seg_end)
		if seg_end <= seg_start:
			continue

		# Build cutter solid in the same graph.
		var cutter_data := _build_inner_cutter_sweep(
			graph, other_curve, other_aux_curve, profile_cfg, fancy, seg_start, seg_end,
		)
		var cutter_id: OclNodeId = cutter_data[0]
		var edge_bits: PackedInt64Array = cutter_data[1]
		var wire_bits: PackedInt64Array = cutter_data[2]

		if cutter_id.bits == 0:
			continue

		# Boolean op: cut or fuse (for debugging).
		var result := OclNodeId.new()
		var status: OclCore.status
		if debug_fuse:
			status = OclBool.fuse(
				graph,
				PackedInt64Array([sweep_solid.bits]),
				PackedInt64Array([cutter_id.bits]),
				OclBoolOptions.new(),
				result,
			) as OclCore.status
			assert(status == OclCore.OK, "junction fuse failed: %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
		else:
			status = OclBool.cut(
				graph,
				PackedInt64Array([sweep_solid.bits]),
				PackedInt64Array([cutter_id.bits]),
				OclBoolOptions.new(),
				result,
			) as OclCore.status
			assert(status == OclCore.OK, "junction cut failed: %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

		if not debug_fuse:
			# Remove cutter solid (only when cutting — keep it visible for fuse debug).
			status = OclTopoBuild.topo_remove_subgraph(graph, cutter_id.bits) as OclCore.status
			assert(status == OclCore.OK)

		# Remove the now-orphaned original sweep solid.
		status = OclTopoBuild.topo_remove_subgraph(graph, sweep_solid.bits) as OclCore.status
		assert(status == OclCore.OK)

		# Remove temporary wires and edges from the cutter build.
		for bits in edge_bits:
			status = OclTopoBuild.topo_remove_subgraph(graph, bits) as OclCore.status
		for bits in wire_bits:
			status = OclTopoBuild.topo_remove_subgraph(graph, bits) as OclCore.status
		
		GraphUtils.delete_orphans(graph, [OclCore.KIND_SHELL], [OclCore.KIND_EDGE, OclCore.KIND_WIRE])

		# The result becomes the new main solid for subsequent ops.
		sweep_solid = result


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
