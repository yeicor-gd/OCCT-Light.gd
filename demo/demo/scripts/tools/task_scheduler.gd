@tool
class_name TaskScheduler
extends RefCounted

## Dispatches chunks to WorkerThreadPool and collects results on the main thread.
##
## Each worker builds and meshes a chunk, then submits its result via
## submit_result() before returning.  The main thread calls reap_completed()
## and collect_all() each frame to drain ready results without ever blocking
## or busy-waiting.
##
## Usage:
##   var sched := TaskScheduler.new()
##   sched.dispatch_task(func():
##       var result := _do_work()
##       sched.submit_result(result)
##   )
##   while sched.is_busy():
##       sched.reap_completed()
##       for r in sched.collect_all():
##           _apply(r)
##       await get_tree().process_frame
##   for r in sched.collect_all():
##       _apply(r)
##
## Concurrency throttling:
##   Set max_concurrent to limit how many tasks run simultaneously on
##   WorkerThreadPool.  This is useful when the worker callable calls into
##   libraries (e.g. OCCT) that are NOT thread-safe — set max_concurrent=1
##   to serialise OCCT access while keeping the main thread responsive.
##   0 (default) = unlimited (let the threadpool manage parallelism).
##
## Thread safety:
##   - Mutex guards _result_queue across the worker/main-thread boundary.
##   - _pending_ids, _pending_count and _total_remaining are only touched
##     on the main thread (dispatch_task, reap_completed, drain queue);
##     no mutex needed, but held for consistency.

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

var _mutex: Mutex
var _result_queue: Array[Variant] = []

## Task IDs dispatched to WorkerThreadPool but not yet reaped as completed.
var _pending_ids: Array[int] = []
var _pending_count: int = 0

## Total tasks that have not yet been fully consumed (in-flight + queued).
var _total_remaining: int = 0

## Concurrency throttle.
var _max_concurrent: int = 0

## Tasks waiting to be dispatched (only used when _max_concurrent > 0).
var _queued: Array[Dictionary] = []

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

## Maximum number of tasks that may run simultaneously on WorkerThreadPool.
##
##  0  = unlimited (default)
##  1  = serialised — useful for diagnosing non-thread-safe libraries
##  N  = at most N tasks in flight at any time
var max_concurrent: int:
	get:
		return _max_concurrent
	set(v):
		_max_concurrent = maxi(0, v)

# -----------------------------------------------------------------------------
# Initialisation
# -----------------------------------------------------------------------------

func _init():
	_mutex = Mutex.new()

# -----------------------------------------------------------------------------
# Dispatch
# -----------------------------------------------------------------------------

## Dispatches |action| as a WorkerThreadPool background task.
##
## The callable MUST call submit_result() as its final statement so that
## the result is available to the main thread when the task completes.
##
## If max_concurrent > 0 and the limit is already reached, the task is
## queued and dispatched later (from reap_completed).  In that case the
## return value is -1 (no task ID yet).
##
## Returns the WorkerThreadPool task ID, or -1 if queued.
func dispatch_task(action: Callable, high_priority: bool = false, description: String = "") -> int:
	if _max_concurrent > 0:
		# Check if we're at capacity — use a snapshot of _pending_count
		# (safe because both dispatch_task and reap_completed run on the
		#  main thread, so the count can't change between the check and
		#  the queuing decision).
		if _pending_count >= _max_concurrent:
			_queued.append({
				"action": action,
				"high_priority": high_priority,
				"description": description,
			})
			_total_remaining += 1
			return -1

	return _dispatch_now(action, high_priority, description)

## Actually submits a task to WorkerThreadPool and records the ID.
func _dispatch_now(action: Callable, high_priority: bool, description: String) -> int:
	var tid := WorkerThreadPool.add_task(action, high_priority, description)
	_pending_ids.append(tid)
	_pending_count += 1
	_total_remaining += 1
	return tid

# -----------------------------------------------------------------------------
# Submission (worker thread)
# -----------------------------------------------------------------------------

## Called by worker threads to enqueue a result.
##
## Thread-safe (Mutex-protected).  Must be the last call in the worker
## callable so that the result is visible before is_task_completed()
## reports completion.
func submit_result(result: Variant) -> void:
	_mutex.lock()
	_result_queue.append(result)
	_mutex.unlock()

# -----------------------------------------------------------------------------
# Collection (main thread)
# -----------------------------------------------------------------------------

## Drains and returns all currently queued results (non-blocking).
func collect_all() -> Array[Variant]:
	var batch: Array[Variant] = []
	_mutex.lock()
	while not _result_queue.is_empty():
		batch.append(_result_queue.pop_front())
	_mutex.unlock()
	return batch

## Checks which pending tasks have completed (via
## WorkerThreadPool.is_task_completed) and removes them from the
## pending list.  Also dispatches queued tasks when concurrency slots
## open up.
##
## Returns the number of tasks reaped this call.
##
## Call this once per frame before collect_all() to keep is_busy()
## accurate.
func reap_completed() -> int:
	var reaped := 0
	var i := 0
	while i < _pending_ids.size():
		if WorkerThreadPool.is_task_completed(_pending_ids[i]):
			_pending_ids.remove_at(i)
			_pending_count -= 1
			_total_remaining -= 1
			reaped += 1
		else:
			i += 1

	# Drain the queue now that slots may be available.
	if _max_concurrent > 0 and not _queued.is_empty():
		_drain_queue()

	return reaped

## Dispatches queued tasks up to the concurrency limit.
func _drain_queue() -> void:
	while _pending_count < _max_concurrent and not _queued.is_empty():
		var entry: Dictionary = _queued.pop_front()
		# _total_remaining already accounts for this entry; _dispatch_now
		# increments _pending_count and _total_remaining again, which
		# would double-count.  Undo the queued increment.
		_total_remaining -= 1
		_dispatch_now(
			entry["action"] as Callable,
			entry["high_priority"] as bool,
			entry["description"] as String,
		)

## Returns true while any dispatched task has not yet been reaped as
## completed, or while tasks remain queued.
func is_busy() -> bool:
	return _total_remaining > 0

## Number of tasks currently dispatched to WorkerThreadPool and not yet
## reaped as completed.
func pending_count() -> int:
	return _pending_count

## Number of tasks queued (waiting for a concurrency slot).
func queued_count() -> int:
	return _queued.size()
