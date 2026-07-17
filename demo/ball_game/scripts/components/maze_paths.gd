@tool
extends Node3D
class_name MazePaths

## Manages all path curves: the main rope-simulated path, auxiliary
## binormal curves for sweep orientation, and configurable shortcut
## paths that connect non-adjacent regions of the maze.
##
## Shortcuts are simulated as additional ropes in the same physics system,
## sharing the shell, self-collision, and bending constraints with the main
## path.  The only hard constraint is fixed start/end anchor points on the
## main rope.  Each shortcut spans a random fraction of the main path,
## sampled from a span CDF curve.  The shortcut's node count (rope density)
## is controlled by a separate shortcut ratio CDF curve.
##
## All generated Path3D children are added directly to this node.
## When [member store_as_nodes] is true they are assigned an owner so they
## appear in the Godot editor scene tree.

# ── Main path ──────────────────────────────────────────────────────────────

@export var rope_physics := OclDemoOnlyRopePhysics.new()

## How much to push the paths away from themselves, as a ratio of the rope's collision radius.
## A value of 1.0 means the path curves are offset by the same distance as the rope's collision radius
## (not recommended as it promotes sharp bends that are hard to mesh).
@export_range(0.0, 5.0, 0.1) var path_offset_ratio: float = 2.0

## Curve interpolation sharpness (higher = tighter to control points).
@export var sharpness := 5.0

## Lateral offset applied when building auxiliary (binormal) curves.
@export var aux_offset_amount: float = 0.5

# ── Shortcuts ──────────────────────────────────────────────────────────────

@export_group("Shortcuts")

## Number of shortcuts to generate (0 = none, 1–3 typical).
@export_range(0, 10, 1) var total_shortcuts: int = 3

## CDF curve defining the span (fraction of main path length) for each shortcut.
## X-axis = probability [0..1], Y-axis = span value [0..1].
## Sampled via seeded RNG for reproducible but controllable shortcut spans.
@export var span_cdf: Curve

## CDF curve defining the shortcut ratio: the relative length of a shortcut
## rope compared to the main subrope it bypasses.
## Values < 1 make shortcuts shorter (faster alternate routes).
## Values > 1 make shortcuts longer (scenic detours).
## X-axis = probability [0..1], Y-axis = ratio value (>0).
## Sampled via seeded RNG for reproducible but controllable shortcuts.
@export var shortcut_ratio: Curve

## Minimum gap (in main-rope node indices) between any two anchor points.
## Prevents shortcuts from clustering at the same location.
@export_range(1, 30, 1) var min_anchor_gap: int = 3

# ── Editor ─────────────────────────────────────────────────────────────────

@export_group("Editor")

## When true, generated Path3D children are assigned the scene root as owner
## so they appear in the Godot editor scene tree.  When false they are added
## as children but stay hidden from the editor.
@export var store_as_nodes: bool = false

# ── Actions ────────────────────────────────────────────────────────────────

@export_group("Actions")

@export_tool_button("Reset") var reset_ = func(): await step(0)
@export_tool_button("Step") var step_ = func(): await step(1)
@export_tool_button("Step N") var stepn_ = func(): await step(rope_physics.iterations)
@export_tool_button("Regenerate") var regenerate_ = func(): await regenerate(false)

# ── Helpers ────────────────────────────────────────────────────────────────

func _scene_root() -> Node:
	if is_inside_tree():
		return get_tree().edited_scene_root
	var n := get_parent()
	while n and n.get_parent():
		n = n.get_parent()
	return n


func _get_generator() -> MazeGenerator:
	var p := get_parent()
	while p:
		if p is MazeGenerator:
			return p as MazeGenerator
		p = p.get_parent()
	return null


func _get_inner_radius() -> float:
	var gen := _get_generator()
	return gen.maze_inner_radius if gen else 1.0


func _get_outer_radius() -> float:
	var gen := _get_generator()
	return gen.maze_outer_radius if gen else 5.0


func _get_seed() -> int:
	var gen := _get_generator()
	return gen.seed_value if gen else 0


func _get_tube_margin() -> float:
	var gen := _get_generator()
	if gen:
		return gen.ball_radius / minf(gen.ball_to_path_min_ratio.x, gen.ball_to_path_min_ratio.y)
	return 0.15


func _ensure_curve_child(curve_name: String) -> Path3D:
	var existing := get_node_or_null(curve_name) as Path3D
	if existing:
		return existing
	var p := Path3D.new()
	p.name = curve_name
	p.curve = Curve3D.new()
	add_child(p, true)
	if store_as_nodes and Engine.is_editor_hint():
		p.set_owner(_scene_root())
	return p


func _make_rng(extra_salt: int = 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_get_seed() + extra_salt)
	return rng


func _ensure_span_cdf() -> Curve:
	if span_cdf == null:
		span_cdf = Curve.new()
		span_cdf.add_point(Vector2(0.0, 0.2))
		span_cdf.add_point(Vector2(0.5, 0.5))
		span_cdf.add_point(Vector2(1.0, 0.8))
	return span_cdf


func _ensure_shortcut_ratio() -> Curve:
	if shortcut_ratio == null:
		shortcut_ratio = Curve.new()
		shortcut_ratio.add_point(Vector2(0.0, 0.5))
		shortcut_ratio.add_point(Vector2(0.5, 1.0))
		shortcut_ratio.add_point(Vector2(1.0, 1.5))
	return shortcut_ratio

# ── Phase 1: Init main rope ───────────────────────────────────────────────

func _init_main_rope() -> void:
	rope_physics.clear()

	var inner_r := _get_inner_radius() + _get_tube_margin()
	var outer_r := _get_outer_radius() - _get_tube_margin() * 2 # Allow jumping over some broken shortcut walls

	rope_physics.inner_radius = inner_r
	rope_physics.outer_radius = outer_r
	rope_physics.collision_radius = _get_tube_margin() * 2.0 * path_offset_ratio
	rope_physics.init_rope(
		_get_seed(),
		Vector3.BACK * outer_r,
		Vector3.FORWARD * outer_r,
	)

# ── Phase 2: Generate shortcuts ───────────────────────────────────────────

## Returns true if [p] is far enough from every index already in [list].
func _is_anchor_free(p: int, list: Array[int]) -> bool:
	for used in list:
		if absi(p - used) < min_anchor_gap:
			return false
	return true


func _generate_shortcuts(used_anchors: Array[int]) -> void:
	if total_shortcuts <= 0:
		return

	var main_positions := rope_physics.get_rope_positions(0)
	var main_count := main_positions.size()
	if main_count < 3:
		return

	var cdf_span := _ensure_span_cdf()
	var cdf_ratio := _ensure_shortcut_ratio()

	for i in range(total_shortcuts):
		var rng := _make_rng(_get_seed() + i * 7919)

		# --- Pick start and end anchors with gap enforcement ---
		var anchor_start := -1
		var anchor_end := -1
		for _attempt in range(20):
			var span := cdf_span.sample(rng.randf())
			var max_start := clampf(1.0 - span, 0.0, 1.0)
			var start_frac := rng.randf_range(0.0, max_start)
			var end_frac := start_frac + span

			var candidate_start := rope_physics.find_main_node_at_fraction(start_frac)
			var candidate_end := rope_physics.find_main_node_at_fraction(end_frac)

			# Ensure end is strictly after start with minimum gap.
			if candidate_end <= candidate_start:
				candidate_end = mini(candidate_start + min_anchor_gap, main_count - 1)
			if candidate_end - candidate_start < min_anchor_gap:
				continue

			if _is_anchor_free(candidate_start, used_anchors) and _is_anchor_free(candidate_end, used_anchors):
				anchor_start = candidate_start
				anchor_end = candidate_end
				break

		# If all attempts failed, skip this shortcut.
		if anchor_start < 0:
			continue

		used_anchors.append(anchor_start)
		used_anchors.append(anchor_end)

		# --- Compute segment count from shortcut ratio ---
		var main_rope_nodes := anchor_end - anchor_start
		var ratio := cdf_ratio.sample(rng.randf())
		var shortcut_nodes := maxi(10, int(main_rope_nodes * ratio))

		rope_physics.add_shortcut(anchor_start, anchor_end, shortcut_nodes)

# ── Phase 3: Relax ────────────────────────────────────────────────────────

func _relax_all_ropes(sync: bool) -> void:
	if sync:
		rope_physics.relax()
	else:
		var task_id := WorkerThreadPool.add_task(func():
			rope_physics.relax()
		)
		while !WorkerThreadPool.is_task_completed(task_id):
			await get_tree().create_timer(0.2).timeout
		WorkerThreadPool.wait_for_task_completion(task_id)

# ── Phase 4: Build Path3D curves ──────────────────────────────────────────

func _build_all_curves() -> void:
	var rope_count := rope_physics.get_rope_count()
	if rope_count == 0:
		return

	# Main path (rope 0).
	var main_path := _ensure_curve_child("MainPath")
	var main_positions := rope_physics.get_rope_positions(0)
	CurveUtils.apply_curve_data(main_path.curve, CurveUtils.precompute_curve_data(main_positions, sharpness))
	var main_aux := _ensure_curve_child("MainPathBinormal")
	main_aux.curve = CurveUtils.build_auxiliary_curve_from_points(main_positions, aux_offset_amount, sharpness)

	# Shortcuts (ropes 1..N).
	for i in range(1, rope_count):
		var sc_positions := rope_physics.get_rope_positions(i)
		if sc_positions.size() < 2:
			continue

		var idx := i - 1
		var sc_path := _ensure_curve_child("Shortcut%d" % idx)
		CurveUtils.apply_curve_data(sc_path.curve, CurveUtils.precompute_curve_data(sc_positions, sharpness))

		var aux_path := _ensure_curve_child("Shortcut%dBinormal" % idx)
		aux_path.curve = CurveUtils.build_auxiliary_curve_from_points(sc_positions, aux_offset_amount, sharpness)


# ── Shortcut children cleanup ──────────────────────────────────────────────

func _clear_shortcut_children() -> void:
	var to_remove: Array[Node] = []
	for child in get_children():
		if child is Path3D and str(child.name).begins_with("Shortcut"):
			to_remove.append(child)
	for n in to_remove:
		remove_child(n)
		n.queue_free()

# ── Owner management ───────────────────────────────────────────────────────

func _update_owners() -> void:
	var root := _scene_root() if Engine.is_editor_hint() else null
	for child in get_children():
		if child is Path3D:
			if store_as_nodes and root:
				child.set_owner(root)
			else:
				child.set_owner(self)

# ── Public API ─────────────────────────────────────────────────────────────

## Run a single step of the pipeline.
## [param n] = 0: reinitialise (clear + init + add shortcuts + build curves).
## [param n] > 0: run [param n] relaxation iterations.
func step(n: int) -> void:
	if n == 0:
		_clear_shortcut_children()
		_init_main_rope()
		var used: Array[int] = []
		_generate_shortcuts(used)
		_build_all_curves()
		_update_owners()
	else:
		var old_iterations := rope_physics.iterations
		rope_physics.iterations = n
		await _relax_all_ropes(true)
		rope_physics.iterations = old_iterations
		_build_all_curves()
		_update_owners()


## Full regeneration: clear → init → shortcuts → relax → build curves.
func regenerate(sync: bool) -> void:
	var start_time := Time.get_ticks_usec()

	_clear_shortcut_children()
	_init_main_rope()

	var used: Array[int] = []
	_generate_shortcuts(used)

	var relax_start := Time.get_ticks_usec()
	await _relax_all_ropes(sync)
	print("[MazePaths] Relax: ", (Time.get_ticks_usec() - relax_start) / 1000.0, " ms")

	_build_all_curves()
	_update_owners()

	print("[MazePaths] Total: ", (Time.get_ticks_usec() - start_time) / 1000.0, " ms")
