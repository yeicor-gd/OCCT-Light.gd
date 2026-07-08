@tool
class_name GraphUtils
extends RefCounted

## Utilities for OCCT graph lifecycle, inspection, and validation.


## Create a fresh graph, asserting success.
static func create_graph() -> OclGraphHandle:
	var graph := OclGraphHandle.new()
	var status := OclTopo.graph_create(graph) as OclCore.status
	assert(
		status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())],
	)
	return graph


## Print the count of a specific node kind in a graph.
static func print_node_kind_count(
		graph: OclGraphHandle,
		node_kind: OclCore.node_kind,
		hint: String = "",
):
	var res := OclSize.new()
	var status: OclCore.status

	match node_kind:
		OclCore.KIND_SOLID:
			status = OclTopo.graph_solid_count(graph, res)
		OclCore.KIND_SHELL:
			status = OclTopo.graph_shell_count(graph, res)
		OclCore.KIND_FACE:
			status = OclTopo.graph_face_count(graph, res)
		OclCore.KIND_WIRE:
			status = OclTopo.graph_wire_count(graph, res)
		OclCore.KIND_EDGE:
			status = OclTopo.graph_edge_count(graph, res)
		OclCore.KIND_VERTEX:
			status = OclTopo.graph_vertex_count(graph, res)
		OclCore.KIND_COMPOUND:
			status = OclTopo.graph_compound_count(graph, res)
		OclCore.KIND_COMPSOLID:
			status = OclTopo.graph_compsolid_count(graph, res)
		OclCore.KIND_COEDGE:
			status = OclTopo.graph_coedge_count(graph, res)
		OclCore.KIND_PRODUCT:
			status = OclTopo.graph_product_count(graph, res)
		OclCore.KIND_OCCURRENCE:
			status = OclTopo.graph_occurrence_count(graph, res)
		OclCore.KIND_INVALID:
			push_error("KIND_INVALID is not a valid node kind to count")
			return
		_:
			push_error("Unknown node kind: %d" % node_kind)
			return

	assert(
		status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())],
	)

	print("Graph has ", res.value, " ", OclCore.node_kind_to_string(node_kind), " nodes (", hint, ")")


## Run topo check and assert no issues.
static func check_graph(graph: OclGraphHandle):
	var issues := OclTopoCheckIssueArray.new()
	var status := OclTopoAlgo.check(graph, issues) as OclCore.status
	assert(
		status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())],
	)
	var issues_str := ""
	for issue_ in issues.data:
		var issue: OclTopoCheckIssue = issue_
		var severity := OclTopoAlgo.check_severity_to_string(issue.severity)
		if issues_str.is_empty():
			issues_str = "Found some issues with the graph:\n"
		issues_str += " - [%s] Per-severity status bit: %d -- Node ID: %d (context: %d)\n" % [
			severity, issue.status_bit, issue.node_id, issue.context_node_id,
		]
	if not issues_str.is_empty():
		assert(false, issues_str)
