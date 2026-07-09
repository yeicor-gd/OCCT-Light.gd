@tool
class_name ChunkBuilder
extends RefCounted

## Plans and builds merged OCCT graphs that span multiple Bezier segments.
##
## Instead of building one tiny graph per segment, this helper batches a
## contiguous range of segments into a single OCCT graph, reducing the number
## of sweep operations and memory allocation overhead.
##
## Usage:
##   var merger := ChunkBuilder.new()
##   merger.chunk_size = 4
##   var chunks = merger.plan_chunks(path.curve.point_count - 1)
##   for chunk in chunks:
##       var graph = merger.build_chunk_graph(chunk, path, aux_curve, profile_cfg)
##       # ... mesh and append as usual
##       OclTopo.graph_free(graph)

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

## How many segments to merge into one graph. 1 = no merging (current behaviour).
var chunk_size: int = 1

## Whether to merge profiles too (reuse the same profile wire for all segments
## in a chunk, placed at the first segment's start transform).
var merge_profiles: bool = true

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

## Build a single OCCT graph containing all segments in |chunk|.
##
## Chains the Bezier curves of the chunk's segments into a single multi-edge
## spine wire, places one profile at the first segment's start, and sweeps.
## Builds end caps via a 180° revolve of the split profile.
##
## Returns the graph handle (caller must mesh and free).
func build_chunk_graph(
	chunk: Chunk,
	path_curve: Curve3D,
	aux_curve: Curve3D,
	profile_cfg: ProfileBuilder.Config,
	profile_strategy: int = 1,
) -> OclGraphHandle:
	var graph := GraphUtils.create_graph()

	# Profile at the first segment's start transform.
	# Build profile BEFORE wires so that topo_remove / topo_remove_subgraph
	# calls inside ProfileBuilder don't invalidate the ShapesView cache that
	# the wire's TopoDS_Shape was registered into by topo_make_wire.
	var start_xf := CurveUtils.transform_at_index(path_curve, chunk.start_segment)
	var start_profile: OclNodeId

	match profile_strategy:
		0:
			start_profile = ProfileBuilder.build_profile_fast(graph, profile_cfg, start_xf)[0]
		1:
			start_profile = ProfileBuilder.build_profile_cool(graph, profile_cfg, start_xf)[0]
		_:
			push_error("ChunkBuilder: unknown profile strategy: ", profile_strategy)
			OclTopo.graph_free(graph)
			return null

	# Build multi-segment spine wire (main path).
	var spine_edges: Array[PackedInt64Array] = [PackedInt64Array()]
	var spine_wire := _build_multi_wire(graph, path_curve, chunk, spine_edges)

	# Build multi-segment auxiliary wire (orientation).
	var aux_edges: Array[PackedInt64Array] = [PackedInt64Array()]
	var aux_wire := _build_multi_wire(graph, aux_curve, chunk, aux_edges)

	# Sweep the multi-edge spine wire with the profile.
	var sweep_info := OclPrimPipeShellInfo.new()
	sweep_info.profiles = PackedInt64Array([start_profile.bits])
	sweep_info.spine_wire = spine_wire.bits
	sweep_info.mode = OclPrimSweep.PIPE_MODE_AUXILIARY_SPINE
	sweep_info.auxiliary_spine_wire = aux_wire.bits
	sweep_info.make_solid = 1
	var sweep_id := OclNodeId.new()
	var status := OclPrimSweep.pipe_shell(graph, sweep_info, sweep_id) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())],
	)

	# TODO: End caps via 180° revolve of half-profile.
	#var end_xf := CurveUtils.transform_at_index(path_curve, chunk.end_segment - 1)
	#var fused_id := _add_revolved_cap(graph, sweep_id, start_xf, profile_cfg, profile_strategy, true)
	#fused_id = _add_revolved_cap(graph, fused_id, end_xf, profile_cfg, profile_strategy, false)

	# Clean up temporary sketches.
	# Remove each edge of the multi-edge wires individually because
	# topo_remove_subgraph on a multi-edge wire only removes the first edge
	# (the remaining edges form a chain not directly under the wire).
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

	status = OclTopoBuild.topo_remove_subgraph(graph, start_profile.bits) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	if Engine.is_editor_hint():
		GraphUtils.check_graph(graph)

	return graph


# -----------------------------------------------------------------------------
# End cap helper
# -----------------------------------------------------------------------------

## Build a 180° revolved half-profile cap at |xf| and fuse it onto |sweep_root|.
##
## Builds a copy of the profile, splits away one half (NEGATIVE at start,
## POSITIVE at end), revolves the half 180° around the local Y axis, and fuses
## the resulting solid onto |sweep_root|.  Returns the fused node ID.
static func _add_revolved_cap(
	graph: OclGraphHandle,
	sweep_root: OclNodeId,
	xf: Transform3D,
	profile_cfg: ProfileBuilder.Config,
	profile_strategy: int,
	is_start: bool,
) -> OclNodeId:
	# Build another copy of the profile.
	var profile: OclNodeId
	match profile_strategy:
		0:
			profile = ProfileBuilder.build_profile_fast(graph, profile_cfg, xf)[0]
		1:
			profile = ProfileBuilder.build_profile_cool(graph, profile_cfg, xf)[0]
		_:
			push_error("_add_revolved_cap: unknown profile strategy: ", profile_strategy)
			return sweep_root

	# Split away one half of the profile.
	var split_opts := OclTopoSplitByPlaneOptions.new()
	split_opts.root = profile.bits
	split_opts.point = OcctConversionUtils.v3_to_p3(xf.origin)
	split_opts.normal = OcctConversionUtils.v3_to_d3(xf.basis.x)  # Split along local X

	if is_start:
		split_opts.keep = OclTopoAlgo.TOPO_SPLIT_KEEP_NEGATIVE
	else:
		split_opts.keep = OclTopoAlgo.TOPO_SPLIT_KEEP_POSITIVE

	var split_result := OclNodeId.new()
	var st := OclTopoAlgo.make_split_by_plane(graph, split_opts, graph, split_result) as OclCore.status
	assert(st == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())],
	)

	# Remove the original (now superseded) profile wire.
	st = OclTopoBuild.topo_remove(graph, profile.bits) as OclCore.status
	assert(st == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())])

	# Revolution axis: local Y through the profile centre.
	var axis := OcctConversionUtils.v3_to_axis1(xf.origin, xf.basis.y)

	# Revolve the half-profile 180° around the local Y axis.
	var revol_info := OclPrimRevolInfo.new()
	revol_info.profile = split_result.bits
	revol_info.axis = axis
	revol_info.angle = PI

	var revolved := OclNodeId.new()
	st = OclPrimSweep.revol(graph, revol_info, revolved) as OclCore.status
	assert(st == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())],
	)

	# Remove the split half-profile now that it's been revolved.
	st = OclTopoBuild.topo_remove(graph, split_result.bits) as OclCore.status
	assert(st == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())])

	# Fuse the revolved cap onto the sweep result.
	var bool_opts := OclBoolOptions.new()
	bool_opts.simplify_result = 1

	var fused := OclNodeId.new()
	st = OclBool.fuse(
		graph,
		PackedInt64Array([sweep_root.bits]),
		PackedInt64Array([revolved.bits]),
		bool_opts,
		fused,
	) as OclCore.status
	assert(st == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())],
	)

	# Remove the revolve result (now merged into fused).
	st = OclTopoBuild.topo_remove(graph, revolved.bits) as OclCore.status
	assert(st == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())])

	# Also remove the original sweep root if it differs from fused.
	if sweep_root.bits != fused.bits:
		st = OclTopoBuild.topo_remove(graph, sweep_root.bits) as OclCore.status
		assert(st == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())])

	return fused


# -----------------------------------------------------------------------------
# Multi-wire builder
# -----------------------------------------------------------------------------

## Build a multi-segment wire from |curve3d| for all segments in |chunk|.
##
## Adjacent edges share their junction vertex so the wire is a single
## continuous chain rather than disconnected edge fragments.
##
## The edge node IDs are appended to |out_edges| as a single PackedInt64Array
## so callers can remove each edge individually when cleaning up.
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
