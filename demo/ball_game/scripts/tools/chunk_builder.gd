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

## When true, run analytical geometry validation after each sweep/loft attempt
## (volume, face area, topology errors, face-face intersection).  Failed checks
## trigger fallback to the next attempt in the ladder.
## When false, only a hard OCCT failure (non-OK status) causes a fallback —
## much faster but may let degenerate geometry through.
var validate_geometry: bool = true

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
## end cap).  Each graph is independent — no boolean operations link them.
##
## |sweep_attempts| is an ordered list of {mode: SweepMode, fancy: bool}
## dictionaries tried in sequence; the first that succeeds wins.  This lets
## the caller express any fallback ladder — display escalates quality while
## physics starts low and can escalate if needed.
##
## Returns an array of graph handles (caller must mesh and free each).
## Returns an empty array only when every attempt in |sweep_attempts| fails.
##
## |out_used_attempt| is set to the index into |sweep_attempts| that produced
## the graphs, so callers can detect when two configurations converge on the
## same attempt and share the result.
func build_chunk_graphs(
	chunk: Chunk,
	path_curve: Curve3D,
	aux_curve: Curve3D,
	profile_cfg: ProfileBuilder.Config,
	do_main_path: bool,
	add_start_cap: bool,
	add_end_cap: bool,
	chunk_junctions_to_clean: Array,
	sweep_attempts: Array,       # Array[{mode: int, fancy: bool}] ordered best→worst
	out_used_attempt: Array,     # [int] out-param; set to winning attempt index, or -1
	segment_wall_heights: PackedFloat32Array = PackedFloat32Array(),
	pobstacle_pos_freq: float = 0.0,
	_seed: int = 0,
	pobstacle_debug: bool = false,
	pobstacle_max_rotation: float = 1.0,
	pobstacle_max_offset: Vector2 = Vector2(1.0, 1.0),
	pobstacle_min_offset: Vector2 = Vector2(0.0, 0.0),
	pshortcut_cutter_sweep_mode: int = 0,
) -> Array[OclGraphHandle]:
	if not out_used_attempt.is_empty():
		out_used_attempt[0] = -1
	var graphs: Array[OclGraphHandle] = []
	var winning_fancy := false  # tracked for cap building

	if do_main_path:
		var graph: OclGraphHandle = null
		var used_idx := -1

		for attempt_idx in range(sweep_attempts.size()):
			var attempt: Dictionary = sweep_attempts[attempt_idx]
			var attempt_fancy: bool = attempt.get("fancy", false)
			var attempt_mode: int  = attempt.get("mode", OclMeshBuilder.SweepMode.LOFT_RULED)
			var candidate := _build_chunk_graph(chunk, path_curve, aux_curve, profile_cfg,
				attempt_fancy, attempt_mode, segment_wall_heights, validate_geometry)
			if candidate != null:
				graph = candidate
				used_idx = attempt_idx
				winning_fancy = attempt_fancy
				break

		if graph == null:
			return []  # All attempts failed.

		if not out_used_attempt.is_empty():
			out_used_attempt[0] = used_idx

		if Engine.is_editor_hint() and graph != null:
			GraphUtils.check_graph(graph)

		# --- Generate obstacles after sweep ---
		if (pobstacle_pos_freq > 0.0):
			_generate_obstacles(graph, path_curve, aux_curve, chunk, profile_cfg, pobstacle_pos_freq, _seed, segment_wall_heights, pobstacle_debug, pobstacle_max_rotation, pobstacle_max_offset, pobstacle_min_offset)

		# --- Clean shortcuts: build inner sweep and boolean-cut at junctions ---
		# _apply_junction_cuts always tries both fancy levels per junction,
		# so the cutter can match the other path's geometry regardless of
		# which fancy level this chunk ended up using.
		if not chunk_junctions_to_clean.is_empty():
			_apply_junction_cuts(graph, profile_cfg, winning_fancy, chunk_junctions_to_clean, debug_fuse_junctions, pshortcut_cutter_sweep_mode)

		graphs.append(graph)

	# Add caps as separate standalone graphs (no fuse/clone needed).
	if add_start_cap:
		var start_xf2 := CurveUtils.transform_at_index(path_curve, chunk.start_segment, aux_curve)
		var start_wh: float = -1.0
		if segment_wall_heights.size() > 0:
			start_wh = segment_wall_heights[0]
		var cap_graph := _build_cap_graph(profile_cfg, start_xf2, true, winning_fancy, start_wh)
		if cap_graph != null:
			if not chunk_junctions_to_clean.is_empty():
				_apply_junction_cuts(cap_graph, profile_cfg, winning_fancy, chunk_junctions_to_clean, debug_fuse_junctions, pshortcut_cutter_sweep_mode)
			graphs.append(cap_graph)

	if add_end_cap:
		var end_xf := CurveUtils.transform_at_index(path_curve, chunk.end_segment, aux_curve)
		var end_wh: float = -1.0
		if segment_wall_heights.size() > 1:
			end_wh = segment_wall_heights[segment_wall_heights.size() - 1]
		var cap_graph := _build_cap_graph(profile_cfg, end_xf, false, winning_fancy, end_wh)
		if cap_graph != null:
			if not chunk_junctions_to_clean.is_empty():
				_apply_junction_cuts(cap_graph, profile_cfg, winning_fancy, chunk_junctions_to_clean, debug_fuse_junctions, pshortcut_cutter_sweep_mode)
			graphs.append(cap_graph)

	return graphs


## Build the main sweep graph for a chunk in a single fresh graph.
##
## Creates a new graph, builds profiles at all chunk points, and sweeps each
## split.  Returns the completed graph on success, or null on failure (any
## partially-created geometry is freed).
static func _build_chunk_graph(
	chunk: Chunk,
	path_curve: Curve3D,
	aux_curve: Curve3D,
	profile_cfg: ProfileBuilder.Config,
	fancy: bool,
	sweep_mode: int,
	segment_wall_heights: PackedFloat32Array,
	validate: bool = true,
) -> OclGraphHandle:
	var graph := GraphUtils.create_graph()
	var status: OclCore.status

	# Build multi-segment spine wire (main path).
	var spine_edges: Array[PackedInt64Array] = [PackedInt64Array()]

	# Build multi-segment auxiliary wire (orientation).
	var aux_edges: Array[PackedInt64Array] = [PackedInt64Array()]

	# Build profiles at all the curve nodes of the chunk.
	var max_profile_count := 0
	var segments_profiles := []
	for segment_i in range(chunk.start_segment, chunk.end_segment + 1):
		var segment_xf := CurveUtils.transform_at_index(path_curve, segment_i, aux_curve)
		var seg_off := segment_i - chunk.start_segment
		var wall_height := segment_wall_heights[seg_off]
		var segment_profiles := ProfileBuilder.build_profiles(graph, profile_cfg, segment_xf, fancy, false, wall_height)
		max_profile_count = max(max_profile_count, segment_profiles.size())
		segments_profiles.append(segment_profiles)

	# Sweep the multi-edge spine wire, one pipe_shell per profile shape.
	for pi in range(max_profile_count):
		# Split sweeps for non-continuous profile indices of sections.
		var splits_profiles := []
		var run_start := -1  # First point index of current contiguous run (-1 = no active run).
		for segment_i_off in range(chunk.end_segment + 1 - chunk.start_segment):
			var segment_i := chunk.start_segment + segment_i_off
			var has_profile: bool = pi < segments_profiles[segment_i_off].size()
			var is_end := segment_i == chunk.end_segment

			# Start a new run when we find a point with the profile.
			if has_profile and run_start == -1:
				run_start = segment_i

			# Determine whether to finalize the current run.
			var finalize := false
			var last_good := -1  # Last point in the run that has the profile (inclusive).
			if not has_profile and run_start != -1:
				# This point lacks the profile; end run at the previous point.
				finalize = true
				last_good = segment_i - 1
			elif is_end and run_start != -1:
				# End of chunk; include this point only if it has the profile.
				finalize = true
				last_good = segment_i if has_profile else segment_i - 1

			if finalize and last_good > run_start:
				var from_off := run_start - chunk.start_segment
				var to_off := last_good - chunk.start_segment
				var profiles: Array[OclNodeId]
				profiles.assign(segments_profiles.slice(from_off, to_off + 1).map(func(a: Array): return a[pi]))
				splits_profiles.append({
					"profiles": profiles,
					"run_start": run_start,
					"pi": pi,
					"sub_spine_wire": _build_multi_wire(graph, path_curve, Chunk.new(run_start, last_good), spine_edges),
					"sub_aux_wire": _build_multi_wire(graph, aux_curve, Chunk.new(run_start, last_good), aux_edges),
				})

			if finalize:
				run_start = -1

		# Sweep each split — any failure aborts the entire chunk.
		for split in splits_profiles:
			var split_run_start: int = split["run_start"]

			var sweep_result: Array[OclNodeId] = []
			var max_area := _compute_max_face_area(profile_cfg, path_curve, aux_curve, split_run_start, split_run_start + split["profiles"].size() - 1)
			if sweep_mode == OclMeshBuilder.SweepMode.SWEEP:
				sweep_result = _try_sweep_and_validate(graph, split["profiles"], split["sub_spine_wire"], split["sub_aux_wire"], max_area if validate else -1.0, validate)
			elif sweep_mode == OclMeshBuilder.SweepMode.LOFT_RULED:
				sweep_result = _try_pairwise_loft(graph, split["profiles"], Callable(), max_area if validate else -1.0, validate)
			else:
				assert(false, "Unknown sweep_mode")

			if sweep_result.is_empty():
				# This split failed — abort the entire chunk.
				_free_graph(graph)
				return null

	GraphUtils.delete_orphans(graph, [OclCore.KIND_SHELL], [OclCore.KIND_EDGE, OclCore.KIND_WIRE])

	# Clean up temporary sketches.
	for bits in spine_edges[0]:
		status = OclTopoBuild.topo_remove_subgraph(graph, bits) as OclCore.status
		assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	for bits in aux_edges[0]:
		status = OclTopoBuild.topo_remove_subgraph(graph, bits) as OclCore.status
		assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

	return graph

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
	wall_height_override: float = -1.0,
) -> OclGraphHandle:
	var graph := GraphUtils.create_graph()
	var profiles := ProfileBuilder.build_profiles(graph, cfg, xf, fancy, false, wall_height_override)

	for profile in profiles:
		var face_info := OclPrimPlanarFaceInfo.new()
		face_info.outer_wire = profile.bits
		var face := OclNodeId.new()
		var status := OclPrimSketch.planar_face(graph, face_info, face) as OclCore.status
		assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

		var half_face := _cut_face_in_half(graph, face, xf, cfg)

		var axis_origin := xf.origin + xf.basis.y * 0.0001 # No clue why this offset is needed to avoid an error, but it does not affect the result...
		var axis := OcctConversionUtils.v3_to_axis1(axis_origin, -xf.basis.y if is_start else xf.basis.y)
		var revol_info := OclPrimRevolInfo.new()
		revol_info.profile = half_face.bits
		revol_info.axis = axis
		revol_info.angle = -PI
		revol_info.copy = 1
		var cap := OclNodeId.new()
		status = OclPrimSweep.revol(graph, revol_info, cap) as OclCore.status
		if status != OclCore.OK:
			push_warning("_build_cap_graph: OclPrimSweep.revol: Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
		
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


static func _has_faces(graph: OclGraphHandle, solid_id: OclNodeId) -> bool:
	if solid_id.bits == 0:
		return false
	var desc_buf := OclNodeIdArray.new()
	var status := OclTopoBuild.graph_descendants_get(graph, solid_id.bits, OclCore.KIND_FACE, desc_buf) as OclCore.status
	return status == OclCore.OK and desc_buf.data.size() > 0


## Compute the surface area of a single face node using graph mass properties.
static func _face_area(graph: OclGraphHandle, face_bits: int) -> float:
	var props := OclGraphMassProperties.new()
	var status := OclTopoBuild.graph_mass_properties_get(graph, face_bits, props) as OclCore.status
	if status != OclCore.OK:
		return 0.0
	return props.get_surface_area()


## Compute the max face area threshold: 1.5 × tube_width × max_seg_length,
## where tube_width = ball_radius / ball_to_path_min_ratio.x.
static func _compute_max_face_area(profile_cfg: ProfileBuilder.Config, curve: Curve3D, aux_curve: Curve3D, seg_start: int, seg_end: int) -> float:
	var tube_width := profile_cfg.ball_radius / profile_cfg.ball_to_path_min_ratio.x
	var max_seg_len := 0.0
	for si in range(seg_start, seg_end):
		var p0 := CurveUtils.transform_at_index(curve, si, aux_curve).origin
		var p1 := CurveUtils.transform_at_index(curve, si + 1, aux_curve).origin
		max_seg_len = max(max_seg_len, p0.distance_to(p1))
	return 8 * tube_width * max_seg_len


## BRepCheck_Status bit values for issues that indicate a genuinely broken
## or self-intersecting solid — not just tolerance/parameterisation warnings.
##
## Indices are 0-based from BRepCheck_Status enum; status_bit = 1 << index.
##   18 = SelfIntersectingWire   (wire crosses itself)
##   22 = IntersectingWires      (two wires on a face intersect)
##   26 = BadOrientation         (face orientation inconsistent with shell)
##   27 = BadOrientationOfSubshape (subshape oriented wrongly — wrong edge link)
##   28 = NotClosed              (shell is not closed — open solid)
##   29 = NotConnected           (shell has disconnected components)
const TOPOLOGY_ERROR_BITS := (
	(1 << 18) |  # SelfIntersectingWire
	(1 << 22) |  # IntersectingWires
	(1 << 26) |  # BadOrientation
	(1 << 27) |  # BadOrientationOfSubshape — catches wrong-profile-edge-link
	(1 << 28) |  # NotClosed
	(1 << 29)    # NotConnected
)

## Return true if the graph has any FATAL issues, or any ERROR issues whose
## status_bit indicates self-intersection, bad orientation, or disconnection.
## Tolerance/parameterisation ERRORs (e.g. InvalidSameParameterFlag) are
## intentionally ignored — they are common on valid swept geometry.
static func _solid_has_topology_errors(graph: OclGraphHandle, _solid_id: OclNodeId) -> bool:
	var issues := OclTopoCheckIssueArray.new()
	if OclTopoAlgo.check(graph, issues) != OclCore.OK:
		return false  # check call failed — be optimistic
	for issue_ in issues.data:
		var issue: OclTopoCheckIssue = issue_
		if issue.severity >= OclTopoAlgo.TOPO_CHECK_FATAL:
			return true
		if issue.severity == OclTopoAlgo.TOPO_CHECK_ERROR:
			if (issue.status_bit & TOPOLOGY_ERROR_BITS) != 0:
				return true
	return false


## Deep-clone a topology graph.  The caller owns the returned handle and
## must free it with _free_graph (or OclTopo.graph_free).
static func _clone_graph(source: OclGraphHandle) -> OclGraphHandle:
	var cloned := OclGraphHandle.new()
	var status := OclTopoBuild.graph_clone(source, cloned) as OclCore.status
	assert(status == OclCore.OK, "ChunkBuilder: graph_clone failed: %s" % [OclCore.status_to_string(status)])
	return cloned


## Null-safe graph free.
static func _free_graph(graph: OclGraphHandle) -> void:
	if graph != null:
		OclTopo.graph_free(graph)


## Validate a sweep or loft solid.
##
## |check_volume|: set true only for full pipe_shell solids (not per-pair lofts
##   whose thin slab shape yields near-zero volume by construction).
##   Volume > 0 catches self-intersecting / inside-out multi-segment sweeps.
## |max_face_area|: cheap early-out for runaway large faces (default -1 = skip).
##
## FATAL topology issues are checked unconditionally — they indicate a genuinely
## broken B-rep (missing faces, non-manifold structure, etc.).
static func _validate_solid_geometry(
		graph: OclGraphHandle, solid_id: OclNodeId,
		max_face_area: float = -1.0,
		check_volume: bool = false) -> bool:
	if not _has_faces(graph, solid_id):
		return false

	# ── Volume check (multi-segment sweeps only) ───────────────────────────────
	if check_volume:
		var props := OclGraphMassProperties.new()
		if OclTopoBuild.graph_mass_properties_get(graph, solid_id.bits, props) == OclCore.OK:
			# Reject clearly negative or zero volume (self-intersecting / inside-out).
			# Use a small negative tolerance rather than strict > 0 to avoid rejecting
			# thin solids (e.g. roof slabs) where BRepGProp returns a tiny negative
			# value due to numerical cancellation.
			if props.get_volume() < -1e-6:
				return false

	# ── Optional face area cap ─────────────────────────────────────────────────
	if max_face_area > 0:
		var face_buf := OclNodeIdArray.new()
		if OclTopoBuild.graph_descendants_get(graph, solid_id.bits, OclCore.KIND_FACE, face_buf) == OclCore.OK:
			for face_bits in face_buf.data:
				if _face_area(graph, face_bits) > max_face_area:
					return false

	# ── OCCT topology check (FATAL + structural ERRORs) ───────────────────────
	if _solid_has_topology_errors(graph, solid_id):
		return false

	# ── Face-face self-intersection (slowest, only when volume check passed) ──
	# Only run the expensive face-pair intersection test when check_volume is
	# enabled (pipe_shell sweeps) because those are the solids where wrong-edge-
	# linking self-intersections can occur.  For per-pair lofts the volume check
	# is disabled and this check would produce too many false positives.
	if check_volume and _solid_has_face_intersections(graph, solid_id):
		return false

	return true


## Delegates to OclTopoRelation.solid_is_self_intersecting — a native API
## that runs bounded BRepAlgoAPI_Section on every face pair, skips existing
## boundary edges, and only counts new intersection edges above min_edge_length.
## Min arc-length for a face-face intersection edge to count as genuine.
## Set conservatively to avoid false positives from curved swept surfaces
## whose underlying geometric extensions produce short phantom section edges.
## A genuine wrong-winding crossing spans at least the profile inner width.
const SELF_INTERSECTION_MIN_EDGE_LENGTH := 0.3

static func _solid_has_face_intersections(graph: OclGraphHandle, solid_id: OclNodeId) -> bool:
	var out_result := OclInt32.new()
	var st := OclTopoExtra.solid_is_self_intersecting(
		graph, solid_id.bits, SELF_INTERSECTION_MIN_EDGE_LENGTH, out_result) as OclCore.status
	if st != OclCore.OK:
		return false  # call failed — be optimistic
	return out_result.value != 0


## Attempt pipe_shell with progressively more forgiving transition modes.
## RIGHT_CORNER is fastest but fails on sharp-curvature spines with fancy profiles.
## ROUND_CORNER handles tight bends more robustly.
## MODIFIED (DiscreteTrihedron law) is the most forgiving fallback.
static func _try_sweep(graph: OclGraphHandle, profiles: Array[OclNodeId], spine: OclNodeId, spine_aux: OclNodeId) -> Array[OclNodeId]:
	var profile_bits := PackedInt64Array(profiles.map(func(p: OclNodeId): return p.bits))
	for transition in [
		OclPrimSweep.PIPE_TRANSITION_RIGHT_CORNER,
		OclPrimSweep.PIPE_TRANSITION_ROUND_CORNER,
		OclPrimSweep.PIPE_TRANSITION_MODIFIED,
	]:
		var sweep_info := OclPrimPipeShellInfo.new()
		sweep_info.profiles = profile_bits
		sweep_info.mode = OclPrimSweep.PIPE_MODE_AUXILIARY_SPINE
		sweep_info.spine_wire = spine.bits
		sweep_info.auxiliary_spine_wire = spine_aux.bits
		sweep_info.transition = transition
		sweep_info.make_solid = 1
		var sweep_id := OclNodeId.new()
		var status := OclPrimSweep.pipe_shell(graph, sweep_info, sweep_id) as OclCore.status
		if status == OclCore.OK and sweep_id.bits != 0:
			return [sweep_id]
	return []


## Try pairwise ruled loft through profile pairs.  For each pair, fancy
## profiles are tried first; on failure the specific pair falls back to
## non-fancy profiles via rebuild_fn (when provided).
## Any invalid geometry from a failed attempt is removed before retrying.
static func _try_pairwise_loft(graph: OclGraphHandle, profiles: Array[OclNodeId], rebuild_fn: Callable = Callable(), max_face_area: float = -1.0, validate: bool = true) -> Array[OclNodeId]:
	var solids: Array[OclNodeId] = []
	for i in range(profiles.size() - 1):
		var info := OclPrimLoftInfo.new()
		info.is_solid = 1
		info.ruled = 1
		info.sections = PackedInt64Array([profiles[i].bits, profiles[i + 1].bits])
		var solid := OclNodeId.new()
		var status := OclPrimSweep.loft(graph, info, solid) as OclCore.status
		# Per-pair lofts: validate with face area cap and topology check when enabled.
		# Volume check is skipped — OCCT cannot reliably compute volume for
		# ruled-loft solids built from open (U-channel) profiles.
		var valid := status == OclCore.OK and (not validate or _validate_solid_geometry(graph, solid, max_face_area, false))

		if not valid and rebuild_fn.is_valid():
			if solid.bits != 0:
				OclTopoBuild.topo_remove_subgraph(graph, solid.bits)
			push_warning("Loft pair %d failed (status=%s), retrying with non-fancy profiles" % [i, OclCore.status_to_string(status)])
			var p0 := rebuild_fn.call(graph, i) as OclNodeId
			var p1 := rebuild_fn.call(graph, i + 1) as OclNodeId
			info.sections = PackedInt64Array([p0.bits, p1.bits])
			solid = OclNodeId.new()
			status = OclPrimSweep.loft(graph, info, solid) as OclCore.status
			valid = status == OclCore.OK and (not validate or _validate_solid_geometry(graph, solid, max_face_area, false))

		if not valid:
			if solid.bits != 0:
				OclTopoBuild.topo_remove_subgraph(graph, solid.bits)
			#push_error("loft pair %d failed all fallbacks: %s - %s" % [i, OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
			# Clean up previously accumulated solids from earlier pairs.
			for prev in solids:
				if prev.bits != 0:
					OclTopoBuild.topo_remove_subgraph(graph, prev.bits)
			return []

		solids.append(solid)
	return solids


## Try a single sweep (pipe_shell) in-place on |graph|, then validate.
## Returns [OclNodeId] of the solid on success, or [] on failure.
## On failure any partially-created geometry is cleaned up from the graph.
static func _try_sweep_and_validate(graph: OclGraphHandle, profiles: Array[OclNodeId], spine: OclNodeId, spine_aux: OclNodeId, max_face_area: float = -1.0, validate: bool = true) -> Array[OclNodeId]:
	var sweep_ids := _try_sweep(graph, profiles, spine, spine_aux)
	if sweep_ids.is_empty():
		return []
	# check_volume=true: pipe_shell produces a closed solid whose volume must be > 0.
	if not validate or _validate_solid_geometry(graph, sweep_ids[0], max_face_area, true):
		return sweep_ids
	for s in sweep_ids:
		if s.bits != 0:
			OclTopoBuild.topo_remove_subgraph(graph, s.bits)
	return []

# -----------------------------------------------------------------------------
# Junction boolean-cut helpers
# -----------------------------------------------------------------------------

## Build inner-profile cutter solids from a section of |other_curve|.
##
## Sweeps the inner (hollow) profile along the other path's spine+aux wires
## for the given segment range.  Attempts sweep first, then pairwise loft.
## Returns [Array[OclNodeId] of pair solids, edge_bits, wire_bits,
## profile_bits, result_graph] where the first four are temporary topology to
## clean up after the boolean cuts, and result_graph is the graph that contains
## the cutter solids (same as input — no cloning).
## On total failure, cleans up all its geometry and returns empty solids.
## No fuse is performed — the caller cuts with each solid individually.
static func _build_inner_cutter_sweep(
	graph: OclGraphHandle,
	other_curve: Curve3D,
	other_aux_curve: Curve3D,
	profile_cfg: ProfileBuilder.Config,
	fancy: bool,
	segment_start: int,
	segment_end: int,  # exclusive
	cutter_sweep_mode: int = 0,
) -> Array:
	var profile_bits: Dictionary = {}  # { bits: true }

	# Build inner profile at all points in the section.
	# segment_end is exclusive (last segment = segment_end - 1),
	# so the last point index = segment_end.
	var profiles: Array[OclNodeId] = []
	for segment_i in range(segment_start, segment_end + 1):
		var xf := CurveUtils.transform_at_index(other_curve, segment_i, other_aux_curve)
		# Use wall_height = 1.0 so the inner cutter matches the full tunnel height
		# including the roof layer, producing a flush opening at roofed junctions.
		var p := ProfileBuilder.build_profiles(graph, profile_cfg, xf, fancy, true, 1.0)[0] # Only one inner wire!
		profiles.append(p)
		profile_bits[p.bits] = true

	# Build sub-spine/aux for this segment pair.
	var pair_spine_edges: Array[PackedInt64Array] = [PackedInt64Array()]
	var pair_spine_wire := _build_multi_wire(graph, other_curve, Chunk.new(segment_start, segment_end), pair_spine_edges)
	var pair_aux_edges: Array[PackedInt64Array] = [PackedInt64Array()]
	var pair_aux_wire := _build_multi_wire(graph, other_aux_curve, Chunk.new(segment_start, segment_end), pair_aux_edges)
	var max_area := _compute_max_face_area(profile_cfg, other_curve, other_aux_curve, segment_start, segment_end)

	# Try sweep first, then pairwise loft — both in the same graph.
	var pair_solids: Array[OclNodeId] = []
	if cutter_sweep_mode == 0:
		pair_solids = _try_sweep_and_validate(graph, profiles, pair_spine_wire, pair_aux_wire, max_area)
	# Loft is always available as a fallback when sweep fails or is skipped.
	if pair_solids.is_empty():
		pair_solids = _try_pairwise_loft(graph, profiles, Callable(), max_area)

	if pair_solids.is_empty():
		# Total failure — clean up all geometry we built.
		for bits in pair_spine_edges[0]:
			if bits != 0:
				OclTopoBuild.topo_remove_subgraph(graph, bits)
		for bits in pair_aux_edges[0]:
			if bits != 0:
				OclTopoBuild.topo_remove_subgraph(graph, bits)
		if pair_spine_wire.bits != 0:
			OclTopoBuild.topo_remove_subgraph(graph, pair_spine_wire.bits)
		if pair_aux_wire.bits != 0:
			OclTopoBuild.topo_remove_subgraph(graph, pair_aux_wire.bits)
		for bits in profile_bits:
			if bits != 0:
				OclTopoBuild.topo_remove_subgraph(graph, bits)
		return [[], PackedInt64Array(), PackedInt64Array(), {}, graph]

	var all_edge_bits := PackedInt64Array()
	all_edge_bits.append_array(pair_spine_edges[0])
	all_edge_bits.append_array(pair_aux_edges[0])
	var all_wire_bits := PackedInt64Array()
	all_wire_bits.append(pair_spine_wire.bits)
	all_wire_bits.append(pair_aux_wire.bits)

	return [pair_solids, all_edge_bits, all_wire_bits, profile_bits, graph]


## Apply boolean cuts at shortcut junction points.
##
## For each junction, builds an inner-profile cutter solid from the other path's
## curve and boolean-cuts it from the main sweep solid.
##
## Always tries both fancy and non-fancy cutter profiles per junction (each on
## a fresh clone) because the cutter is built along the OTHER path's curve and
## we don't know what fancy level that path used.  The first successful cut wins.
##
## Returns the (possibly swapped) graph handle.
static func _apply_junction_cuts(
	graph: OclGraphHandle,
	profile_cfg: ProfileBuilder.Config,
	fancy: bool,
	chunk_junctions: Array,
	debug_fuse: bool = false,
	cutter_sweep_mode: int = 0,
) -> void:
	if chunk_junctions.is_empty():
		return

	# Find the main sweep solid (should be the only solid after the outer sweep).
	var sweep_solids: Array[OclNodeId] = []
	sweep_solids.assign(GraphUtils._collect_ids(graph, OclCore.KIND_SOLID).map(func(i: int):
		var r := OclNodeId.new()
		r.bits = i
		return r))

	for junc in chunk_junctions:
		var other_curve: Curve3D = junc["other_curve"]
		var other_aux_curve: Curve3D = junc["other_aux_curve"]
		var seg_start: int = junc["other_segment_start"]
		var seg_end: int = junc["other_segment_end"]

		var pre_junction_solids := sweep_solids.duplicate()

		# Retry ladder per junction:
		#   0 — fancy cutter
		#   1 — non-fancy cutter
		#   2 — compact graph, then non-fancy cutter (OCCT boolean robustness workaround)
		# graph_compact rebuilds internal BRep structures and often resolves sporadic
		# parity/orientation errors that occur even when the geometry is correct.
		for attempt in range(3):
			var attempt_fancy := fancy and attempt == 0
			var do_compact := attempt == 2

			if do_compact:
				OclTopoBuild.graph_compact(graph)

			# Build cutter solids in the same graph (one per pair of adjacent profiles).
			var cutter_data := _build_inner_cutter_sweep(
				graph, other_curve, other_aux_curve, profile_cfg, attempt_fancy, seg_start, seg_end, cutter_sweep_mode,
			)
			var cutter_solids: Array = cutter_data[0]
			var edge_bits: PackedInt64Array = cutter_data[1]
			var wire_bits: PackedInt64Array = cutter_data[2]

			# Cut (or fuse for debugging) with each pair-solid individually.
			var old_solids: Array[OclNodeId] = []
			var result_solids: Array[OclNodeId] = []
			var boolean_failed := false
			for cutter_id in cutter_solids:
				var result: Array[OclNodeId] = [OclNodeId.new()]
				var status: OclCore.status
				if debug_fuse:
					status = OclBool.fuse(
						graph,
						PackedInt64Array(sweep_solids.map(func(n: OclNodeId): return n.bits)),
						PackedInt64Array([cutter_id.bits]),
						OclBoolOptions.new(),
						result[0],
					) as OclCore.status
					if status != OclCore.OK:
						push_warning("junction fuse failed (attempt %d): %s - %s" % [attempt, OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
						boolean_failed = true
						break
				else:
					# Skip the boolean if the cutter doesn't actually touch the sweep solid.
					var do_cut := false
					for sweep_solid in sweep_solids:
						var dist := OclDouble.new()
						status = OclTopoBuild.graph_pair_distance_get(graph, sweep_solid.bits, cutter_id.bits, dist) as OclCore.status
						if status != OclCore.OK:
							push_warning("junction graph_pair_distance_get failed (ignoring): %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
						elif dist.value == 0.0:
							do_cut = true
							break
					if not do_cut:
						result = sweep_solids
					else:
						status = OclBool.cut(
							graph,
							PackedInt64Array(sweep_solids.map(func(n: OclNodeId): return n.bits)),
							PackedInt64Array([cutter_id.bits]),
							OclBoolOptions.new(),
							result[0],
						) as OclCore.status
						if status != OclCore.OK:
							push_warning("junction cut failed (attempt %d): %s - %s" % [attempt, OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
							boolean_failed = true
							break
						old_solids.append_array(sweep_solids)
						result_solids.append_array(result)
					sweep_solids = result

			# Remove cutter solids (only when cutting — keep visible for fuse debug).
			if not debug_fuse:
				for cutter_id in cutter_solids:
					if cutter_id.bits != 0:
						var rm_status := OclTopoBuild.topo_remove_subgraph(graph, cutter_id.bits) as OclCore.status
						assert(rm_status == OclCore.OK, "ChunkBuilder: failed to remove cutter solid: %s" % [OclCore.status_to_string(rm_status)])

			if boolean_failed:
				# Roll back any partial cuts this attempt made.
				for sol in result_solids:
					if sol.bits != 0:
						OclTopoBuild.topo_remove_subgraph(graph, sol.bits)
				var pre_bits := {}
				for p in pre_junction_solids:
					pre_bits[p.bits] = true
				for old_id in old_solids:
					if old_id.bits != 0 and not pre_bits.has(old_id.bits):
						OclTopoBuild.topo_remove_subgraph(graph, old_id.bits)
				sweep_solids = pre_junction_solids.duplicate()
				# Clean up temporary edges/wires before the next attempt.
				for bits in edge_bits:
					var rm_status := OclTopoBuild.topo_remove_subgraph(graph, bits) as OclCore.status
					assert(rm_status == OclCore.OK, "ChunkBuilder: failed to remove cutter edge: %s" % [OclCore.status_to_string(rm_status)])
				for bits in wire_bits:
					var rm_status := OclTopoBuild.topo_remove_subgraph(graph, bits) as OclCore.status
					assert(rm_status == OclCore.OK, "ChunkBuilder: failed to remove cutter wire: %s" % [OclCore.status_to_string(rm_status)])
				GraphUtils.delete_orphans(graph, [OclCore.KIND_SHELL], [OclCore.KIND_EDGE, OclCore.KIND_WIRE])
				if attempt < 2:
					push_warning("Junction boolean failed on attempt %d — retrying" % attempt)
					continue
				push_warning("Junction boolean failed on all attempts — skipping junction cut")
			else:
				# Success — remove the now-replaced original sweep solid(s).
				for old_id in old_solids:
					var rm_status := OclTopoBuild.topo_remove_subgraph(graph, old_id.bits) as OclCore.status
					assert(rm_status == OclCore.OK, "ChunkBuilder: failed to remove old solid: %s" % [OclCore.status_to_string(rm_status)])
				# Clean up temporary edges/wires.
				for bits in edge_bits:
					var rm_status := OclTopoBuild.topo_remove_subgraph(graph, bits) as OclCore.status
					assert(rm_status == OclCore.OK, "ChunkBuilder: failed to remove cutter edge: %s" % [OclCore.status_to_string(rm_status)])
				for bits in wire_bits:
					var rm_status := OclTopoBuild.topo_remove_subgraph(graph, bits) as OclCore.status
					assert(rm_status == OclCore.OK, "ChunkBuilder: failed to remove cutter wire: %s" % [OclCore.status_to_string(rm_status)])
			break

		GraphUtils.delete_orphans(graph, [OclCore.KIND_SHELL], [OclCore.KIND_EDGE, OclCore.KIND_WIRE])


# -----------------------------------------------------------------------------
# Obstacle generation
# -----------------------------------------------------------------------------

## Discover all available obstacle build scripts at runtime.
static func _discover_obstacle_scripts() -> Array[Script]:
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
	# Fallback: ObstacleIndex (exported builds).
	var entries := ObstacleIndex.get_all()
	for e in entries:
		scripts.append(e["script"])
	return scripts


## Surface type for obstacle placement (planar against floor or walls only).
enum Surface { FLOOR, LEFT_WALL, RIGHT_WALL }


## Generate independent positive obstacles along a chunk.
## Obstacles are planar against floor or walls with 1-DOF orientation
## (rotation in the surface plane) and 3-DOF positioning (AABB stays inside
## the corridor, center path always clear for the ball to pass through).
static func _generate_obstacles(
	graph: OclGraphHandle,
	path_curve: Curve3D,
	aux_curve: Curve3D,
	chunk: Chunk,
	profile_cfg: ProfileBuilder.Config,
	pos_freq: float,
	_seed: int,
	segment_wall_heights: PackedFloat32Array = PackedFloat32Array(),
	debug_mode: bool = false,
	debug_max_rotation: float = 1.0,
	debug_max_offset: Vector2 = Vector2(1.0, 1.0),
	debug_min_offset: Vector2 = Vector2(0.0, 0.0),
) -> void:
	var seg_count := chunk.end_segment - chunk.start_segment
	if seg_count <= 0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = _seed

	var br: float = profile_cfg.ball_radius
	var bd: float = 2.0 * br
	var ratio := profile_cfg.ball_to_path_min_ratio
	# Inner rectangle of the sweep cross-section (path frame):
	#   X (lateral/binormal): [-inner_hw, +inner_hw]
	#   Y (up):               [-br, -br + inner_h]  (floor to wall top)
	# Size: bd / ratio on both axes.
	var inner_hw: float = bd / ratio.x * 0.5  # = br / ratio.x  (half-width)
	var inner_h: float = bd / ratio.y          # full wall height
	# Per-segment clamped wall height (may be less than inner_h).
	if pos_freq <= 0.0:
		return

	var obstacle_scripts := _discover_obstacle_scripts()
	if obstacle_scripts.is_empty():
		return

	var num_obstacles := maxi(1, int(seg_count * pos_freq))
	var status: OclCore.status

	# --- Safe maximums derived from inner rectangle ---
	# Clearance: max protrusion so the ball can still pass on the other side.
	var clearance: float = inner_hw - br
	# Floor obstacle height: ball rolls over if h < br; use 40% for gameplay.
	var max_floor_h: float = br * 0.4
	# Wall protrusion: limited by clearance.
	var max_wall_d: float = clearance

	for obs_i in range(num_obstacles):
		var t := (obs_i + 0.5) / num_obstacles
		var seg_idx := chunk.start_segment + int(t * seg_count)
		seg_idx = clampi(seg_idx, chunk.start_segment, mini(chunk.end_segment - 1, path_curve.point_count - 2))
		var xf := CurveUtils.transform_at_index(path_curve, seg_idx, aux_curve)

		var seg_off := seg_idx - chunk.start_segment
		var wall_h: float = clampf(segment_wall_heights[seg_off], 0.0, 1.0)
		var wh_clamped: float = minf(wall_h, 1.0) * inner_h

		# Choose surface: FLOOR, LEFT_WALL, or RIGHT_WALL.
		var surface: int = [Surface.FLOOR, Surface.LEFT_WALL, Surface.RIGHT_WALL][rng.randi() % 3]

		# Compute placement: flush against the inner rectangle surface.
		# Path frame: X=-binormal (lateral), Y=up, Z=-forward (along path).
		# All obstacles rotate around Y (up) for 1-DOF orientation.
		var local_pos := Vector3.ZERO
		var aabb_size := Vector3.ZERO

		# All surfaces share rotation around Y.
		var local_normal := Vector3(0, 1, 0)

		# Compute rotation angle first (shared across surfaces).
		# All obstacles rotate around Y (up) for 1-DOF orientation.
		var angle: float = rng.randf() * TAU * debug_max_rotation
		var cos_a: float = cos(angle)
		var sin_a: float = sin(angle)

		match surface:
			Surface.FLOOR:
				# Inner floor surface is at Y = -br in path frame.
				# OCCT box is corner-aligned: corner at obs_xf.origin, extends +size.
				# Negative: same box rotated 180° around floor → extends downward.
				var h: float = rng.randf_range(0.2, 0.5) * max_floor_h
				var sx: float = rng.randf_range(0.3, 0.8) * br
				var sz: float = rng.randf_range(0.3, 0.8) * br
				aabb_size = Vector3(sx, h, sz)
				# Compute lateral (X) extent after rotation around Y.
				var lateral_x: float = sx * abs(cos_a) + sz * abs(sin_a)
				# Compute min_ox: offset from corner to the leftmost X point after rotation.
				var min_ox: float = minf(0.0, minf(sx * cos_a, minf(sz * sin_a, sx * cos_a + sz * sin_a)))
				# Desired center of the box's world-X range: cx ∈ [-inner_hw + lateral_x/2, inner_hw - lateral_x/2].
				var cx_max: float = inner_hw - lateral_x * 0.5
				var x_frac: float = clampf(rng.randf_range(debug_min_offset.x, debug_max_offset.x), 0.0, 1.0)
				var cx: float = x_frac * cx_max * (1.0 if rng.randi() % 2 == 0 else -1.0)
				# Same lateral placement for both. Flip around floor surface (Y=-br).
				# Positive: corner at Y=-br, extends upward → [Y=-br, Y=-br+h].
				# Negative: corner at Y=-br-h, extends upward → [Y=-br-h, Y=-br].
				var y_pos: float = -br
				local_pos = Vector3(cx - min_ox - lateral_x * 0.5, y_pos, 0.0)
			Surface.LEFT_WALL, Surface.RIGHT_WALL:
				# Wall surface: place box so its world-X range is centered on cx.
				# After rotation, box X-range is [cx - eff_x/2, cx + eff_x/2].
				# Negative: same box rotated 180° around wall surface → extends outward.
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
				# Compute min_ox with (possibly scaled) dimensions.
				var min_ox: float = minf(0.0, minf(protrusion * cos_a, minf(length * sin_a, protrusion * cos_a + length * sin_a)))
				# Flip around wall surface (X = ±inner_hw).
				# Positive cx: midpoint between wall and ball → extends inward.
				# Negative cx: mirror of positive around wall surface → extends outward.
				var cx: float
				if surface == Surface.LEFT_WALL:
					cx = -(inner_hw + br) * 0.5
				else:
					cx = (inner_hw + br) * 0.5
				# Random height within wall, floor at Y=-br, top at Y=-br+wh_clamped.
				var y_range: float = wh_clamped - h
				var y_frac: float = clampf(rng.randf_range(debug_min_offset.y, debug_max_offset.y), 0.0, 1.0) if y_range > 0 else 0.5
				var y_pos: float = -br + y_frac * y_range
				# Place corner so box X-range is centered on cx.
				local_pos = Vector3(cx - min_ox - eff_x * 0.5, y_pos, 0.0)

		# Build rotation basis from the angle computed above.
		var rot_basis := Basis(local_normal.normalized(), angle)

		# Build the obstacle local transform.
		var obs_xf := xf.translated_local(local_pos)
		obs_xf.basis = xf.basis * rot_basis

		# Build the obstacle AABB (corner-aligned to match OCCT box convention).
		var obs_aabb := AABB(Vector3.ZERO, aabb_size)

		# Build the obstacle solid directly into the main graph.
		var obs_bits: PackedInt64Array
		if debug_mode:
			var box_info := OclPrimBoxInfo.new()
			box_info.placement = OcctConversionUtils.transform3d_to_occt_placement(obs_xf)
			box_info.dx = aabb_size.x
			box_info.dy = aabb_size.y
			box_info.dz = aabb_size.z
			var box_id := OclNodeId.new()
			status = OclPrimSolid.box(graph, box_info, box_id) as OclCore.status
			if status != OclCore.OK:
				push_warning("obstacle debug box failed: %s" % OclCore.status_to_string(status))
				continue
			obs_bits = PackedInt64Array([box_id.get_bits()])
		else:
			obs_bits = obstacle_scripts[rng.randi() % obstacle_scripts.size()].build(graph, obs_aabb, obs_xf)

		if obs_bits.is_empty():
			continue

		# Positive obstacles are left as independent solids.
		pass

	GraphUtils.delete_orphans(graph, [OclCore.KIND_SHELL], [OclCore.KIND_EDGE, OclCore.KIND_WIRE])


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

		# Ensure non-degenerate Bezier tangent at both endpoints.  When a
		# handle length is zero (c0 ≈ p0 or c1 ≈ p1) the cubic Bezier has a
		# zero tangent at that endpoint.  OCCT's pipe_shell normalises the
		# spine tangent via gp_Vec::Normalize() which throws on zero-norm
		# vectors.  Nudge the control point along the chord direction so
		# the tangent stays non-zero without altering visible geometry.
		var chord := p1 - p0
		var chord_len := chord.length()
		if chord_len > 1e-12:
			var min_handle := chord_len * 0.01
			if c0.distance_to(p0) < min_handle:
				c0 = p0 + (chord / chord_len) * min_handle
			if c1.distance_to(p1) < min_handle:
				c1 = p1 - (chord / chord_len) * min_handle

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
		out_edges[0].append_array(edge_bits)

	return TopoBuilders.make_wire(graph, edges)
