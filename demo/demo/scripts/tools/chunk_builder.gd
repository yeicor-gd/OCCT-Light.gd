@tool
class_name ChunkBuilder
extends RefCounted

## Plans and builds merged OCCT graphs that span multiple Bezier segments.
##
## Instead of building one tiny graph per segment (the current approach in
## OclMeshBuilder), this helper batches a contiguous range of segments into a
## single OCCT graph, reducing the number of sweep operations and memory
## allocation overhead.
##
## Usage sketch (future):
##   var merger := ChunkBuilder.new()
##   merger.chunk_size = 4
##   var chunks = merger.plan_chunks(path.curve.point_count - 1)
##   for chunk in chunks:
##       var graph = merger.build_chunk_graph(chunk, path, aux_curve, profile_cfg)
##       # ... mesh and append as usual
##       OclTopo.graph_free(graph)
##
## TODO: Integrate with OclMeshBuilder.regenerate() — replace the per-segment
##       loop with chunked loops. May require adjusting TopoBuilders to handle
##       multi-segment spine wires or using a single compound wire.

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
## TODO: Implement multi-segment spine wire. Currently TopoBuilders only
##       builds per-segment wires. For a chunk we need to chain adjacent
##       Bezier curves into a single wire (or a compound) and sweep once.
##
##       Approach:
##         1. Create a graph.
##         2. For each segment in chunk, build its Bezier curve (no vertices/edges).
##         3. Join curves into a single wire (make_edge + make_wire with multiple edges).
##         4. Place one profile at the chunk's first segment start.
##         5. Sweep the multi-edge spine wire with the profile.
##         6. Return the graph.
func build_chunk_graph(
	chunk: Chunk,
	path_curve: Curve3D,
	aux_curve: Curve3D,
	profile_cfg: ProfileBuilder.Config,
	profile_strategy: int = 1,
) -> OclGraphHandle:
	push_warning("ChunkBuilder.build_chunk_graph is not yet implemented. ",
		"Falling back to a warning graph. Chunk: ", chunk.start_segment, "-", chunk.end_segment)

	# TODO: actual implementation
	var graph := GraphUtils.create_graph()
	return graph
