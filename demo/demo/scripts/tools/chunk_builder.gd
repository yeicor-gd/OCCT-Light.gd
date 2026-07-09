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
# Building (skeleton)
# -----------------------------------------------------------------------------

## Build a single OCCT graph containing all segments in |chunk|.
##
## Chains the Bezier curves of the chunk's segments into a single multi-edge
## spine wire, places one profile at the first segment's start, and sweeps.
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
	# Build profile BEFORE wires so that topo_remove_subgraph / topo_remove
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
	var spine_wire := _build_multi_wire(graph, path_curve, chunk)

	# Build multi-segment auxiliary wire (orientation).
	var aux_wire := _build_multi_wire(graph, aux_curve, chunk)

	# Sweep the multi-edge spine wire with the profile.
	var sweep_info := OclPrimPipeShellInfo.new()
	sweep_info.profiles = PackedInt64Array([start_profile.bits])
	sweep_info.spine_wire = spine_wire.bits
	sweep_info.mode = OclPrimSweep.PIPE_MODE_AUXILIARY_SPINE
	sweep_info.auxiliary_spine_wire = aux_wire.bits
	#sweep_info.auxiliary_curvilinear_equivalence = 1
	sweep_info.make_solid = 1
	var sweep_id := OclNodeId.new()
	var status := OclPrimSweep.pipe_shell(graph, sweep_info, sweep_id) as OclCore.status
	assert(status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())],
	)
	
	# Clean up temporary sketches.
	status = OclTopoBuild.topo_remove_subgraph(graph, start_profile.bits) as OclCore.status
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	status = OclTopoBuild.topo_remove_subgraph(graph, spine_wire.bits) as OclCore.status # FIXME: Only removes first edge for some reason
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	status = OclTopoBuild.topo_remove_subgraph(graph, aux_wire.bits) as OclCore.status # FIXME: Only removes first edge for some reason
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	if Engine.is_editor_hint():
		GraphUtils.check_graph(graph)

	return graph


## Build a multi-segment wire from |curve3d| for all segments in |chunk|.
##
## Adjacent edges share their junction vertex so the wire is a single
## continuous chain rather than disconnected edge fragments.
static func _build_multi_wire(graph: OclGraphHandle, curve3d: Curve3D, chunk: Chunk) -> OclNodeId:
	var edges: Array[OclOrientedNode] = []
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

	return TopoBuilders.make_wire(graph, edges)
