@tool
extends Path3D
class_name MazePath

## A position-based-dynamics rope simulation that produces a space-filling curve
## inside a spherical shell, exposed as a Godot Path3D curve.
##
## The rope starts as a straight chord and relaxes under segment-length,
## shell-containment, radial-alignment-penalty, and self-repulsion constraints.
##
## All simulation logic is delegated to RopePhysics (scripts/helpers/).

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

@export_group("Rope")

## Number of nodes along the rope. More nodes = finer detail.
@export_range(2, 5000) var node_count: int = 100

## Rest length of each rope segment. The PBD spring attempts to keep
## consecutive nodes this far apart.
@export_range(0.001, 10.0) var segment_length: float = 0.5

## Curve sharpness. Higher values make the interpolated Catmull-Rom
## spline hug the node positions more tightly (lower = smoother / looser).
@export_range(0.5, 30.0) var sharpness: float = 5.0

@export_group("Solver")

## Number of PBD iterations. More iterations = stiffer constraint
## satisfaction but slower generation.
@export_range(1, 10000) var relaxation_iters: int = 2000

## How many adjacent nodes to skip during self-repulsion. 1 means
## neighbours are excluded; higher values let the repulsion range grow.
@export_range(0, 20) var repulsion_skip: int = 1

@export_subgroup("Strengths")

## Stiffness of the segment-length spring. Higher = segments snap
## faster to rest length.
@export_range(0.0, 10.0) var segment_strength: float = 0.5

## Stiffness of the shell-containment push. Higher = nodes hug the
## inner/outer boundary more tightly.
@export_range(0.0, 10.0) var shell_strength: float = 1.0

## How radial to be before [radial_penalty_strength] starts to apply.
@export_range(0.0, 1.0) var radial_penalty_threshold := 0.5

## Penalty strength for segments aligned with the radial direction.
## Higher = stronger push away from forming columns.
@export_range(0.0, 10.0) var radial_penalty_strength: float = 0.5

## Stiffness of the inter-node repulsion. Higher = nodes spread apart
## more aggressively.
@export_range(0.0, 10.0) var repulsion_strength: float = 0.5

## How far away nodes keep pushing each other.
@export_range(0.0, 10.0) var repulsion_influence: float = 4.0

## Random jitter applied every iteration to help the system escape
## symmetrical local minima. 0 = deterministic, 0.02 = mild, 0.1 = chaotic.
@export_range(0.0, 1.0, 0.001) var jitter_noise: float = 0.001

@export_group("Actions")

@export_tool_button("Reset") var reset_ = _reset
@export_tool_button("Step") var step_ = func(): _step(1)
@export_tool_button("Step N") var step_n_ = func(): _step(relaxation_iters)
@export_tool_button("Generate") var generate_ = func(): await regenerate(false)

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

var _rope: RopePhysics

# -----------------------------------------------------------------------------
# Private helpers
# -----------------------------------------------------------------------------

func _get_parent_generator():
	var p = get_parent()
	while p:
		if p is MazeGenerator:
			return p
		p = p.get_parent()
	return null

func _get_inner_radius() -> float:
	var p = _get_parent_generator()
	return p.maze_inner_radius

func _get_outer_radius() -> float:
	var p = _get_parent_generator()
	return p.maze_outer_radius

func _get_seed() -> int:
	var p = _get_parent_generator()
	return p.seed_value if p else 0

## Clearance margin derived from the parent MazeGenerator's ball size / fill ratio.
func _get_tube_margin() -> float:
	var p = _get_parent_generator()
	if p and p.ball_radius > 0 and p.ball_to_path_min_ratio > 0:
		return p.ball_radius / p.ball_to_path_min_ratio
	return 0.0

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------

func _reset():
	if _rope:
		_rope.clear()
	curve.clear_points()

func _step(n: int):
	if not _rope:
		_rope = RopePhysics.new()
	_sync_rope_config()
	var self_task: Array[int] = [-1]
	self_task[0] = WorkerThreadPool.add_task(func():
		if _rope.nodes.is_empty():
			_rope.init_rope(_get_seed(), _get_outer_radius(), _get_tube_margin())
		else:
			_rope.relaxation_iters = n
			_rope.relax(_get_inner_radius(), _get_outer_radius(), _get_tube_margin())
			_rope.relaxation_iters = relaxation_iters
		var data := CurveUtils.precompute_curve_data(_rope.get_positions(), sharpness)
		CurveUtils.apply_curve_data.call_deferred(curve, data)
		WorkerThreadPool.wait_for_task_completion.call_deferred(self_task[0])
	)

func regenerate(do_await: bool):
	_reset()
	if not _rope:
		_rope = RopePhysics.new()
	_sync_rope_config()
	var self_task: Array[int] = [-1]
	self_task[0] = WorkerThreadPool.add_task(func():
		_rope.init_rope(_get_seed(), _get_outer_radius(), _get_tube_margin())
		_rope.relax(_get_inner_radius(), _get_outer_radius(), _get_tube_margin())
		var data := CurveUtils.precompute_curve_data(_rope.get_positions(), sharpness)
		CurveUtils.apply_curve_data.call_deferred(curve, data)
		if !do_await:
			WorkerThreadPool.wait_for_task_completion(self_task[0])
	)
	if do_await:
		while !WorkerThreadPool.is_task_completed(self_task[0]):
			await get_tree().create_timer(0.2).timeout
		WorkerThreadPool.wait_for_task_completion(self_task[0])

func _sync_rope_config():
	_rope.node_count = node_count
	_rope.segment_length = segment_length
	_rope.sharpness = sharpness
	_rope.relaxation_iters = relaxation_iters
	_rope.repulsion_skip = repulsion_skip
	_rope.segment_strength = segment_strength
	_rope.shell_strength = shell_strength
	_rope.radial_penalty_threshold = radial_penalty_threshold
	_rope.radial_penalty_strength = radial_penalty_strength
	_rope.repulsion_strength = repulsion_strength
	_rope.repulsion_influence = repulsion_influence
	_rope.jitter_noise = jitter_noise

# -----------------------------------------------------------------------------
# Curve transforms (used externally by path followers and the OCL manager)
# -----------------------------------------------------------------------------

func transform_at_point(i: int) -> Transform3D:
	return CurveUtils.transform_at_index(curve, i)

func transform_at(baked_length: float, cubic_interp: bool = true) -> Transform3D:
	return CurveUtils.transform_at_baked(curve, baked_length, cubic_interp)
