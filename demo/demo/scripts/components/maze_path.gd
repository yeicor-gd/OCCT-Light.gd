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

@export var rope_physics := RopePhysics.new()

@export var sharpness := 5.0

@export_group("Actions")

@export_tool_button("Reset") var reset_ = _reset
@export_tool_button("Step") var step_ = func(): _step(1)
@export_tool_button("Step N") var step_n_ = func(): _step(rope_physics.iterations)
@export_tool_button("Generate") var generate_ = func(): await regenerate(false)

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
	return p.ball_radius / minf(p.ball_to_path_min_ratio.x, p.ball_to_path_min_ratio.y)

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------

func _reset():
	rope_physics.clear()
	curve.clear_points()

func _step(n: int):
	var self_task: Array[int] = [-1]
	self_task[0] = WorkerThreadPool.add_task(func():
		var start_time := Time.get_ticks_usec()
		if rope_physics.nodes.is_empty():
			rope_physics.inner_radius = _get_inner_radius() + _get_tube_margin()
			rope_physics.outer_radius = _get_outer_radius() - _get_tube_margin()
			rope_physics.collision_radius = 2.5 * _get_tube_margin() # Extra to avoid inter-node collisions as much as possible
			rope_physics.init_rope(_get_seed(), Vector3.BACK * (_get_outer_radius() - _get_tube_margin()), Vector3.FORWARD * (_get_outer_radius() - _get_tube_margin()))
		else:
			var old_iterations := rope_physics.iterations
			rope_physics.iterations = n
			rope_physics.relax()
			rope_physics.iterations = old_iterations
		var elapsed := (Time.get_ticks_usec() - start_time) / 1000.0
		print("MainPath::_step took ", elapsed, " ms for ", n, " steps")
		var data := CurveUtils.precompute_curve_data(rope_physics.get_positions(), sharpness)
		CurveUtils.apply_curve_data.call_deferred(curve, data)
		WorkerThreadPool.wait_for_task_completion.call_deferred(self_task[0])
	)

func regenerate(do_await: bool):
	_reset()
	var self_task: Array[int] = [-1]
	self_task[0] = WorkerThreadPool.add_task(func():
		var start_time := Time.get_ticks_usec()
		rope_physics.inner_radius = _get_inner_radius() + _get_tube_margin()
		rope_physics.outer_radius = _get_outer_radius() - _get_tube_margin()
		rope_physics.collision_radius = 2.5 * _get_tube_margin() # Extra to avoid inter-node collisions as much as possible
		rope_physics.init_rope(_get_seed(), Vector3.BACK * (_get_outer_radius() - _get_tube_margin()), Vector3.FORWARD * (_get_outer_radius() - _get_tube_margin()))
		rope_physics.relax()
		var elapsed := (Time.get_ticks_usec() - start_time) / 1000.0
		print("MainPath::_step took ", elapsed, " ms for ", rope_physics.iterations, " steps")
		var data := CurveUtils.precompute_curve_data(rope_physics.get_positions(), sharpness)
		CurveUtils.apply_curve_data.call_deferred(curve, data)
		if !do_await:
			WorkerThreadPool.wait_for_task_completion(self_task[0])
	)
	if do_await:
		while !WorkerThreadPool.is_task_completed(self_task[0]):
			await get_tree().create_timer(0.2).timeout
		WorkerThreadPool.wait_for_task_completion(self_task[0])


# -----------------------------------------------------------------------------
# Curve transforms (used externally by path followers and the OCL manager)
# -----------------------------------------------------------------------------

func transform_at_point(i: int) -> Transform3D:
	return CurveUtils.transform_at_index(curve, i)

func transform_at(baked_length: float, cubic_interp: bool = true) -> Transform3D:
	return CurveUtils.transform_at_baked(curve, baked_length, cubic_interp)
