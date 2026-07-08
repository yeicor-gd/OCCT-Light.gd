@tool
class_name TaskScheduler
extends RefCounted

## Dispatches OCCT mesh-building work to Godot's WorkerThreadPool and
## collects results on the main thread via call_deferred.
##
## This decouples parallelism management from the mesh builder itself, making
## it easy to adjust thread count, prioritisation, and task ordering without
## touching OclMeshBuilder.
##
## Usage sketch (future, in OclMeshBuilder):
##   var scheduler := TaskScheduler.new()
##   scheduler.concurrent_tasks = 4
##   scheduler.dispatch_segments(path, aux_curve, profile_cfg)
##   # ... on main thread, collect results:
##   while scheduler.has_pending():
##       var result = scheduler.collect_next()
##       if result: _append_graph_faces(result.graph, $Faces.mesh)
##       await get_tree().process_frame
##
## TODO: Replace OclMeshBuilder.regenerate()'s sequential loop with a
##       scheduler-driven pipeline. Each task builds+meshes one segment (or
##       chunk) graph, then calls deferrred to append results.

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

## Maximum number of WorkerThreadPool tasks running simultaneously.
## 0 = let WorkerThreadPool decide (recommended).
var max_concurrent: int = 0

## Whether to wait for all tasks to finish before returning from dispatch().
## If false, the caller must poll has_pending() / collect_next().
var block_on_dispatch: bool = true

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

var _pending_results: Array[Callable] = []
var _task_ids: Array[int] = []

# -----------------------------------------------------------------------------
# Dispatch
# -----------------------------------------------------------------------------

## Dispatches a single callable as a background task.
## Returns the task ID.
func dispatch_task(task: Callable) -> int:
	var id := WorkerThreadPool.add_task(task, true, "OclMeshTask")
	_task_ids.append(id)
	return id


## Dispatches a group of callables (one per segment/chunk).
func dispatch_group(tasks: Array[Callable]):
	for t in tasks:
		dispatch_task(t)

	if block_on_dispatch:
		_await_all()


## Schedule a result for collection on the main thread.
## Call this from within a background task via call_deferred.
func submit_result(result_handler: Callable):
	_pending_results.append(result_handler)


# -----------------------------------------------------------------------------
# Collection
# -----------------------------------------------------------------------------

func has_pending() -> bool:
	return not _pending_results.is_empty()


## Process one pending result handler. Returns false if nothing pending.
func collect_next() -> bool:
	if _pending_results.is_empty():
		return false
	_pending_results.pop_front().call()
	return true


## Process all pending results immediately.
func drain_all():
	while collect_next():
		pass


# -----------------------------------------------------------------------------
# Await
# -----------------------------------------------------------------------------

## Block until all dispatched tasks complete.
func _await_all():
	for id in _task_ids:
		WorkerThreadPool.wait_for_task_completion(id)
	_task_ids.clear()


## Wait for all tasks and then drain results.
func wait_and_drain():
	_await_all()
	drain_all()
