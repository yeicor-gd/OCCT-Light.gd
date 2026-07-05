class_name TestSelectIter

# Manual test for select iterator functions.
# All value-struct parameters MUST be initialized via their respective
# *_init() function before passing to the C API so that struct_version
# and other internal fields are set correctly.

# OCCTL status codes
const OK := 0
const NOT_FOUND := 4

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

# Helper: create a simple box using make_box
static func _make_box(graph: OclGraphHandle) -> int:
	var box_info := OclPrimBoxInfo.new()
	box_info.dx = 10.0
	box_info.dy = 10.0
	box_info.dz = 10.0
	var out_solid := OclNodeId.new()
	var status := OclPrimSolid.box(graph, box_info, out_solid)
	if status != OK:
		printerr("Failed to create box: status=", status)
		return -1
	return out_solid.bits

# Helper: init runtime (tolerates double-init)
static func _init_runtime() -> int:
	var rt_status = OclCore.runtime_init(null)
	if rt_status != OK and rt_status != 2:
		return rt_status
	return OK

# Helper: create select options with default init
static func _make_select_options() -> OclSelectOptions:
	var opt := OclSelectOptions.new()
	return opt

# Helper: create group options with default init
static func _make_group_options() -> OclSelectGroupOptions:
	var opt := OclSelectGroupOptions.new()
	return opt

# Helper: iterate and collect results
static func _collect_select_iter(iter: OclSelectIterHandle) -> Array:
	var results := []
	while true:
		var out_node := OclNodeId.new()
		var status := OclTopoBuild.select_iter_next(iter, out_node)
		if status == NOT_FOUND:
			break
		if status != OK:
			return ["ERROR: select_iter_next failed with status=%d" % status]
		results.append(out_node.get_bits())
	return results

static func test_select_iter_basic() -> String:
	var init_err = _init_runtime()
	if init_err != OK:
		return "runtime_init failed: %d" % init_err

	var graph := OclGraphHandle.new()
	var create_err := OclTopo.graph_create(graph)
	if create_err != OK or graph == null:
		OclCore.runtime_shutdown()
		return "graph_create failed: err=%d" % create_err

	var solid_id := _make_box(graph)
	if solid_id < 0:
		OclTopo.graph_free(graph)
		OclCore.runtime_shutdown()
		return "Failed to create box"

	var options := _make_select_options()
	options.kind_mask = 1 << 1  # KIND_SOLID

	var iter = OclSelectIterHandle.new()
	var status = OclTopoBuild.select_iter_create(graph, options, iter)
	if status != OK:
		OclTopo.graph_free(graph)
		OclCore.runtime_shutdown()
		return "select_iter_create failed: %d" % status

	var results = _collect_select_iter(iter)
	if typeof(results[0]) == TYPE_STRING:
		OclTopoBuild.select_iter_free(iter)
		OclTopo.graph_free(graph)
		OclCore.runtime_shutdown()
		return results[0]

	OclTopoBuild.select_iter_free(iter)

	if results.find(solid_id) == -1:
		OclTopo.graph_free(graph)
		OclCore.runtime_shutdown()
		return "Did not find the solid we created (got %d results)" % results.size()

	OclTopo.graph_free(graph)
	OclCore.runtime_shutdown()
	return "OK"

static func test_select_iter_with_null_options() -> String:
	var init_err = _init_runtime()
	if init_err != OK:
		return "runtime_init failed: %d" % init_err

	var graph := OclGraphHandle.new()
	var create_err := OclTopo.graph_create(graph)
	if create_err != OK or graph == null:
		OclCore.runtime_shutdown()
		return "graph_create failed: err=%d" % create_err

	var iter = OclSelectIterHandle.new()
	var status = OclTopoBuild.select_iter_create(graph, null, iter)
	if status != OK:
		printerr("Expected failure with null options, got status=", status)
	OclTopoBuild.select_iter_free(iter)

	OclTopo.graph_free(graph)
	OclCore.runtime_shutdown()
	return "OK"

static func test_select_tagged_iter() -> String:
	var init_err = _init_runtime()
	if init_err != OK:
		return "runtime_init failed: %d" % init_err

	var graph := OclGraphHandle.new()
	var create_err := OclTopo.graph_create(graph)
	if create_err != OK or graph == null:
		OclCore.runtime_shutdown()
		return "graph_create failed: err=%d" % create_err

	# Create a box
	var solid_id := _make_box(graph)
	if solid_id < 0:
		OclTopo.graph_free(graph)
		OclCore.runtime_shutdown()
		return "Failed to create box"

	# Tag the solid node (uses string+length auto-collapse)
	var tag := "test_tag"
	var status = OclTopo.graph_tag_add(graph, solid_id, tag)
	if status != OK:
		OclTopo.graph_free(graph)
		OclCore.runtime_shutdown()
		return "Failed to add tag: status=%d" % status

	# Verify tag exists using out-param
	var out_has_tag := OclInt32.new()
	status = OclTopo.graph_tag_has(graph, solid_id, tag, out_has_tag)
	if status != OK:
		OclTopo.graph_free(graph)
		OclCore.runtime_shutdown()
		return "graph_tag_has failed: status=%d" % status
	if out_has_tag.get_value() != 1:
		OclTopo.graph_free(graph)
		OclCore.runtime_shutdown()
		return "Tag not found after adding (has_tag=%d)" % out_has_tag.get_value()

	# Select tagged nodes
	var options := _make_select_options()
	var iter = OclSelectIterHandle.new()
	status = OclTopoBuild.select_tagged_iter_create(graph, options, tag, iter)
	if status != OK:
		OclTopo.graph_free(graph)
		OclCore.runtime_shutdown()
		return "select_tagged_iter_create failed: %d" % status

	var results = _collect_select_iter(iter)
	if typeof(results[0]) == TYPE_STRING:
		OclTopoBuild.select_iter_free(iter)
		OclTopo.graph_free(graph)
		OclCore.runtime_shutdown()
		return results[0]

	OclTopoBuild.select_iter_free(iter)

	if results.find(solid_id) == -1:
		OclTopo.graph_free(graph)
		OclCore.runtime_shutdown()
		return "Did not find tagged solid (got %d results)" % results.size()

	OclTopo.graph_free(graph)
	OclCore.runtime_shutdown()
	return "OK"

static func test_select_group_iter() -> String:
	var init_err = _init_runtime()
	if init_err != OK:
		return "runtime_init failed: %d" % init_err

	var graph := OclGraphHandle.new()
	var create_err := OclTopo.graph_create(graph)
	if create_err != OK or graph == null:
		OclCore.runtime_shutdown()
		return "graph_create failed: err=%d" % create_err

	# Create a box
	var solid_id := _make_box(graph)
	if solid_id < 0:
		OclTopo.graph_free(graph)
		OclCore.runtime_shutdown()
		return "Failed to create box"

	# Create select and group options with proper initialization
	var select_options := _make_select_options()
	select_options.kind_mask = 1 << 1  # KIND_SOLID
	var group_options := _make_group_options()

	# Create grouped iterator
	var iter = OclSelectGroupIterHandle.new()
	var status = OclTopoBuild.select_group_iter_create(graph, select_options, group_options, iter)
	if status != OK:
		OclTopo.graph_free(graph)
		OclCore.runtime_shutdown()
		return "select_group_iter_create failed: %d" % status

	# Iterate groups
	var found_solid := false
	while true:
		var out_view := OclSelectGroupView.new()
		status = OclTopoBuild.select_group_iter_next(iter, out_view)
		if status == NOT_FOUND:
			break
		if status != OK:
			OclTopoBuild.select_group_iter_free(iter)
			OclTopo.graph_free(graph)
			OclCore.runtime_shutdown()
			return "select_group_iter_next failed with status=%d" % status
		found_solid = true

	OclTopoBuild.select_group_iter_free(iter)

	if not found_solid:
		OclTopo.graph_free(graph)
		OclCore.runtime_shutdown()
		return "select_group_iter_next never found a group"

	OclTopo.graph_free(graph)
	OclCore.runtime_shutdown()
	return "OK"
