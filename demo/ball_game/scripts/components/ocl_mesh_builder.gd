@tool
extends Node3D
class_name OclMeshBuilder

## OCCT-based mesh builder for maze segments, parallelised via TaskScheduler.
##
## Reads path pairs (Path3D + auxiliary Path3D) from the MazePaths/Curves
## node, plans chunked segments via ChunkBuilder, then dispatches each chunk
## as a WorkerThreadPool background task.  Results arrive out of order and
## are assembled into a per-batch Node3D hierarchy on the main thread.
##
## Path pairs are always auto-discovered from the scene tree:
##   MainPath + MainPathBinormal  (primary pair)
##   Shortcut0 + Shortcut0Binormal, ... (additional pairs when sweep_shortcuts)
##
## Batching: consecutive chunks (by rope order) are grouped into spatial
## batches of size merge_batch_size.  A batch is flushed to the scene as
## soon as every one of its chunks has completed, so early batches appear
## progressively while later ones are still computing.  Each batch produces
## exactly one draw call per feature type (faces/edges/vertices), which
## amortises GPU overhead without sacrificing occlusion-culling granularity.
##
## Batch scene hierarchy (merge_batch_size > 1):
##   BatchN (Node3D)
##     Faces (StaticBody3D if physics, Node3D otherwise)
##       FacesMesh (MeshInstance3D)
##       CollisionFaces (CollisionShape3D, if physics)
##     Edges / Vertices — same pattern
##
## With merge_batch_size <= 1 each chunk keeps its own ChunkN node.
##
## Batch subtrees are persisted as .scn (binary) PackedScene files.
## Display and physics have independent OclMeshOptions and fancy flags.

# -----------------------------------------------------------------------------
# Sweep mode enum (sorted from most to least complex)
# -----------------------------------------------------------------------------

enum SweepMode {
	## Full sweep along spine with auxiliary orientation (pipe_shell).
	SWEEP = 0,
	## Ruled loft through pairs of adjacent sections (ThruSections, ruled=1).
	LOFT_RULED = 1,
}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

@export_group("Design")

## Thickness of the track walls.
@export_range(0.0, 1.0) var wall_thickness := 0.05
## Whether to actually build the inner path (for debugging).
@export var main_path := true
## Add rounded end caps at the start and end of the track.
@export var end_caps := true

@export_group("Wall Height Variation")

## Frequency of the smooth noise that varies wall height along the track.
## Lower values produce gradual changes; higher values produce rapid oscillation.
@export_range(0.0001, 1.0, 0.0001) var wall_height_noise_freq := 0.05

## CDF curve controlling wall height distribution along the track.
## Smooth noise is evaluated at each segment to provide spatial coherence,
## then remapped to [0, 1] and sampled on this curve to produce the final
## wall height.  X-axis = probability [0..1], Y-axis = wall height value.
## Values > 1.0 produce a roof that clamps to 1.0 and persists across
## contiguous segments.
@export var wall_height_cdf: Curve

@export_group("Shortcuts (slow)")

## Sweep all generated shortcut / longcut paths in addition to the main path.
@export var sweep_shortcuts: bool = true

## When true, build an inner hollow profile for each path and perform
## boolean cuts at shortcut junction points so the interior is connected.
@export var clean_shortcuts: bool = true

## Debug: fuse cutter solids instead of cutting so they remain visible.
@export var debug_fuse_junctions: bool = false

@export_group("Obstacles (slow)")

## Frequency of positive obstacles along the track (obstacles per segment unit).
@export_range(0.0, 0.5, 0.01) var obstacle_positive_frequency: float = 0.1
## Seed offset for obstacle randomisation.
@export var obstacle_seed_offset: int = 0
## Debug mode: always adds boxes instead of obstacle shapes, for visualising placement.
@export var obstacle_debug_mode: bool = false
## Debug: max rotation multiplier [0-1] applied to obstacle placement (0 = axis-aligned, 1 = full).
@export_range(0.0, 1.0, 0.01) var obstacle_debug_max_rotation: float = 1.0
## Debug: max offset multiplier [0-1] applied to obstacle placement.
@export var obstacle_debug_max_offset: Vector2 = Vector2(1.0, 1.0)
## Debug: min offset multiplier [0-1] applied to force minimum displacement.
@export var obstacle_debug_min_offset: Vector2 = Vector2(0.0, 0.0)

@export_group("Chunking")

## Number of segments to merge into one OCCT graph (1 is more stable and the most parallelizable but may have some synchronization and GPU overhead due to extra planar walls and more objects / draw calls).
@export_range(1, 200, 1) var chunk_size: int = 1

## Maximum number of chunk results to accumulate before flushing.
@export_range(0, 200, 1) var merge_batch_size: int = 16

## Maximum concurrent WorkerThreadPool tasks. 0 = unlimited.
@export_range(0, 32, 1) var max_concurrent: int = 0

@export_group("Display")

## Sweep algorithm for display face geometry. Falls back to simpler modes on failure.
@export var display_sweep_mode: SweepMode = SweepMode.SWEEP
## Sweep algorithm for display shortcut cutter geometry. Falls back to simpler modes on failure.
@export var display_shortcut_cutter_sweep_mode: SweepMode = SweepMode.SWEEP
## OCCT mesh tessellation options for DISPLAY (visual) geometry.
@export var display_options := OclMeshOptions.new()
## Apply 2D fillets to smooth profile corners (fancy mode) for display.
@export var display_fancy := true
## Show tessellated face surfaces.
@export var display_show_faces := true
## Display edges as cylinders (== 0 = disabled, <0 = fixed size).
@export var display_edge_radius: float = -0.01
## Display vertices as spheres (== 0 = disabled, <0 = fixed size).
@export var display_vertex_radius: float = -0.02
## Material for faces
@export var display_faces_material: Material
## Material for edges
@export var display_edges_material: Material
## Material for vertices
@export var display_vertices_material: Material

## Debug: tint each batch with a colour indicating which sweep attempt succeeded.
## sweep+fancy=green, sweep+nf=yellow, loft+fancy=orange, loft+nf=red.
## Overrides display_faces_material albedo modulate when enabled.
@export var debug_color_sweep_mode: bool = false

## Validate display sweep geometry (volume, face area, topology, self-intersection).
## Disabling skips all analytical checks — only hard OCCT failures cause fallback.
## Disable for fastest generation; enable for highest-quality geometry.
@export var display_validate_geometry: bool = true

@export_group("Physics")

## Sweep algorithm for physics face geometry. Falls back to simpler modes on failure.
@export var physics_sweep_mode: SweepMode = SweepMode.LOFT_RULED
## Sweep algorithm for physics shortcut cutter geometry. Falls back to simpler modes on failure.
@export var physics_shortcut_cutter_sweep_mode: SweepMode = SweepMode.LOFT_RULED
## OCCT mesh tessellation options for PHYSICS (collision) geometry.
@export var physics_options := OclMeshOptions.new()
## Apply 2D fillets to smooth profile corners (fancy mode) for physics.
@export var physics_fancy := false
## Validate physics sweep geometry (volume, face area, topology, self-intersection).
## Disabling skips all analytical checks — only hard OCCT failures cause fallback.
@export var physics_validate_geometry: bool = false

## Generate collision shapes for faces.
@export var physics_show_faces := true
## Generate collision shapes for edges (== 0 = disabled, <0 = fixed size).
@export var physics_edge_radius: float = 0.0
## Generate collision shapes for vertices (== 0 = disabled, <0 = fixed size).
@export var physics_vertex_radius: float = 0.0

@export_group("Persistence")

## Base path for saving generated resources. Empty = memory-only.
@export var resource_save_path := "res://demo/generated/maze_meshes"

@export_group("Actions")

@export_tool_button("Regenerate") var regenerate_ = func(): await regenerate(false)

# -----------------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------------

## Emitted once when regeneration begins.
## total_chunks: total number of chunks to be built across all pairs.
signal generation_started(total_chunks: int)

## Emitted each time one chunk worker finishes (from the main thread).
## chunk_idx: the chunk's sequential global index (rope order).
## pair_name: "" for main path, "ShortcutN_" for shortcuts.
## elapsed_ms: wall-clock time the worker spent on this chunk.
signal chunk_completed(chunk_idx: int, pair_name: String, elapsed_ms: float)

## Emitted when a spatial batch is assembled and added to the scene.
## batch_name: the node name of the batch (e.g. "Batch3").
## chunks_in_batch: how many chunks contributed to this batch.
signal batch_ready(batch_name: String, chunks_in_batch: int)

## Emitted when all chunks are done and the scene is fully built.
## total_ms: total wall-clock time since generation_started.
## total_chunks: total chunks processed.
## failed_chunks: chunks that returned empty geometry.
signal generation_finished(total_ms: float, total_chunks: int, failed_chunks: int)

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

var _maze_generator: MazeGenerator
var _profile_cfg: ProfileBuilder.Config
var _is_regenerating: bool = false
var _scheduler: TaskScheduler = null
var _wall_height_cdf: Curve
var _wall_height_noise: FastNoiseLite
# Per-batch accumulators: batch_id (int) -> { "pending": int, "name": String }
var _batches: Dictionary = {}
# Arriving results held until their batch is complete: batch_id -> Array[Dictionary]
var _pending_results: Dictionary = {}
# Progress counters (main thread only).
var _progress_total: int = 0
var _progress_done: int = 0
var _progress_failed: int = 0
var _progress_start_us: int = 0

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

func _ensure_config() -> void:
	_maze_generator = _find_generator()
	_profile_cfg = ProfileBuilder.Config.new(
		_maze_generator.ball_radius,
		_maze_generator.ball_to_path_min_ratio,
		wall_thickness,
	)
	_wall_height_cdf = _ensure_wall_height_cdf()
	_wall_height_noise = FastNoiseLite.new()
	_wall_height_noise.seed = _maze_generator.seed_value
	_wall_height_noise.frequency = wall_height_noise_freq
	_wall_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH


## Ensure the wall height CDF curve exists, creating a sensible default if not set.
func _ensure_wall_height_cdf() -> Curve:
	if wall_height_cdf == null:
		wall_height_cdf = Curve.new()
		wall_height_cdf.add_point(Vector2(0.0, 0.0))
		wall_height_cdf.add_point(Vector2(0.5, 0.8))
		wall_height_cdf.add_point(Vector2(1.0, 1.5))
	return wall_height_cdf


## Sample the wall height at a given parametric progress along the track.
## Uses smooth noise for spatial coherence, then maps through the CDF curve
## to control the height distribution.
func _sample_wall_height(noise_input: float) -> float:
	if not is_finite(noise_input):
		push_warning("OclMeshBuilder: non-finite noise input %.2f in _sample_wall_height, using default" % noise_input)
		return 0.8
	var n := _wall_height_noise.get_noise_1d(noise_input)
	if not is_finite(n):
		push_warning("OclMeshBuilder: FastNoiseLite returned NaN for input %.2f" % noise_input)
		return 0.8
	var t := clampf(n * 0.5 + 0.5, 0.0, 1.0) # Remap [-1,1] -> [0,1]
	var h := _wall_height_cdf.sample(t)
	if not is_finite(h):
		push_warning("OclMeshBuilder: CDF returned non-finite height for t=%.4f" % t)
		return 0.8
	return h

## Return the scene root for setting node owners.
##
## In the editor tree this is get_tree().edited_scene_root.
## During export the instantiated nodes are not in the tree, so we walk up
## to the topmost ancestor (the instantiated PackedScene root).
func _scene_root() -> Node:
	if is_inside_tree():
		return get_tree().edited_scene_root
	var n: Node = get_parent()
	while n and n.get_parent():
		n = n.get_parent()
	return n

# -----------------------------------------------------------------------------
# Path-pair discovery (always auto-detect from scene tree)
# -----------------------------------------------------------------------------

## Collect all path + auxiliary pairs to sweep.
##
## Path pairs are auto-discovered from the MazePaths node:
##   MainPath + MainPathBinormal  → primary pair
##   ShortcutN + ShortcutNBinormal → additional pairs (if sweep_shortcuts)
##
## Returns an array of dictionaries:
##   { "name": String, "path": Path3D, "aux": Path3D, "junctions": Array }
##
## When clean_shortcuts is true, both the main path and each shortcut carry
## bidirectional junction data for boolean-cutting walls at intersection points.
## Each shortcut produces TWO junction entries (one for start, one for end):
##   { "other_curve": Curve3D, "other_aux_curve": Curve3D,
##     "other_segment_start": int, "other_segment_end": int,
##     "junction_frac": float }
func _collect_path_pairs() -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []

	var gen := _find_generator()
	if not gen:
		return pairs

	var paths: Node3D = gen.get_node_or_null("Paths") as Node3D
	if not paths:
		return pairs

	# --- Primary (main) path pair ---
	var path: Path3D = paths.get_node_or_null("MainPath") as Path3D
	var aux_path: Path3D = paths.get_node_or_null("MainPathBinormal") as Path3D
	if path and aux_path:
		pairs.append({ "name": "", "path": path, "aux": aux_path, "junctions": [] })

	# --- Shortcut pairs ---
	if sweep_shortcuts:
		var main_curve: Curve3D = path.curve if path else null
		var main_baked_len: float = main_curve.get_baked_length() if main_curve else 0.0
		var main_aux_curve: Curve3D = aux_path.curve if aux_path else null

		for child in paths.get_children():
			if not child is Path3D:
				continue
			var cn := str(child.name)
			if cn.begins_with("Shortcut") and not cn.ends_with("Binormal"):
				var sc_aux: Path3D = paths.get_node_or_null(cn + "Binormal")
				if not sc_aux:
					continue

				var sc_curve: Curve3D = child.curve
				if sc_curve == null or sc_curve.point_count < 2:
					continue

				var sc_start := sc_curve.get_point_position(0)
				var sc_end := sc_curve.get_point_position(sc_curve.point_count - 1)

				var start_frac := _find_closest_fraction(main_curve, sc_start, main_baked_len)
				var end_frac := _find_closest_fraction(main_curve, sc_end, main_baked_len)

				# Compute segment indices on the main path for both anchor points.
				# Declared here so both junction blocks below can reference them.
				var start_seg := _fraction_to_segment(start_frac, main_curve.point_count)
				var end_seg := _fraction_to_segment(end_frac, main_curve.point_count)

				# --- Shortcut pair junction data (cut shortcut wall with main interior) ---
				var shortcut_junctions: Array = []
				if clean_shortcuts:
					var pathway_hw := _profile_cfg.ball_radius / _profile_cfg.ball_to_path_min_ratio.x + _profile_cfg.wall_thickness
					var sc_num_segs := sc_curve.point_count - 1
					# Start junction: main path cutter centered on start_frac
					var start_section := _compute_cutter_section(main_curve, start_seg, pathway_hw)
					shortcut_junctions.append({
						"other_curve": main_curve,
						"other_aux_curve": main_aux_curve,
						"other_name": "",
						"other_segment_start": start_section[0],
						"other_segment_end": start_section[1],
						"junction_frac": 0.0,           # fraction along THIS (shortcut) path
						"junction_segment": 0,           # segment index along THIS (shortcut) path
					})
					# End junction: main path cutter centered on end_frac
					var end_section := _compute_cutter_section(main_curve, end_seg, pathway_hw)
					shortcut_junctions.append({
						"other_curve": main_curve,
						"other_aux_curve": main_aux_curve,
						"other_name": "",
						"other_segment_start": end_section[0],
						"other_segment_end": end_section[1],
						"junction_frac": 1.0 if sc_num_segs <= 0 else float(sc_num_segs - 1) / float(sc_num_segs),
						"junction_segment": maxi(0, sc_num_segs - 1), # segment index along THIS (shortcut) path
					})
				pairs.append({ "name": cn + "_", "path": child, "aux": sc_aux, "junctions": shortcut_junctions })

				# --- Main path junction data (cut main wall with shortcut interior) ---
				if clean_shortcuts and not pairs.is_empty():
					var pathway_hw := _profile_cfg.ball_radius / _profile_cfg.ball_to_path_min_ratio.x + _profile_cfg.wall_thickness
					var main_junctions: Array = pairs[0].get("junctions", []) as Array
					# Start junction: shortcut cutter centred on segment 0
					var sc_start_section := _compute_cutter_section(sc_curve, 0, pathway_hw)
					main_junctions.append({
						"other_curve": sc_curve,
						"other_aux_curve": sc_aux.curve,
						"other_name": cn + "_",
						"other_segment_start": sc_start_section[0],
						"other_segment_end": sc_start_section[1],
						"junction_frac": start_frac,    # fraction along THIS (main) path
						"junction_segment": start_seg,  # segment index along THIS (main) path
					})
					# End junction: shortcut cutter centred on last segment
					var sc_last_seg := sc_curve.point_count - 2
					var sc_end_section := _compute_cutter_section(sc_curve, maxi(0, sc_last_seg), pathway_hw)
					main_junctions.append({
						"other_curve": sc_curve,
						"other_aux_curve": sc_aux.curve,
						"other_name": cn + "_",
						"other_segment_start": sc_end_section[0],
						"other_segment_end": sc_end_section[1],
						"junction_frac": end_frac,      # fraction along THIS (main) path
						"junction_segment": end_seg,    # segment index along THIS (main) path
					})
					pairs[0]["junctions"] = main_junctions

	return pairs


## Convert a parametric fraction (0–1) to a segment index on a curve.
static func _fraction_to_segment(frac: float, point_count: int) -> int:
	var total_segments := point_count - 1
	return clampi(int(frac * total_segments), 0, maxi(total_segments - 1, 0))


## Compute a segment range on |other_curve| centred on |center_segment|
## wide enough to span the pathway half-width (plus wall thickness margin).
static func _compute_cutter_section(
	other_curve: Curve3D,
	center_segment: int,
	pathway_half_width: float,
) -> Array:
	var num_segments := other_curve.point_count - 1
	if num_segments <= 0:
		return [0, 0]
	var baked_len := other_curve.get_baked_length()
	var avg_seg_len := baked_len / float(num_segments)
	# +1 buffer ensures the cutter extends far enough through the junction to
	# fully penetrate both sides of the main wall, even with short segments.
	var segments_each_side := int(ceil(pathway_half_width / avg_seg_len) + 1)
	var seg_start := maxi(0, center_segment - segments_each_side - 1)
	var seg_end := mini(num_segments, center_segment + segments_each_side)
	return [seg_start, seg_end]


## Find the parametric fraction (0–1) along |curve| closest to |target_pos|.
func _find_closest_fraction(curve: Curve3D, target_pos: Vector3, baked_len: float) -> float:
	if curve == null or baked_len < 0.001:
		return 0.0

	# Sample at regular intervals and pick the closest.
	var best_frac := 0.0
	var best_dist := INF
	var steps := 32
	for i in range(steps + 1):
		var frac := float(i) / float(steps)
		var pos := curve.sample_baked(frac * baked_len)
		var d := pos.distance_squared_to(target_pos)
		if d < best_dist:
			best_dist = d
			best_frac = frac

	# Refine with a local search around the best sample.
	var lo := clampf(best_frac - 1.0 / float(steps), 0.0, 1.0)
	var hi := clampf(best_frac + 1.0 / float(steps), 0.0, 1.0)
	var refine_steps := 16
	for i in range(refine_steps + 1):
		var frac := lerpf(lo, hi, float(i) / float(refine_steps))
		var pos := curve.sample_baked(frac * baked_len)
		var d := pos.distance_squared_to(target_pos)
		if d < best_dist:
			best_dist = d
			best_frac = frac

	return best_frac

# -----------------------------------------------------------------------------
# Entry point (async)
# -----------------------------------------------------------------------------

func regenerate(sync: bool) -> void:
	if _is_regenerating:
		push_warning("OclMeshBuilder: regeneration already in progress, skipping.")
		return
	_is_regenerating = true

	var total_start: int = Time.get_ticks_usec()

	_ensure_config()
	_clear_all_chunks()

	var path_pairs := _collect_path_pairs()
	if path_pairs.is_empty():
		push_error("OclMeshBuilder: no path pairs found to sweep")
		_is_regenerating = false
		return

	# Capture config for worker threads (avoids main-thread-only bindings).
	var captured_cfg: ProfileBuilder.Config = _profile_cfg
	var captured_display_fancy: bool = display_fancy
	var captured_physics_fancy: bool = physics_fancy
	var captured_display_opts: OclMeshOptions = display_options
	var captured_physics_opts: OclMeshOptions = physics_options

	var captured_main_path := main_path
	var captured_end_caps: bool = end_caps
	var captured_clean_shortcuts: bool = clean_shortcuts
	var captured_debug_fuse: bool = debug_fuse_junctions

	var captured_display_show_faces: bool = display_show_faces
	var captured_display_edge_radius: float = display_edge_radius
	var captured_display_vertex_radius: float = display_vertex_radius
	var captured_physics_show_faces: bool = physics_show_faces
	var captured_physics_edge_radius: float = physics_edge_radius
	var captured_physics_vertex_radius: float = physics_vertex_radius

	var captured_display_sweep_mode: int = display_sweep_mode
	var captured_display_shortcut_cutter_sweep_mode: int = display_shortcut_cutter_sweep_mode
	var captured_physics_sweep_mode: int = physics_sweep_mode
	var captured_physics_shortcut_cutter_sweep_mode: int = physics_shortcut_cutter_sweep_mode
	var captured_debug_color_sweep: bool = debug_color_sweep_mode
	var captured_display_validate: bool = display_validate_geometry
	var captured_physics_validate: bool = physics_validate_geometry

	var captured_obstacle_pos_freq: float = obstacle_positive_frequency
	var captured_obstacle_seed: int = obstacle_seed_offset
	var captured_obstacle_debug: bool = obstacle_debug_mode
	var captured_obstacle_max_rotation: float = obstacle_debug_max_rotation
	var captured_obstacle_max_offset: Vector2 = obstacle_debug_max_offset
	var captured_obstacle_min_offset: Vector2 = obstacle_debug_min_offset

	var scheduler := TaskScheduler.new(sync)
	scheduler.max_concurrent = max_concurrent
	_scheduler = scheduler
	_batches.clear()
	_pending_results.clear()
	_progress_done = 0
	_progress_failed = 0

	# First pass: count all chunks and pre-register batches so we know when
	# each batch is complete as results arrive out of order.
	var total_segments := 0
	var global_chunk_counter := 0

	for pair in path_pairs:
		var seg_count: int = (pair["path"] as Path3D).curve.point_count - 1
		if seg_count <= 0:
			continue
		total_segments += seg_count
		var n_chunks := ChunkBuilder.new().plan_chunks(seg_count).size()
		for _ci in range(n_chunks):
			var batch_id: int = int(global_chunk_counter / float(maxi(merge_batch_size, 1))) if merge_batch_size > 1 else global_chunk_counter
			var pair_name: String = pair["name"]
			var batch_name := pair_name + ("Batch" if merge_batch_size > 1 else "Chunk") + str(batch_id)
			if not _batches.has(batch_id):
				_batches[batch_id] = {"pending": 0, "name": batch_name}
				_pending_results[batch_id] = []
			(_batches[batch_id] as Dictionary)["pending"] += 1
			global_chunk_counter += 1

	_progress_total = global_chunk_counter
	_progress_start_us = total_start
	generation_started.emit(_progress_total)
	print("[OclMeshBuilder] Dispatching ", _progress_total, " chunks across ",
			path_pairs.size(), " pair(s), ", total_segments, " total segment(s). Polling...")

	# Second pass: dispatch tasks with pre-computed batch IDs.
	global_chunk_counter = 0
	var noise_offset := 0.0
	for pair in path_pairs:
		var pair_name: String = pair["name"]
		var pair_path: Path3D = pair["path"]
		var pair_aux: Path3D = pair["aux"]
		var pair_junctions: Array = pair["junctions"]

		var seg_count: int = pair_path.curve.point_count - 1
		if seg_count <= 0:
			continue

		var chunker := ChunkBuilder.new()
		chunker.chunk_size = chunk_size
		var chunks: Array = chunker.plan_chunks(seg_count)

		var captured_path_curve: Curve3D = pair_path.curve
		var captured_aux_curve: Curve3D = pair_aux.curve
		var captured_pair_name := pair_name
		var captured_pair_junctions: Array = pair_junctions

		# Force Godot's lazy bake cache to populate on the main thread before any
		# worker accesses these curves. Curve3D._bake() is not thread-safe: parallel
		# workers racing to call get_baked_length() / sample_baked() on an unbaked
		# curve will corrupt the internal baked_points array, causing some chunks to
		# receive garbage positions and fail (or silently produce wrong geometry).
		captured_path_curve.get_baked_length()
		captured_aux_curve.get_baked_length()
		for junc in captured_pair_junctions:
			var jc: Curve3D = junc.get("other_curve")
			var ja: Curve3D = junc.get("other_aux_curve")
			if jc: jc.get_baked_length()
			if ja: ja.get_baked_length()

		# Precompute per-segment wall heights for this pair.
		var seg_count_for_heights: int = captured_path_curve.point_count
		var segment_wall_heights := PackedFloat32Array()
		segment_wall_heights.resize(seg_count_for_heights)
		var pair_baked_len := pair_path.curve.get_baked_length()
		for si in range(seg_count_for_heights):
			var t := float(si) / float(maxi(seg_count_for_heights - 1, 1))
			segment_wall_heights[si] = _sample_wall_height(noise_offset + t * pair_baked_len)
		noise_offset += pair_baked_len

		var total_chunks := chunks.size()
		for chunk_idx in range(mini(total_chunks, 1) if OS.get_environment("OCL_DEBUG_FIRST_CHUNK_ONLY") == "1" else total_chunks):
			var c: ChunkBuilder.Chunk = chunks[chunk_idx] as ChunkBuilder.Chunk
			var local_idx := chunk_idx
			var global_idx := global_chunk_counter
			var batch_id: int = int(float(global_idx) / maxi(merge_batch_size, 1)) if merge_batch_size > 1 else global_idx
			var is_first := local_idx == 0
			var is_last := local_idx == total_chunks - 1
			var chunk_seg_heights: PackedFloat32Array = segment_wall_heights.slice(c.start_segment, c.end_segment + 1)
			scheduler.dispatch_task(func():
				var worker_start := Time.get_ticks_usec()
				var result: Dictionary = _worker_build_chunk(
					global_idx, c,
					captured_path_curve, captured_aux_curve,
					captured_cfg,
					captured_display_fancy, captured_physics_fancy,
					captured_display_opts, captured_physics_opts,
					captured_display_show_faces, captured_display_edge_radius, captured_display_vertex_radius,
					captured_physics_show_faces, captured_physics_edge_radius, captured_physics_vertex_radius,
					captured_main_path,
					captured_end_caps,
					is_first, is_last,
					captured_pair_name,
					captured_pair_junctions if captured_clean_shortcuts else [],
					captured_debug_fuse,
					chunk_seg_heights,
					captured_obstacle_pos_freq,
					captured_obstacle_seed + global_idx * 1337,
					captured_obstacle_debug,
					captured_obstacle_max_rotation,
					captured_obstacle_max_offset,
					captured_obstacle_min_offset,
					captured_display_sweep_mode,
					captured_display_shortcut_cutter_sweep_mode,
					captured_physics_sweep_mode,
					captured_physics_shortcut_cutter_sweep_mode,
					captured_display_validate,
					captured_physics_validate,
				)
				result["batch_id"] = batch_id
				result["elapsed_ms"] = (Time.get_ticks_usec() - worker_start) / 1000.0
				result["debug_color_sweep"] = captured_debug_color_sweep
				scheduler.submit_result(result)
			, false, "OclChunk")
			global_chunk_counter += 1

	while true:
		scheduler.reap_completed()
		for res in scheduler.collect_all():
			_on_chunk_result(res as Dictionary)
		if not scheduler.is_busy():
			break
		await get_tree().process_frame
		if not _is_regenerating:
			return

	for res in scheduler.collect_all():
		_on_chunk_result(res as Dictionary)

	# Flush any partially-filled batches at the end of the run.
	for batch_id in _batches.keys():
		var bucket: Array = _pending_results.get(batch_id, [])
		if not bucket.is_empty():
			_flush_batch(batch_id)

	var total_ms := (Time.get_ticks_usec() - total_start) / 1000.0
	print("[OclMeshBuilder] All %d chunks done in %.1f ms (%d failed)" % [
		_progress_total, total_ms, _progress_failed])
	generation_finished.emit(total_ms, _progress_total, _progress_failed)

	if Engine.is_editor_hint():
		_persist_resources()
	_scheduler = null
	_is_regenerating = false

# =============================================================================
# Worker helpers  (thread-pool threads)
# =============================================================================

static func _worker_build_chunk(
	chunk_idx: int, chunk: ChunkBuilder.Chunk,
	path_curve: Curve3D, aux_curve: Curve3D,
	cfg: ProfileBuilder.Config,
	cdisplay_fancy: bool, cphysics_fancy: bool,
	display_opts: OclMeshOptions, physics_opts: OclMeshOptions,
	do_display_faces: bool,
	cdisplay_edge_radius: float, cdisplay_vertex_radius: float,
	do_physics_faces: bool,
	cphysics_edge_radius: float, cphysics_vertex_radius: float,
	do_main_path: bool,
	do_end_caps: bool,
	is_first_chunk: bool, is_last_chunk: bool,
	pair_name: String = "",
	pair_junctions_to_clean: Array = [],
	pdebug_fuse_junctions: bool = false,
	segment_wall_heights: PackedFloat32Array = PackedFloat32Array(),
	pobstacle_pos_freq: float = 0.0,
	_seed: int = 0,
	pobstacle_debug: bool = false,
	pobstacle_max_rotation: float = 1.0,
	pobstacle_max_offset: Vector2 = Vector2(1.0, 1.0),
	pobstacle_min_offset: Vector2 = Vector2(0.0, 0.0),
	cdisplay_sweep_mode: int = 0,
	cdisplay_shortcut_cutter_sweep_mode: int = 0,
	cphysics_sweep_mode: int = 0,
	cphysics_shortcut_cutter_sweep_mode: int = 0,
	cdisplay_validate: bool = true,
	cphysics_validate: bool = false,
) -> Dictionary:
	var result: Dictionary = {
		"idx": chunk_idx,
		"prefix": pair_name,
		# Display
		"v": PackedFloat64Array(),
		"e": PackedFloat64Array(),
		"f": [],
		# Physics
		"pv": PackedFloat64Array(),
		"pe": PackedFloat64Array(),
		"pf": PackedVector3Array(),
	}

	var has_display_edges := cdisplay_edge_radius != 0.0
	var has_display_vertices := cdisplay_vertex_radius != 0.0
	var has_physics_edges := cphysics_edge_radius != 0.0
	var has_physics_vertices := cphysics_vertex_radius != 0.0

	var any_display := do_display_faces or has_display_edges or has_display_vertices
	var any_physics := do_physics_faces or has_physics_edges or has_physics_vertices
	if not any_display and not any_physics:
		return result

	# Only add end caps if enabled AND at global track ends.
	var is_shortcut := not pair_name.is_empty()
	var add_start_cap := do_end_caps and is_first_chunk and not is_shortcut
	var add_end_cap := do_end_caps and is_last_chunk and not is_shortcut

	# Filter junctions to those whose cutter tube may overlap this chunk.
	# Uses junction_segment (a segment index on THIS path) for an exact,
	# unit-consistent comparison — no baked-length vs segment-index mismatch.
	# The cutter tube extends ~pathway_hw along THIS path at the junction point;
	# factor 3 covers shallow-angle intersections (down to ~20°).
	var chunk_junctions: Array = []
	if not pair_junctions_to_clean.is_empty():
		var pathway_hw := cfg.ball_radius / cfg.ball_to_path_min_ratio.x + cfg.wall_thickness
		var baked_len := path_curve.get_baked_length()
		var num_segs := path_curve.point_count - 1
		var avg_seg_len := baked_len / float(maxi(num_segs, 1))
		# Margin in segments: how many segments the cutter tube spans along THIS path.
		var margin_segs := int(ceil(pathway_hw * 3.0 / avg_seg_len)) + 1
		for junc in pair_junctions_to_clean:
			var js: int = junc.get("junction_segment", -1)
			if js < 0:
				# Legacy junction without segment index — fall back to fraction comparison.
				var jf: float = junc["junction_frac"]
				var chunk_start_frac := float(chunk.start_segment) / float(maxi(num_segs, 1))
				var chunk_end_frac := float(chunk.end_segment) / float(maxi(num_segs, 1))
				var margin_frac := (pathway_hw * 3.0) / baked_len if baked_len > 0.001 else 0.1
				if jf >= chunk_start_frac - margin_frac and jf <= chunk_end_frac + margin_frac:
					chunk_junctions.append(junc)
			else:
				if js >= chunk.start_segment - margin_segs and js <= chunk.end_segment + margin_segs:
					chunk_junctions.append(junc)

	# Display: quality-descending fallback (starts from configured sweep+fancy).
	var display_attempts := _make_sweep_attempts(cdisplay_sweep_mode, cdisplay_fancy, true)
	# Physics: quality-ascending fallback (starts from its configured preference
	# which is typically loft+non-fancy, and escalates toward sweep+fancy).
	var phys_attempts := _make_sweep_attempts(cphysics_sweep_mode, cphysics_fancy, false)

	var display_graphs: Array[OclGraphHandle] = []
	var display_used_attempt := -1

	if any_display:
		var disp_result := _build_and_extract(
			chunk, path_curve, aux_curve, cfg,
			display_attempts, display_opts,
			has_display_vertices, has_display_edges, do_display_faces,
			cdisplay_vertex_radius, cdisplay_edge_radius, result, true,
			do_main_path, add_start_cap, add_end_cap,
			chunk_junctions, pdebug_fuse_junctions,
			segment_wall_heights,
			pobstacle_pos_freq, _seed, pobstacle_debug,
			pobstacle_max_rotation, pobstacle_max_offset, pobstacle_min_offset,
			cdisplay_shortcut_cutter_sweep_mode,
			cdisplay_validate,
		)
		display_graphs = disp_result[0]
		display_used_attempt = disp_result[1]
		result["display_used_attempt"] = display_used_attempt

	if any_physics:
		var phys_first: Dictionary = phys_attempts[0] if not phys_attempts.is_empty() else {}
		var disp_attempt: Dictionary = display_attempts[display_used_attempt] if display_used_attempt >= 0 else {}
		var phys_reuse_display: bool = (
			not display_graphs.is_empty()
			and not phys_first.is_empty()
			and phys_first["mode"] == disp_attempt.get("mode", -1)
			and phys_first["fancy"] == disp_attempt.get("fancy", false)
		)

		if phys_reuse_display:
			_extract_physics_from_graphs(display_graphs, physics_opts,
				has_physics_vertices, has_physics_edges, do_physics_faces,
				cphysics_vertex_radius, cphysics_edge_radius, result)
		else:
			var phys_result := _build_and_extract(
				chunk, path_curve, aux_curve, cfg,
				phys_attempts, physics_opts,
				has_physics_vertices, has_physics_edges, do_physics_faces,
				cphysics_vertex_radius, cphysics_edge_radius, result, false,
				do_main_path, add_start_cap, add_end_cap,
				chunk_junctions, pdebug_fuse_junctions,
				segment_wall_heights,
				pobstacle_pos_freq, _seed, pobstacle_debug,
				pobstacle_max_rotation, pobstacle_max_offset, pobstacle_min_offset,
				cphysics_shortcut_cutter_sweep_mode,
				cphysics_validate,
			)
			for g in phys_result[0]:
				OclTopo.graph_free(g)

	for g in display_graphs:
		OclTopo.graph_free(g)

	return result


## Extract physics mesh data from already-built graphs using physics mesh opts.
static func _extract_physics_from_graphs(
	graphs: Array[OclGraphHandle],
	physics_opts: OclMeshOptions,
	do_vertices: bool, do_edges: bool, do_faces: bool,
	v_radius: float, e_radius: float,
	result: Dictionary,
) -> void:
	for graph in graphs:
		if do_vertices:
			var mm := MultiMesh.new()
			if OclMeshToGodot.mesh_vertices(graph, mm, physics_opts, null, v_radius) == OclCore.OK:
				var xforms := _extract_multimesh_transforms(mm)
				result["pv"] = (result.get("pv", PackedFloat64Array()) as PackedFloat64Array) + xforms
		if do_edges:
			var mm := MultiMesh.new()
			if OclMeshToGodot.mesh_edges(graph, mm, physics_opts, null, e_radius) == OclCore.OK:
				var xforms := _extract_multimesh_transforms(mm)
				result["pe"] = (result.get("pe", PackedFloat64Array()) as PackedFloat64Array) + xforms
		if do_faces:
			var tris := OclMeshToGodot.extract_face_triangles(graph, physics_opts, null)
			result["pf"] = (result.get("pf", PackedVector3Array()) as PackedVector3Array) + tris

## Build a sweep attempt ladder from a preferred (mode, fancy) pair.
## The ladder always escalates from the given preference toward the safest
## fallback (non-fancy loft).  When prefer_quality=true the initial attempts
## try higher quality; when false they start from the simplest and escalate.
static func _make_sweep_attempts(mode: int, fancy: bool, prefer_quality: bool) -> Array:
	# Full quality-descending ladder (display direction).
	var full: Array = [
		{"mode": SweepMode.SWEEP,      "fancy": true},
		{"mode": SweepMode.SWEEP,      "fancy": false},
		{"mode": SweepMode.LOFT_RULED, "fancy": true},
		{"mode": SweepMode.LOFT_RULED, "fancy": false},
	]
	if prefer_quality:
		# Start from the requested (mode, fancy) and continue downward.
		var start := 0
		for i in range(full.size()):
			if full[i]["mode"] == mode and full[i]["fancy"] == fancy:
				start = i
				break
		return full.slice(start)
	else:
		# Physics: start from the requested (mode, fancy) and escalate upward
		# (trying simpler first, then escalating toward quality as fallback).
		var start := full.size() - 1
		for i in range(full.size()):
			if full[i]["mode"] == mode and full[i]["fancy"] == fancy:
				start = i
				break
		# Ladder: preferred first, then escalate toward higher quality.
		# e.g. for LOFT_RULED+non-fancy: [loft/nf, loft/f, sweep/nf, sweep/f]
		var result: Array = [full[start]]
		# Add entries going up (toward more quality).
		for i in range(start - 1, -1, -1):
			result.append(full[i])
		return result


## Build graphs and extract mesh data into |result|.
## |sweep_attempts| is the ordered fallback ladder ({mode, fancy} dicts).
## Returns [graphs, used_attempt_idx]; graphs is empty on total failure.
static func _build_and_extract(
	chunk: ChunkBuilder.Chunk,
	path_curve: Curve3D, aux_curve: Curve3D,
	cfg: ProfileBuilder.Config,
	sweep_attempts: Array,
	mesh_opts: OclMeshOptions,
	do_vertices: bool, do_edges: bool, do_faces: bool,
	v_radius: float, e_radius: float,
	result: Dictionary, is_display: bool,
	do_main_path: bool, add_start_cap: bool, add_end_cap: bool,
	chunk_junctions: Array,
	pdebug_fuse_junctions: bool = false,
	segment_wall_heights: PackedFloat32Array = PackedFloat32Array(),
	pobstacle_pos_freq: float = 0.0,
	_seed: int = 0,
	pobstacle_debug: bool = false,
	pobstacle_max_rotation: float = 1.0,
	pobstacle_max_offset: Vector2 = Vector2(1.0, 1.0),
	pobstacle_min_offset: Vector2 = Vector2(0.0, 0.0),
	pshortcut_cutter_sweep_mode: int = 0,
	pvalidate_geometry: bool = true,
) -> Array:  # [Array[OclGraphHandle], int used_attempt]
	var prefix: String = "" if is_display else "p"

	var out_used := [- 1]
	var chunker := ChunkBuilder.new()
	chunker.debug_fuse_junctions = pdebug_fuse_junctions
	chunker.validate_geometry = pvalidate_geometry
	var graphs: Array[OclGraphHandle] = chunker.build_chunk_graphs(
		chunk, path_curve, aux_curve, cfg,
		do_main_path, add_start_cap, add_end_cap,
		chunk_junctions, sweep_attempts, out_used,
		segment_wall_heights,
		pobstacle_pos_freq, _seed, pobstacle_debug,
		pobstacle_max_rotation, pobstacle_max_offset, pobstacle_min_offset,
		pshortcut_cutter_sweep_mode)
	if graphs.is_empty():
		if is_display:
			push_warning("OclMeshBuilder: build_chunk_graphs returned empty for chunk %d (all sweep fallbacks failed)" % chunk.start_segment)
		return [graphs, -1]

	for graph_i in range(graphs.size()):
		var graph := graphs[graph_i]
		if do_vertices:
			var mm := MultiMesh.new()
			var st: int = OclMeshToGodot.mesh_vertices(graph, mm, mesh_opts, null, v_radius) as OclCore.status
			if st == OclCore.OK:
				var xforms := _extract_multimesh_transforms(mm)
				var key := prefix + "v"
				result[key] = (result.get(key, PackedFloat64Array()) as PackedFloat64Array) + xforms
			else:
				push_error("OclMeshBuilder: mesh_vertices failed: ", OclCore.status_to_string(st))

		if do_edges:
			var mm := MultiMesh.new()
			var st: int = OclMeshToGodot.mesh_edges(graph, mm, mesh_opts, null, e_radius) as OclCore.status
			if st == OclCore.OK:
				var xforms := _extract_multimesh_transforms(mm)
				var key := prefix + "e"
				result[key] = (result.get(key, PackedFloat64Array()) as PackedFloat64Array) + xforms
			else:
				push_error("OclMeshBuilder: mesh_edges failed: ", OclCore.status_to_string(st))

		if do_faces:
			if is_display:
				var face_arr := _export_face_data(graph, mesh_opts)
				if not face_arr.is_empty():
					result["f"] = (result.get("f", []) as Array) + face_arr
			else:
				var tris := OclMeshToGodot.extract_face_triangles(graph, mesh_opts, null)
				result["pf"] = (result.get("pf", PackedVector3Array()) as PackedVector3Array) + tris

	return [graphs, out_used[0]]

static func _export_face_data(graph: OclGraphHandle, opts: OclMeshOptions) -> Array:
	var mesh := ArrayMesh.new()
	var st: int = OclMeshToGodot.mesh_faces(graph, mesh, opts, null, true, true, true) as OclCore.status
	if st != OclCore.OK:
		return []
	if mesh.get_surface_count() == 0:
		return []
	var arrays: Array = mesh.surface_get_arrays(0)
	if arrays.size() < ArrayMesh.ARRAY_MAX:
		return []
	var verts = arrays[ArrayMesh.ARRAY_VERTEX]
	var idxs  = arrays[ArrayMesh.ARRAY_INDEX]
	if verts == null or (verts is PackedVector3Array and (verts as PackedVector3Array).is_empty()):
		return []
	if idxs == null or (idxs is PackedInt32Array and (idxs as PackedInt32Array).is_empty()):
		return []
	return [arrays]

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

static func _decode_transform(data: PackedFloat64Array, index: int) -> Transform3D:
	var base: int = index * 16
	var mbasis := Basis(
		Vector3(data[base + 0], data[base + 4], data[base + 8]),
		Vector3(data[base + 1], data[base + 5], data[base + 9]),
		Vector3(data[base + 2], data[base + 6], data[base + 10]),
	)
	var origin := Vector3(data[base + 12], data[base + 13], data[base + 14])
	return Transform3D(mbasis, origin)

# =============================================================================
# Cleanup
# =============================================================================

func _exit_tree() -> void:
	if _scheduler != null and _scheduler.is_busy():
		_scheduler.sync_and_discard()
		_scheduler = null
		_is_regenerating = false

func _clear_all_chunks() -> void:
	var to_remove: Array[Node] = []
	for child in get_children():
		if child is Node3D and ("Chunk" in str(child.name) or "Batch" in str(child.name)):
			to_remove.append(child)
	for n in to_remove:
		n.queue_free()
	_batches.clear()
	_pending_results.clear()

# =============================================================================
# Result handling (main thread)
# =============================================================================

## Called on the main thread for each arriving chunk result.
func _on_chunk_result(result: Dictionary) -> void:
	var batch_id: int = result.get("batch_id", 0)
	_progress_done += 1

	var is_empty_result := (result.get("f", []) as Array).is_empty() \
		and (result.get("pf", PackedVector3Array()) as PackedVector3Array).is_empty() \
		and (result.get("e", PackedFloat64Array()) as PackedFloat64Array).is_empty()
	if is_empty_result:
		_progress_failed += 1

	chunk_completed.emit(
		result.get("idx", 0),
		result.get("prefix", ""),
		result.get("elapsed_ms", 0.0),
	)

	# Accumulate into the batch bucket.
	var bucket: Array = _pending_results.get(batch_id, [])
	bucket.append(result)
	_pending_results[batch_id] = bucket

	# Decrement pending count; flush when this batch is complete.
	var batch_info: Dictionary = _batches.get(batch_id, {})
	batch_info["pending"] = (batch_info.get("pending", 1) as int) - 1
	_batches[batch_id] = batch_info
	if batch_info["pending"] <= 0:
		_flush_batch(batch_id)


func _flush_batch(batch_id: int) -> void:
	var bucket: Array = _pending_results.get(batch_id, [])
	if bucket.is_empty():
		return
	var batch_info: Dictionary = _batches.get(batch_id, {})
	var batch_name: String = batch_info.get("name", "Batch" + str(batch_id))

	if merge_batch_size <= 1:
		# No merging: one node per chunk result.
		for result in bucket:
			_apply_chunk(result)
	else:
		var typed_bucket: Array[Dictionary] = []
		typed_bucket.assign(bucket)
		_apply_batch(typed_bucket, batch_name)

	_pending_results.erase(batch_id)
	batch_ready.emit(batch_name, bucket.size())


## Merge geometry from multiple chunk results into a single named batch node,
## reducing draw calls and scene-tree overhead.
func _apply_batch(results: Array[Dictionary], batch_name: String) -> void:
	if results.is_empty():
		return
	var batch_root := Node3D.new()
	batch_root.name = batch_name
	add_child(batch_root, true)
	if Engine.is_editor_hint():
		batch_root.set_owner(_scene_root())

	# Accumulate geometry across all results.
	var all_f_surfaces: Array = []
	var all_pf_tris := PackedVector3Array()
	var all_e_transforms := PackedFloat64Array()
	var all_pe_transforms := PackedFloat64Array()
	var all_v_transforms := PackedFloat64Array()
	var all_pv_transforms := PackedFloat64Array()
	var has_physics_faces := false
	var has_physics_edges := false
	var has_physics_vertices := false

	for result in results:
		var f: Array = result.get("f", [])
		var pf: PackedVector3Array = result.get("pf", PackedVector3Array())
		var e: PackedFloat64Array = result.get("e", PackedFloat64Array())
		var pe: PackedFloat64Array = result.get("pe", PackedFloat64Array())
		var v: PackedFloat64Array = result.get("v", PackedFloat64Array())
		var pv: PackedFloat64Array = result.get("pv", PackedFloat64Array())
		all_f_surfaces.append_array(f)
		all_pf_tris.append_array(pf)
		all_e_transforms.append_array(e)
		all_pe_transforms.append_array(pe)
		all_v_transforms.append_array(v)
		all_pv_transforms.append_array(pv)
		if pf.size() >= 3: has_physics_faces = true
		if pe.size() > 0: has_physics_edges = true
		if pv.size() > 0: has_physics_vertices = true

	var has_faces_display := not all_f_surfaces.is_empty()
	var has_edges_display := all_e_transforms.size() > 0
	var has_vertices_display := all_v_transforms.size() > 0

	# Debug sweep-mode colouring: pick the most common used_attempt across results.
	var debug_sweep_mat: Material = null
	if results[0].get("debug_color_sweep", false):
		var attempt_counts := {}
		for r in results:
			var a: int = r.get("display_used_attempt", -1)
			attempt_counts[a] = attempt_counts.get(a, 0) + 1
		var most_common := -1
		var best_count := 0
		for k in attempt_counts:
			if attempt_counts[k] > best_count:
				best_count = attempt_counts[k]
				most_common = k
		# Map attempt index to colour: 0=sweep+fancy(green), 1=sweep+nf(yellow),
		# 2=loft+fancy(orange), 3=loft+nf(red), -1/unknown=grey
		var debug_colors := [Color.GREEN, Color.YELLOW, Color.ORANGE_RED, Color.RED, Color.GRAY]
		var ci := clampi(most_common, 0, 4)
		var col: Color = debug_colors[ci] if ci >= 0 else debug_colors[4]
		var dbg_mat := StandardMaterial3D.new()
		dbg_mat.albedo_color = col
		dbg_mat.flags_unshaded = true
		debug_sweep_mat = dbg_mat

	# --- Merged face node ---
	if has_faces_display or has_physics_faces:
		var faces_node: Node3D
		if has_physics_faces:
			faces_node = StaticBody3D.new()
		else:
			faces_node = Node3D.new()
		faces_node.name = "Faces"
		batch_root.add_child(faces_node, true)
		if Engine.is_editor_hint():
			faces_node.set_owner(_scene_root())

		if has_physics_faces:
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(all_pf_tris)
			var cs := CollisionShape3D.new()
			cs.name = "CollisionFaces"
			cs.shape = shape
			faces_node.add_child(cs, true)
			if Engine.is_editor_hint():
				cs.set_owner(_scene_root())

		if has_faces_display:
			var merged: Array
			if all_f_surfaces.size() == 1:
				merged = all_f_surfaces[0]
				merged.resize(Mesh.ARRAY_MAX)
			else:
				merged = OclMeshToGodot.merge_surface_arrays(all_f_surfaces)
				merged.resize(Mesh.ARRAY_MAX)
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged)
			am.surface_set_material(0, debug_sweep_mat if debug_sweep_mat else display_faces_material)
			var mi := MeshInstance3D.new()
			mi.name = "FacesMesh"
			mi.mesh = am
			faces_node.add_child(mi, true)
			if Engine.is_editor_hint():
				mi.set_owner(_scene_root())

	# --- Merged edge node ---
	if has_edges_display or has_physics_edges:
		var edges_node: Node3D
		if has_physics_edges:
			edges_node = StaticBody3D.new()
		else:
			edges_node = Node3D.new()
		edges_node.name = "Edges"
		batch_root.add_child(edges_node, true)
		if Engine.is_editor_hint():
			edges_node.set_owner(_scene_root())

		if has_edges_display:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			var slices := _slices_from_angle(display_options.angle)
			var cyl := CylinderMesh.new()
			cyl.height = 1.0
			cyl.radial_segments = slices
			cyl.rings = 1
			cyl.cap_top = false
			cyl.cap_bottom = false
			cyl.surface_set_material(0, display_edges_material)
			mm.mesh = cyl
			var n := int(all_e_transforms.size() / 16.0)
			if n > 0:
				mm.instance_count = n
				for i in range(n):
					mm.set_instance_transform(i, _decode_transform(all_e_transforms, i))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "EdgesMesh"
			mmi.multimesh = mm
			edges_node.add_child(mmi, true)
			if Engine.is_editor_hint():
				mmi.set_owner(_scene_root())

		if has_physics_edges:
			var n := int(all_pe_transforms.size() / 16.0)
			for i in range(n):
				var t := _decode_transform(all_pe_transforms, i)
				var radius := t.basis.x.length()
				var seg_len := t.basis.y.length()
				if radius < 0.0001:
					continue
				var cs := CollisionShape3D.new()
				var shape := CapsuleShape3D.new()
				shape.radius = radius
				shape.height = maxf(0.001, seg_len - 2.0 * radius)
				cs.shape = shape
				cs.transform = Transform3D(Basis(t.basis.x.normalized(), t.basis.y.normalized(), t.basis.z.normalized()), t.origin)
				cs.name = "_occtl_edge_" + str(i)
				edges_node.add_child(cs, true)
				if Engine.is_editor_hint():
					cs.set_owner(_scene_root())

	# --- Merged vertex node ---
	if has_vertices_display or has_physics_vertices:
		var verts_node: Node3D
		if has_physics_vertices:
			verts_node = StaticBody3D.new()
		else:
			verts_node = Node3D.new()
		verts_node.name = "Vertices"
		batch_root.add_child(verts_node, true)
		if Engine.is_editor_hint():
			verts_node.set_owner(_scene_root())

		if has_vertices_display:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			var slices := _slices_from_angle(display_options.angle)
			var sph := SphereMesh.new()
			sph.radius = 1.0
			sph.radial_segments = slices
			sph.rings = maxi(int(slices / 2.0), 2)
			sph.surface_set_material(0, display_vertices_material)
			mm.mesh = sph
			var n := int(all_v_transforms.size() / 16.0)
			if n > 0:
				mm.instance_count = n
				for i in range(n):
					mm.set_instance_transform(i, _decode_transform(all_v_transforms, i))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "VerticesMesh"
			mmi.multimesh = mm
			verts_node.add_child(mmi, true)
			if Engine.is_editor_hint():
				mmi.set_owner(_scene_root())

		if has_physics_vertices:
			var n := int(all_pv_transforms.size() / 16.0)
			for i in range(n):
				var t := _decode_transform(all_pv_transforms, i)
				var radius := t.basis.x.length()
				if radius < 0.0001:
					continue
				var cs := CollisionShape3D.new()
				var shape := SphereShape3D.new()
				shape.radius = radius
				cs.shape = shape
				cs.transform = Transform3D(Basis.IDENTITY, t.origin)
				cs.name = "_occtl_vertex_" + str(i)
				verts_node.add_child(cs, true)
				if Engine.is_editor_hint():
					cs.set_owner(_scene_root())

func _apply_chunk(result: Dictionary) -> void:
	var idx: int = result.get("idx", 0)
	var prefix: String = result.get("prefix", "")

	# Helper to get or create the per-chunk root node (plain Node3D).
	var ensure_chunk_root := func() -> Node3D:
		var node_name := prefix + "Chunk" + str(idx)
		var existing := get_node_or_null(node_name) as Node3D
		if existing != null:
			return existing

		var root: Node3D = Node3D.new()
		root.name = node_name
		add_child(root, true)
		if Engine.is_editor_hint():
			root.set_owner(_scene_root())
		return root

	# Helper to get or create a named child under the chunk root.
	# The features child MAY be a StaticBody3D when physics is enabled,
	# otherwise a plain Node3D.
	var ensure_child := func(parent: Node, child_name: String, _has_display: bool, has_physics: bool) -> Node3D:
		var existing := parent.get_node_or_null(child_name) as Node3D
		if existing != null:
			return existing

		var child: Node3D
		if has_physics:
			child = StaticBody3D.new()
		else:
			child = Node3D.new()
		child.name = child_name
		parent.add_child(child, true)
		if Engine.is_editor_hint():
			child.set_owner(_scene_root())
		return child

	var chunk_root: Node3D = ensure_chunk_root.call()

	# --- Faces ---
	var f_surfaces: Array = result.get("f", []) as Array
	var pf_tris: PackedVector3Array = result.get("pf", PackedVector3Array()) as PackedVector3Array
	var has_faces_display := not f_surfaces.is_empty()
	var has_faces_physics := pf_tris.size() >= 3

	if has_faces_display or has_faces_physics:
		var features_root: Node3D = ensure_child.call(chunk_root, "Faces", has_faces_display, has_faces_physics)

		# --- Face collision shape ---
		if has_faces_physics:
			var cs_name := "CollisionFaces"
			var old_cs := features_root.get_node_or_null(cs_name) as CollisionShape3D
			if old_cs != null:
				old_cs.queue_free()

			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(pf_tris)
			var cs := CollisionShape3D.new()
			cs.name = cs_name
			cs.shape = shape
			features_root.add_child(cs, true)
			if Engine.is_editor_hint():
				cs.set_owner(_scene_root())

		# --- Face mesh ---
		if has_faces_display:
			var mesh_name := "FacesMesh"
			var mi := features_root.get_node_or_null(mesh_name) as MeshInstance3D
			if mi == null:
				mi = MeshInstance3D.new()
				mi.name = mesh_name
				features_root.add_child(mi, true)
				if Engine.is_editor_hint():
					mi.set_owner(_scene_root())

			if f_surfaces.size() == 1:
				var arr: Array = f_surfaces[0] as Array
				arr.resize(Mesh.ARRAY_MAX)
				var am := ArrayMesh.new()
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				mi.mesh = am
			else:
				# Merge multiple surfaces into one via C++.
				var merged := OclMeshToGodot.merge_surface_arrays(f_surfaces)
				merged.resize(Mesh.ARRAY_MAX)
				var am := ArrayMesh.new()
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged)
				mi.mesh = am

			# Debug sweep-mode tint for per-chunk path.
			var chunk_dbg_mat: Material = display_faces_material
			if result.get("debug_color_sweep", false):
				var a: int = result.get("display_used_attempt", -1)
				var dbg_colors := [Color.GREEN, Color.YELLOW, Color.ORANGE_RED, Color.RED, Color.GRAY]
				var ci := clampi(a, 0, 4)
				var dbm := StandardMaterial3D.new()
				dbm.albedo_color = dbg_colors[ci] if ci >= 0 else dbg_colors[4]
				dbm.flags_unshaded = true
				chunk_dbg_mat = dbm
			mi.mesh.surface_set_material(0, chunk_dbg_mat)

	# --- Edges ---
	var e_transforms: PackedFloat64Array = result.get("e", PackedFloat64Array()) as PackedFloat64Array
	var pe_transforms: PackedFloat64Array = result.get("pe", PackedFloat64Array()) as PackedFloat64Array
	var has_edges_display := e_transforms.size() > 0
	var has_edges_physics := pe_transforms.size() > 0

	if has_edges_display or has_edges_physics:
		var features_root: Node3D = ensure_child.call(chunk_root, "Edges", has_edges_display, has_edges_physics)

		if has_edges_display:
			var mm_name := "EdgesMesh"
			var mmi := features_root.get_node_or_null(mm_name) as MultiMeshInstance3D
			if mmi == null:
				mmi = MultiMeshInstance3D.new()
				mmi.name = mm_name
				features_root.add_child(mmi, true)
				if Engine.is_editor_hint():
					mmi.set_owner(_scene_root())

			var existing_mm := mmi.multimesh
			if existing_mm == null or not existing_mm.get_mesh().is_valid():
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				var slices := _slices_from_angle(display_options.angle)
				var cyl := CylinderMesh.new()
				cyl.height = 1.0
				cyl.radial_segments = slices
				cyl.rings = 1
				cyl.cap_top = false
				cyl.cap_bottom = false
				mm.mesh = cyl
				mmi.multimesh = mm
				existing_mm = mm
			existing_mm.mesh.surface_set_material(0, display_edges_material)

			var n := int(e_transforms.size() / 16.0)
			if n > 0:
				existing_mm.instance_count = n
				for i in range(n):
					existing_mm.set_instance_transform(i, _decode_transform(e_transforms, i))

		if has_edges_physics:
			_clear_collision_children(features_root, "_occtl_edge_")
			var n := int(pe_transforms.size() / 16.0)
			for i in range(n):
				var t := _decode_transform(pe_transforms, i)
				var radius := t.basis.x.length()
				var seg_len := t.basis.y.length()
				if radius < 0.0001:
					continue
				var cs := CollisionShape3D.new()
				var shape := CapsuleShape3D.new()
				shape.radius = radius
				shape.height = maxf(0.001, seg_len - 2.0 * radius)
				cs.shape = shape
				var mbasis := Basis(
					t.basis.x.normalized(),
					t.basis.y.normalized(),
					t.basis.z.normalized(),
				)
				cs.transform = Transform3D(mbasis, t.origin)
				cs.name = "_occtl_edge_" + str(i)
				features_root.add_child(cs, true)
				if Engine.is_editor_hint():
					cs.set_owner(_scene_root())

	# --- Vertices ---
	var v_transforms: PackedFloat64Array = result.get("v", PackedFloat64Array()) as PackedFloat64Array
	var pv_transforms: PackedFloat64Array = result.get("pv", PackedFloat64Array()) as PackedFloat64Array
	var has_vertices_display := v_transforms.size() > 0
	var has_vertices_physics := pv_transforms.size() > 0

	if has_vertices_display or has_vertices_physics:
		var features_root: Node3D = ensure_child.call(chunk_root, "Vertices", has_vertices_display, has_vertices_physics)

		if has_vertices_display:
			var mm_name := "VerticesMesh"
			var mmi := features_root.get_node_or_null(mm_name) as MultiMeshInstance3D
			if mmi == null:
				mmi = MultiMeshInstance3D.new()
				mmi.name = mm_name
				features_root.add_child(mmi, true)
				if Engine.is_editor_hint():
					mmi.set_owner(_scene_root())

			var existing_mm := mmi.multimesh
			if existing_mm == null or not existing_mm.get_mesh().is_valid():
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				var slices := _slices_from_angle(display_options.angle)
				var sph := SphereMesh.new()
				sph.radius = 1.0
				sph.radial_segments = slices
				sph.rings = maxi(int(slices / 2.0), 2)
				mm.mesh = sph
				mmi.multimesh = mm
				existing_mm = mm
			existing_mm.mesh.surface_set_material(0, display_vertices_material)

			var n := int(v_transforms.size() / 16.0)
			if n > 0:
				existing_mm.instance_count = n
				for i in range(n):
					existing_mm.set_instance_transform(i, _decode_transform(v_transforms, i))

		if has_vertices_physics:
			_clear_collision_children(features_root, "_occtl_vertex_")
			var n := int(pv_transforms.size() / 16.0)
			for i in range(n):
				var t := _decode_transform(pv_transforms, i)
				var radius := t.basis.x.length()
				if radius < 0.0001:
					continue
				var cs := CollisionShape3D.new()
				var shape := SphereShape3D.new()
				shape.radius = radius
				cs.shape = shape
				cs.transform = Transform3D(Basis.IDENTITY, t.origin)
				cs.name = "_occtl_vertex_" + str(i)
				features_root.add_child(cs, true)
				if Engine.is_editor_hint():
					cs.set_owner(_scene_root())

func _clear_collision_children(parent: Node, prefix: String) -> void:
	var to_remove: Array[Node] = []
	for child in parent.get_children():
		if child is CollisionShape3D and str(child.name).begins_with(prefix):
			to_remove.append(child)
	for n in to_remove:
		n.queue_free()

static func _slices_from_angle(angle: float) -> int:
	var safe := maxf(angle, 0.001)
	return maxi(4, int(roundf(PI / safe)) + 2)

# -----------------------------------------------------------------------------
# Resource persistence
# -----------------------------------------------------------------------------

func _persist_resources() -> void:
	if resource_save_path.is_empty():
		return

	var base: String = resource_save_path.trim_suffix("/")
	var dir_abs := ProjectSettings.globalize_path(base)
	DirAccess.make_dir_recursive_absolute(dir_abs)

	for branch in get_children().duplicate():
		if not (branch is Node3D and ("Chunk" in str(branch.name) or "Batch" in str(branch.name))):
			push_warning("Unexpected child of OclManager", branch)
			continue

		var path: String = base + "/" + str(branch.name) + ".scn"

		save_branch(branch, path)

		var parent = branch.get_parent()
		var index = branch.get_index()
		var bname = branch.name

		var packed = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var instance := packed.instantiate()

		instance.name = bname

		parent.remove_child(branch)
		parent.add_child(instance)
		parent.move_child(instance, index)

		instance.owner = parent.owner # or whatever is appropriate

func save_branch(branch: Node, path: String) -> Error:
	for child in branch.get_children():
		_set_owner_recursive(child, branch)

	var packed := PackedScene.new()
	var err := packed.pack(branch)
	if err != OK:
		return err

	return ResourceSaver.save(packed, path)


func _set_owner_recursive(node: Node, mowner: Node):
	node.owner = mowner
	for child in node.get_children():
		_set_owner_recursive(child, mowner)
