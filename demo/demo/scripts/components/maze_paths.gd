@tool
extends Node3D
class_name MazePaths

## Manages all path curves: the main rope-simulated path, auxiliary
## binormal curves for sweep orientation, and configurable shortcut /
## longcut paths that connect non-adjacent regions of the maze.
##
## Shortcuts are simulated as additional ropes in the same physics system,
## sharing the shell, self-collision, and bending constraints with the main
## path.  The only hard constraint is fixed start/end anchor points.
##
## All generated Path3D children are added directly to this node.
## When [member store_as_nodes] is true they are assigned an owner so they
## appear in the Godot editor scene tree; otherwise they are invisible to
## the editor but still usable at runtime.

# -----------------------------------------------------------------------------
# Main path configuration
# -----------------------------------------------------------------------------

@export var rope_physics := OclDemoOnlyRopePhysics.new()
@export var sharpness := 5.0

## Lateral offset applied when building auxiliary (binormal) curves.
@export var aux_offset_amount: float = 0.15

# -----------------------------------------------------------------------------
# Shortcut / longcut configuration (seeded-RNG parametric)
# -----------------------------------------------------------------------------

@export_group("Shortcuts")

## Number of shortcuts to generate (0 = none, 1–5 typical).
@export_range(0, 10, 1) var total_shortcuts: int = 3

## Probability distribution for shortcut start position (0–1 along main path).
## X = normalised main-path position, Y = relative probability weight.
@export var target_shortcut_start: Curve

## Probability distribution for shortcut end position (0–1 along main path).
## X = normalised main-path position, Y = relative probability weight.
@export var target_shortcut_end: Curve

## Probability distribution for how much of the main path a shortcut covers
## (end − start).  X = normalised main-path fraction, Y = probability weight.
@export var target_main_path_length: Curve

## Probability distribution for shortcut arc length (normalised 0–1 of main path).
## X = normalised shortcut length, Y = relative probability weight.
@export var target_shortcut_length: Curve

# -----------------------------------------------------------------------------
# Editor visibility
# -----------------------------------------------------------------------------

@export_group("Editor")

## When true, generated Path3D children are assigned the scene root as owner
## so they appear in the Godot editor scene tree.  When false they are added
## as children but stay hidden from the editor.
@export var store_as_nodes: bool = false

# -----------------------------------------------------------------------------
# Actions
# -----------------------------------------------------------------------------

@export_group("Actions")

@export_tool_button("Reset") var reset_ = func(): step(0)
@export_tool_button("Step") var step_ = func(): step(1)
@export_tool_button("Regenerate") var regenerate_ = func(): regenerate(false)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _scene_root() -> Node:
	if is_inside_tree():
		return get_tree().edited_scene_root
	var n: Node = get_parent()
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

# ---------------------------------------------------------------------------
# Seeded RNG helpers
# ---------------------------------------------------------------------------

## Create a deterministic RandomNumberGenerator seeded from the maze seed
## plus an optional extra salt (for independent streams per shortcut index).
func _make_rng(extra_salt: int = 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_get_seed() + extra_salt)
	return rng


## Sample from a probability distribution Curve using inverse-CDF sampling.
## Returns a value in [0, 1] shaped by the curve's weight profile.
func _sample_curve_pdf(curve: Curve, rng: RandomNumberGenerator, steps: int = 64) -> float:
	if curve == null or curve.point_count < 2:
		return rng.randf()

	var cdf: PackedFloat64Array = PackedFloat64Array()
	cdf.resize(steps + 1)
	var total := 0.0
	cdf[0] = 0.0
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var w := maxf(curve.sample(t), 0.0)
		total += w
		cdf[i] = total

	if total < 1e-12:
		return rng.randf()

	for i in range(cdf.size()):
		cdf[i] /= total

	var u := rng.randf()
	for i in range(1, cdf.size()):
		if cdf[i] >= u:
			var t_prev := float(i - 1) / float(steps)
			var t_curr := float(i) / float(steps)
			var blend := (u - cdf[i - 1]) / maxf(cdf[i] - cdf[i - 1], 1e-12)
			return lerpf(t_prev, t_curr, blend)

	return 1.0

# ---------------------------------------------------------------------------
# Phase 1: Init main rope (no relax — shortcuts added next)
# ---------------------------------------------------------------------------

func _init_main_rope(sync: bool) -> void:
	rope_physics.clear()

	var inner_r := _get_inner_radius() + _get_tube_margin()
	var outer_r := _get_outer_radius() - _get_tube_margin()
	var collision_r := 3.0 * _get_tube_margin()
	var seed_val := _get_seed()

	rope_physics.inner_radius = inner_r
	rope_physics.outer_radius = outer_r
	rope_physics.collision_radius = collision_r
	rope_physics.init_rope(
		seed_val,
		Vector3.BACK * outer_r,
		Vector3.FORWARD * outer_r,
	)

# ---------------------------------------------------------------------------
# Phase 2: Add shortcuts to rope physics (main thread, fast)
# ---------------------------------------------------------------------------

func _generate_shortcuts() -> void:
	if total_shortcuts <= 0:
		return

	# We need a temporary curve to sample positions for chord-length estimation.
	# Build it from the current main rope positions.
	var main_positions := rope_physics.get_rope_positions(0)
	if main_positions.size() < 2:
		return

	var tmp_curve := Curve3D.new()
	for p in main_positions:
		tmp_curve.add_point(p)
	var baked_len := tmp_curve.get_baked_length()

	for i in range(total_shortcuts):
		var rng := _make_rng(i * 7919)

		var start_frac := _sample_curve_pdf(target_shortcut_start, rng)
		var main_path_frac := _sample_curve_pdf(target_main_path_length, rng)
		var end_frac := clampf(start_frac + main_path_frac, start_frac + 0.05, 1.0)

		var anchor_start := rope_physics.find_main_node_at_fraction(start_frac)
		var anchor_end := rope_physics.find_main_node_at_fraction(end_frac)

		# Shortcut arc length (how long the shortcut rope actually is).
		var shortcut_frac := _sample_curve_pdf(target_shortcut_length, rng)
		var shortcut_arc_len := shortcut_frac * baked_len
		var start_pos := tmp_curve.sample_baked(start_frac * baked_len)
		var end_pos := tmp_curve.sample_baked(end_frac * baked_len)
		var chord := start_pos.distance_to(end_pos)
		var segments := maxi(3, roundi(shortcut_arc_len / rope_physics.segment_length))

		rope_physics.add_shortcut(anchor_start, anchor_end, segments)

# ---------------------------------------------------------------------------
# Phase 3: Relax all ropes together
# ---------------------------------------------------------------------------

func _relax_all_ropes(sync: bool) -> void:
	if sync:
		rope_physics.relax()
	else:
		var self_task: Array[int] = [-1]
		self_task[0] = WorkerThreadPool.add_task(func():
			rope_physics.relax()
		)
		while !WorkerThreadPool.is_task_completed(self_task[0]):
			await get_tree().create_timer(0.2).timeout
		var res := WorkerThreadPool.wait_for_task_completion(self_task[0])
		assert(res == OK)

# ---------------------------------------------------------------------------
# Phase 4: Build Path3D curves from rope positions
# ---------------------------------------------------------------------------

func _build_all_curves() -> void:
	var rope_count := rope_physics.get_rope_count()
	if rope_count == 0:
		return

	# Main path (rope 0).
	var main_path := _ensure_curve_child("MainPath")
	var main_positions := rope_physics.get_rope_positions(0)
	CurveUtils.apply_curve_data(main_path.curve, CurveUtils.precompute_curve_data(main_positions, sharpness))

	# Main path binormal.
	_regenerate_aux_curve(main_path, "MainPathBinormal", aux_offset_amount)

	# Shortcuts (ropes 1..N).
	for i in range(1, rope_count):
		var idx := i - 1
		var sc_positions := rope_physics.get_rope_positions(i)
		if sc_positions.size() < 2:
			continue

		var sc_path := _ensure_curve_child("Shortcut%d" % idx)
		CurveUtils.apply_curve_data(sc_path.curve, CurveUtils.precompute_curve_data(sc_positions, sharpness))

		var aux_path := _ensure_curve_child("Shortcut%dBinormal" % idx)
		aux_path.curve = CurveUtils.build_auxiliary_curve(sc_path.curve, aux_offset_amount)

# ---------------------------------------------------------------------------
# Auxiliary curve generation
# ---------------------------------------------------------------------------

func _regenerate_aux_curve(source: Path3D, curve_name: String, offset: float) -> Path3D:
	var path := _ensure_curve_child(curve_name)
	path.curve = CurveUtils.build_auxiliary_curve(source.curve, offset)
	return path

func step(n: int):
	if n == 0:
		_clear_shortcut_children()
		_init_main_rope(false)
		_generate_shortcuts()
		_build_all_curves()
		_update_owners()
	else:
		var old_iterations = rope_physics.iterations
		rope_physics.iterations = n
		await _relax_all_ropes(false)
		rope_physics.iterations = old_iterations
		_build_all_curves()
		_update_owners()

# ---------------------------------------------------------------------------
# Public regenerate
# ---------------------------------------------------------------------------

func regenerate(sync: bool) -> void:
	var start_time := Time.get_ticks_usec()

	# 1. Clear old shortcut children.
	_clear_shortcut_children()

	# 2. Init main rope (no relax yet).
	_init_main_rope(sync)

	# 3. Add shortcuts to rope physics.
	_generate_shortcuts()

	# 4. Relax all ropes together (main + shortcuts).
	var relax_start := Time.get_ticks_usec()
	await _relax_all_ropes(sync)
	print("[MazePaths] Rope relax took ", (Time.get_ticks_usec() - relax_start) / 1000.0, " ms")

	# 5. Build Path3D curves from rope positions.
	_build_all_curves()

	# 6. Optionally update owner so children appear in the editor.
	_update_owners()

	print("[MazePaths] All paths generated in ", (Time.get_ticks_usec() - start_time) / 1000.0, " ms")

# ---------------------------------------------------------------------------
# Owner management for editor visibility
# ---------------------------------------------------------------------------

func _update_owners() -> void:
	var root := _scene_root() if Engine.is_editor_hint() else null
	for child in get_children():
		if child is Path3D:
			if store_as_nodes and root:
				child.set_owner(root)
			else:
				child.set_owner(self)

# ---------------------------------------------------------------------------
# Shortcut children cleanup
# ---------------------------------------------------------------------------

func _clear_shortcut_children() -> void:
	var to_remove: Array[Node] = []
	for child in get_children():
		if child is Path3D and str(child.name).begins_with("Shortcut"):
			to_remove.append(child)
	for n in to_remove:
		remove_child(n)
		n.queue_free()
