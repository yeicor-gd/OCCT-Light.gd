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
	chunk_junctions_to_clean: Array,
	segment_wall_heights: PackedFloat32Array = PackedFloat32Array(),
	pobstacle_frequency: float = 0.0,
	pobstacle_positive: bool = true,
	pobstacle_negative: bool = true,
	pobstacle_seed: int = 0,
) -> Array[OclGraphHandle]:
	var graphs: Array[OclGraphHandle] = []
	var status: OclCore.status
	
	if do_main_path:
		var graph := GraphUtils.create_graph()

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
		
		if Engine.is_editor_hint() and graph != null:
			GraphUtils.check_graph(graph)

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
						"sub_spine_wire": _build_multi_wire(graph, path_curve, Chunk.new(run_start, last_good), spine_edges),
						"sub_aux_wire": _build_multi_wire(graph, aux_curve, Chunk.new(run_start, last_good), aux_edges),
					})

				if finalize:
					run_start = -1
			
			# Actually sub-sweep for each split
			for split in splits_profiles:
				var sweep_result := sweep_with_fallback_to_loft(graph, split["profiles"], split["sub_spine_wire"], split["sub_aux_wire"])
				if sweep_result.is_empty():
					return [] # Assertion failed and error already pushed
		
		GraphUtils.delete_orphans(graph, [OclCore.KIND_SHELL], [OclCore.KIND_EDGE, OclCore.KIND_WIRE])

		# Clean up temporary sketches.
		for bits in spine_edges[0]:
			status = OclTopoBuild.topo_remove_subgraph(graph, bits) as OclCore.status
			assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
		for bits in aux_edges[0]:
			status = OclTopoBuild.topo_remove_subgraph(graph, bits) as OclCore.status
			assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
		
		if Engine.is_editor_hint() and graph != null:
			GraphUtils.check_graph(graph)
		
		# --- Generate obstacles after sweep ---
		if pobstacle_frequency > 0.0 and (pobstacle_positive or pobstacle_negative):
			_generate_obstacles(graph, path_curve, aux_curve, chunk, profile_cfg, pobstacle_frequency, pobstacle_positive, pobstacle_negative, pobstacle_seed, segment_wall_heights)

		# --- Clean shortcuts: build inner sweep and boolean-cut at junctions ---
		if not chunk_junctions_to_clean.is_empty():
			_apply_junction_cuts(graph, profile_cfg, fancy, chunk_junctions_to_clean, debug_fuse_junctions)

		graphs.append(graph)

	# Add caps as separate standalone graphs (no fuse/clone needed).
	if add_start_cap:
		var start_xf2 := CurveUtils.transform_at_index(path_curve, chunk.start_segment, aux_curve)
		var start_wh: float = -1.0
		if segment_wall_heights.size() > 0:
			start_wh = segment_wall_heights[0]
		var cap_graph := _build_cap_graph(profile_cfg, start_xf2, true, fancy, start_wh)
		if cap_graph != null:
			if not chunk_junctions_to_clean.is_empty():
				_apply_junction_cuts(cap_graph, profile_cfg, fancy, chunk_junctions_to_clean, debug_fuse_junctions)
			graphs.append(cap_graph)

	if add_end_cap:
		var end_xf := CurveUtils.transform_at_index(path_curve, chunk.end_segment, aux_curve)
		var end_wh: float = -1.0
		if segment_wall_heights.size() > 1:
			end_wh = segment_wall_heights[segment_wall_heights.size() - 1]
		var cap_graph := _build_cap_graph(profile_cfg, end_xf, false, fancy, end_wh)
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


static func sweep_with_fallback_to_loft(graph: OclGraphHandle, profiles: Array[OclNodeId], spine: OclNodeId, spine_aux: OclNodeId) -> Array[OclNodeId]:
	var status := OclCore.NOT_DONE
	var sweep_ids: Array[OclNodeId] = []
	if true: # Always try sweep first.
		var sweep_info := OclPrimPipeShellInfo.new()
		sweep_info.profiles = PackedInt64Array(profiles.map(func(p: OclNodeId): return p.bits))
		sweep_info.mode = OclPrimSweep.PIPE_MODE_AUXILIARY_SPINE
		sweep_info.spine_wire = spine.bits
		sweep_info.auxiliary_spine_wire = spine_aux.bits
		sweep_info.transition = OclPrimSweep.PIPE_TRANSITION_RIGHT_CORNER
		# sweep_info.auxiliary_curvilinear_equivalence = 1  # Very slow, same results?
		#sweep_info.with_contact = 1
		#sweep_info.auxiliary_contact = OclPrimSweep.PIPE_AUX_CONTACT_NONE
		sweep_info.make_solid = 1
		var sweep_id := OclNodeId.new()
		status = OclPrimSweep.pipe_shell(graph, sweep_info, sweep_id) as OclCore.status
		sweep_ids.append(sweep_id)
	if status != OclCore.OK:
		push_warning("Sweep failed (Got status %s - %s), falling back to a ruled loft" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
		var solids: Array[OclNodeId] = []
		for i in range(profiles.size() - 1):
			# Loft should be better but edge matching cannot be controlled and often results in crazy surfaces that do not do proper cuts.
			var info := OclPrimLoftInfo.new()
			info.is_solid = 1
			info.ruled = 1
			info.sections = PackedInt64Array([profiles[i].bits, profiles[i + 1].bits])
			var solid := OclNodeId.new()
			status = OclPrimSweep.loft(graph, info, solid) as OclCore.status
			assert(status == OclCore.OK, "loft failed: %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
			
			# This is a hack that performs a two-way prism and takes the common part as the fake lofted solid (better when from and to are closest)
			#var from_props := OclGraphMassProperties.new()
			#status = OclTopoBuild.graph_mass_properties_get(graph, profiles[i].bits, from_props) as OclCore.status
			#assert(status == OclCore.OK, "%s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
			#var from := OcctConversionUtils.p3_to_v3(from_props.centre_of_mass)
			#var to_props := OclGraphMassProperties.new()
			#status = OclTopoBuild.graph_mass_properties_get(graph, profiles[i+1].bits, to_props) as OclCore.status
			#assert(status == OclCore.OK, "%s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
			#var to := OcctConversionUtils.p3_to_v3(to_props.centre_of_mass)
			#var info1 := OclPrimPrismInfo.new()
			#info1.direction = OcctConversionUtils.v3_to_ov3(to - from)
			#info1.profile = profiles[i].bits
			#var solid1 := OclNodeId.new()
			#status = OclPrimSweep.prism(graph, info1, solid1) as OclCore.status
			#assert(status == OclCore.OK, "%s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
			#var info2 := OclPrimPrismInfo.new()
			#info2.direction = OcctConversionUtils.v3_to_ov3(from - to)
			#info2.profile = profiles[i+1].bits
			#var solid2 := OclNodeId.new()
			#status = OclPrimSweep.prism(graph, info2, solid2) as OclCore.status
			#assert(status == OclCore.OK, "%s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
			#var info := OclBoolOptions.new()
			#var solid := OclNodeId.new()
			#status = OclBool.common(graph, PackedInt64Array([solid1.bits]), PackedInt64Array([solid2.bits]), info, solid) as OclCore.status
			#assert(status == OclCore.OK, "%s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
			
			sweep_ids.append(solid)
	return sweep_ids

# -----------------------------------------------------------------------------
# Junction boolean-cut helpers
# -----------------------------------------------------------------------------

## Build inner-profile cutter solids from a section of |other_curve|.
##
## Sweeps the inner (hollow) profile along the other path's spine+aux wires
## for the given segment range.  Each pair of adjacent profiles produces one
## solid.  Returns [Array[OclNodeId] of pair solids, edge_bits, wire_bits]
## where the latter two are temporary topology to remove after the boolean cuts.
## No fuse is performed — the caller cuts with each solid individually.
static func _build_inner_cutter_sweep(
	graph: OclGraphHandle,
	other_curve: Curve3D,
	other_aux_curve: Curve3D,
	profile_cfg: ProfileBuilder.Config,
	fancy: bool,
	segment_start: int,
	segment_end: int,  # exclusive
) -> Array:
	# Build inner profile at all points in the section.
	# segment_end is exclusive (last segment = segment_end - 1),
	# so the last point index = segment_end.
	var profiles: Array[OclNodeId] = []
	for segment_i in range(segment_start, segment_end + 1):
		var xf := CurveUtils.transform_at_index(other_curve, segment_i, other_aux_curve)
		profiles.append(ProfileBuilder.build_profiles(graph, profile_cfg, xf, fancy, true, 1.0)[0]) # Only one inner wire!

	# Sweep inner profile along the wires.
	# Going in pairs avoids matching the wrong wire edges between the first and last profiles,
	# as edges change slowly across the sweep but can accumulate a lot of changes across edges of sweep.
	# Each pair produces one solid; we return them individually so the caller
	# can cut with each one separately (avoids fuse instability).
	# IMPORTANT: each pair gets its own sub-spine covering only its 1 segment
	# (2 points), because pipe_shell places the 2 profiles at the start/end
	# of the given spine.
	var all_edge_bits := PackedInt64Array()
	var all_wire_bits := PackedInt64Array()
	var cutter_solids: Array[OclNodeId] = []
	var pair_seg_start := segment_start
	var pair_seg_end := segment_end  # exclusive, covers exactly 1 segment (2 points)
	var pair_spine_edges: Array[PackedInt64Array] = [PackedInt64Array()]
	var pair_spine_wire := _build_multi_wire(graph, other_curve, Chunk.new(pair_seg_start, pair_seg_end), pair_spine_edges)
	var pair_aux_edges: Array[PackedInt64Array] = [PackedInt64Array()]
	var pair_aux_wire := _build_multi_wire(graph, other_aux_curve, Chunk.new(pair_seg_start, pair_seg_end), pair_aux_edges)
	var pair_solids := sweep_with_fallback_to_loft(graph, profiles, pair_spine_wire, pair_aux_wire)
	if pair_solids.is_empty():
		return [[], PackedInt64Array(), PackedInt64Array()] # Assertion failed and error already pushed
	cutter_solids.append_array(pair_solids)
	all_edge_bits.append_array(pair_spine_edges[0])
	all_edge_bits.append_array(pair_aux_edges[0])
	all_wire_bits.append(pair_spine_wire.bits)
	all_wire_bits.append(pair_aux_wire.bits)

	return [cutter_solids, all_edge_bits, all_wire_bits]


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

		# Build cutter solids in the same graph (one per pair of adjacent profiles).
		var cutter_data := _build_inner_cutter_sweep(
			graph, other_curve, other_aux_curve, profile_cfg, fancy, seg_start, seg_end,
		)
		var cutter_solids: Array = cutter_data[0]
		var edge_bits: PackedInt64Array = cutter_data[1]
		var wire_bits: PackedInt64Array = cutter_data[2]
		
		var actually_cut := true

		# Cut (or fuse for debugging) with each pair-solid individually.
		# All cutter solid cleanup happens after the loop so that removing
		# one pair's topology does not corrupt subsequent pairs.
		var old_solids: Array[OclNodeId] = []
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
				assert(status == OclCore.OK, "junction fuse failed: %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
			else:
				# Check first if they intersect
				var do_cut := false
				for sweep_solid in sweep_solids:
					var dist := OclDouble.new()
					status = OclTopoBuild.graph_pair_distance_get(graph, sweep_solid.bits, cutter_id.bits, dist)as OclCore.status
					if status != OclCore.OK:
						push_warning("junction graph_pair_distance_get failed (ignoring): %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
					elif dist.value == 0.0:
						do_cut = true
						break
				if not do_cut:
					actually_cut = false
					result = sweep_solids
				else:
					actually_cut = true
					status = OclBool.cut(
						graph,
						PackedInt64Array(sweep_solids.map(func(n: OclNodeId): return n.bits)),
						PackedInt64Array([cutter_id.bits]),
						OclBoolOptions.new(),
						result[0],
					) as OclCore.status
					if status != OclCore.OK: # Continue anyway to clean things up:
						push_warning("junction cut failed: %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])

			# The cut may completely miss the original object causing no changes.
			# When the cutter misses, AddWithHistory returns the same root node ID,
			# so we can detect no-op cuts by comparing node IDs directly.
			if actually_cut:
				old_solids.append_array(sweep_solids)
			sweep_solids = result

		# Remove cutter solids (only when cutting — keep visible for fuse debug).
		if not debug_fuse:
			for cutter_id in cutter_solids:
				if cutter_id.bits != 0:
					var rm_status := OclTopoBuild.topo_remove_subgraph(graph, cutter_id.bits) as OclCore.status
					assert(rm_status == OclCore.OK, "ChunkBuilder: failed to remove cutter solid: %s" % [OclCore.status_to_string(rm_status)])

		# Remove the now-orphaned original sweep solid(s)
		for old_id in old_solids:
			var rm_status := OclTopoBuild.topo_remove_subgraph(graph, old_id.bits) as OclCore.status
			assert(rm_status == OclCore.OK, "ChunkBuilder: failed to remove old solid: %s" % [OclCore.status_to_string(rm_status)])

		# Remove temporary wires and edges from the cutter build.
		for bits in edge_bits:
			var rm_status := OclTopoBuild.topo_remove_subgraph(graph, bits) as OclCore.status
			assert(rm_status == OclCore.OK, "ChunkBuilder: failed to remove cutter edge: %s" % [OclCore.status_to_string(rm_status)])
		for bits in wire_bits:
			var rm_status := OclTopoBuild.topo_remove_subgraph(graph, bits) as OclCore.status
			assert(rm_status == OclCore.OK, "ChunkBuilder: failed to remove cutter wire: %s" % [OclCore.status_to_string(rm_status)])

		GraphUtils.delete_orphans(graph, [OclCore.KIND_SHELL], [OclCore.KIND_EDGE, OclCore.KIND_WIRE])


# -----------------------------------------------------------------------------
# Obstacle generation
# -----------------------------------------------------------------------------

## Generate positive (fused) and negative (cut) obstacles along a chunk.
## Obstacles are placed at regular intervals along the path, offset to one
## side. Positive obstacles narrow the path; negative obstacles widen it.
static func _generate_obstacles(
	graph: OclGraphHandle,
	path_curve: Curve3D,
	aux_curve: Curve3D,
	chunk: Chunk,
	profile_cfg: ProfileBuilder.Config,
	frequency: float,
	do_positive: bool,
	do_negative: bool,
	seed_offset: int,
	segment_wall_heights: PackedFloat32Array = PackedFloat32Array(),
) -> void:
	var seg_count := chunk.end_segment - chunk.start_segment
	if seg_count <= 0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_offset

	var br := profile_cfg.ball_radius
	var pwh := br / profile_cfg.ball_to_path_min_ratio.x
	var obstacle_size := br * 0.6

	# Collect all existing sweep solids for fuse/cut operations.
	var sweep_solids: Array[OclNodeId] = []
	sweep_solids.assign(GraphUtils._collect_ids(graph, OclCore.KIND_SOLID).map(func(i: int):
		var r := OclNodeId.new()
		r.bits = i
		return r))

	var num_obstacles := maxi(1, int(seg_count * frequency))
	var status: OclCore.status

	for obs_i in range(num_obstacles):
		var t := (obs_i + 0.5) / num_obstacles
		var seg_idx := chunk.start_segment + int(t * seg_count)
		seg_idx = clampi(seg_idx, chunk.start_segment, mini(chunk.end_segment - 1, path_curve.point_count - 2))
		var xf := CurveUtils.transform_at_index(path_curve, seg_idx, aux_curve)

		var side := 1.0 if (obs_i % 2 == 0) else -1.0
		var offset := pwh * (0.3 + rng.randf() * 0.4) * side

		var seg_off := seg_idx - chunk.start_segment
		var wall_h := clampf(segment_wall_heights[seg_off], 0.0, 1.0)
		var wth := (2.0 * br) / profile_cfg.ball_to_path_min_ratio.y
		var obstacle_height := wall_h * wth * 0.5

		var box_xf := xf.translated_local(Vector3(offset, -br + obstacle_height, 0))

		var box_info := OclPrimBoxInfo.new()
		box_info.placement = OcctConversionUtils.transform3d_to_occt_placement(box_xf)
		box_info.dx = obstacle_size * 2.0
		box_info.dy = obstacle_size * 2.0
		box_info.dz = obstacle_size * 2.0

		var box_id := OclNodeId.new()
		status = OclPrimSolid.box(graph, box_info, box_id) as OclCore.status
		if status != OclCore.OK:
			push_warning("Obstacle box creation failed: %s" % OclCore.status_to_string(status))
			continue

		if sweep_solids.is_empty():
			OclTopoBuild.topo_remove_subgraph(graph, box_id.bits)
			continue

		var fuse_it := false
		if do_positive and do_negative:
			fuse_it = rng.randf() < 0.5
		elif do_positive:
			fuse_it = true

		var result_id := OclNodeId.new()
		if fuse_it:
			status = OclBool.fuse(
				graph,
				PackedInt64Array(sweep_solids.map(func(n: OclNodeId): return n.bits)),
				PackedInt64Array([box_id.bits]),
				OclBoolOptions.new(),
				result_id,
			) as OclCore.status
		else:
			status = OclBool.cut(
				graph,
				PackedInt64Array(sweep_solids.map(func(n: OclNodeId): return n.bits)),
				PackedInt64Array([box_id.bits]),
				OclBoolOptions.new(),
				result_id,
			) as OclCore.status

		if status == OclCore.OK:
			for old in sweep_solids:
				OclTopoBuild.topo_remove_subgraph(graph, old.bits)
			sweep_solids = [result_id]
		else:
			OclTopoBuild.topo_remove_subgraph(graph, box_id.bits)

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
