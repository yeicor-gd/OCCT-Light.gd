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
static func print_node_kind_of(
		graph: OclGraphHandle,
		node_id: OclNodeId,
		hint: String = "",
):
	var out := OclInt32.new()
	var status := OclTopo.graph_node_kind(graph, node_id.bits, out) as OclCore.status
	assert(
		status == OclCore.OK,
		"Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())],
	)
	print("Node ID ", node_id.bits, " is of kind ", OclCore.node_kind_to_string(out.value), " [", hint, "]")

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
			status = OclTopo.graph_solid_count(graph, res) as OclCore.status
		OclCore.KIND_SHELL:
			status = OclTopo.graph_shell_count(graph, res) as OclCore.status
		OclCore.KIND_FACE:
			status = OclTopo.graph_face_count(graph, res) as OclCore.status
		OclCore.KIND_WIRE:
			status = OclTopo.graph_wire_count(graph, res) as OclCore.status
		OclCore.KIND_EDGE:
			status = OclTopo.graph_edge_count(graph, res) as OclCore.status
		OclCore.KIND_VERTEX:
			status = OclTopo.graph_vertex_count(graph, res) as OclCore.status
		OclCore.KIND_COMPOUND:
			status = OclTopo.graph_compound_count(graph, res) as OclCore.status
		OclCore.KIND_COMPSOLID:
			status = OclTopo.graph_compsolid_count(graph, res) as OclCore.status
		OclCore.KIND_COEDGE:
			status = OclTopo.graph_coedge_count(graph, res) as OclCore.status
		OclCore.KIND_PRODUCT:
			status = OclTopo.graph_product_count(graph, res) as OclCore.status
		OclCore.KIND_OCCURRENCE:
			status = OclTopo.graph_occurrence_count(graph, res) as OclCore.status
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

static func _iter_ids(iter: OclNodeIterHandle) -> Array[int]:
	var ids: Array[int] = []

	var id := OclNodeId.new()

	while true:
		var st := OclTopo.node_iter_next(iter, id) as OclCore.status

		if st == OclCore.NOT_FOUND:
			break

		assert(
			st == OclCore.OK,
			"Got status %s - %s" % [
				OclCore.status_to_string(st),
				var_to_str(OclCore.error_last())
			]
		)

		ids.append(id.bits)

	OclTopo.node_iter_free(iter)

	return ids

# Helper: collect node ids of a given kind from a graph
static func _collect_ids(graph: OclGraphHandle, kind: int) -> Array[int]:
	var out_iter := OclNodeIterHandle.new()
	var status: OclCore.status
	match kind:
		OclCore.KIND_SOLID:
			status = OclTopo.graph_solid_iter_create(graph, out_iter) as OclCore.status
		OclCore.KIND_SHELL:
			status = OclTopo.graph_shell_iter_create(graph, out_iter) as OclCore.status
		OclCore.KIND_FACE:
			status = OclTopo.graph_face_iter_create(graph, out_iter) as OclCore.status
		OclCore.KIND_WIRE:
			status = OclTopo.graph_wire_iter_create(graph, out_iter) as OclCore.status
		OclCore.KIND_EDGE:
			status = OclTopo.graph_edge_iter_create(graph, out_iter) as OclCore.status
		OclCore.KIND_VERTEX:
			status = OclTopo.graph_vertex_iter_create(graph, out_iter) as OclCore.status
		OclCore.KIND_COMPOUND:
			status = OclTopo.graph_compound_iter_create(graph, out_iter) as OclCore.status
		OclCore.KIND_COMPSOLID:
			status = OclTopo.graph_compsolid_iter_create(graph, out_iter) as OclCore.status
		OclCore.KIND_COEDGE:
			status = OclTopo.graph_coedge_iter_create(graph, out_iter) as OclCore.status
		_:
			return []
	assert(status == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(status), var_to_str(OclCore.error_last())])
	return _iter_ids(out_iter)

static func _collect_iter(status: OclCore.status, iter: OclNodeIterHandle) -> Array[int]:
	assert(
		status == OclCore.OK,
		"Got status %s - %s" % [
			OclCore.status_to_string(status),
			var_to_str(OclCore.error_last())
		]
	)
	return _iter_ids(iter)

static func dump_graph_tree(graph: OclGraphHandle):
	print("\n=========== GRAPH ===========")

	var visited := {
		"solid": {},
		"shell": {},
		"face": {},
		"wire": {},
		"coedge": {},
		"edge": {},
		"vertex": {},
	}

	var iter := OclNodeIterHandle.new()

	var solids := _collect_iter(
		OclTopo.graph_solid_iter_create(graph, iter) as OclCore.status,
		iter
	)

	for solid in solids:
		_dump_solid(graph, solid, "", visited)

	_dump_orphans(graph, visited)

	print("=============================\n")
	
static func _dump_solid(graph, solid:int, indent:String, visited:Dictionary, do_print: bool = true):

	visited.solid[solid] = true

	if do_print:
		print(indent, "Solid ", solid)

	var iter := OclNodeIterHandle.new()

	var shells := _collect_iter(
		OclTopo.topo_shells_of_solid_iter_create(
			graph,
			solid,
			iter
		) as OclCore.status,
		iter
	)

	for shell in shells:
		_dump_shell(graph, shell, indent + "  ", visited, do_print)
		
static func _dump_shell(graph, shell:int, indent:String, visited, do_print: bool = true):

	visited.shell[shell] = true

	if do_print:
		print(indent, "Shell ", shell)

	var iter := OclNodeIterHandle.new()

	var faces := _collect_iter(
		OclTopo.topo_faces_of_shell_iter_create(
			graph,
			shell,
			iter
		) as OclCore.status,
		iter
	)

	for face in faces:
		_dump_face(graph, face, indent + "  ", visited, do_print)
		
static func _dump_face(graph, face:int, indent:String, visited, do_print: bool = true):

	visited.face[face] = true

	var outer := OclNodeId.new()

	var st := OclTopo.topo_face_outer_wire(
		graph,
		face,
		outer
	) as OclCore.status

	if st != OclCore.OK:
		if do_print:
			print(indent, "Face ", face, " (no outer wire - ", OclCore.status_to_string(st), ")")
		outer.bits = 0  # Continue traversing wires even without a valid outer wire.

	if do_print:
		print(indent, "Face ", face)

	var iter := OclNodeIterHandle.new()

	var wires := _collect_iter(
		OclTopo.topo_wires_of_face_iter_create(
			graph,
			face,
			iter
		) as OclCore.status,
		iter
	)

	for wire in wires:

		if do_print:
			var is_outer := wire == outer.bits

			print(
				indent,
				"  Wire ",
				wire,
				(" (outer)" if is_outer else  "")
			)

		_dump_wire(graph, wire, indent + "    ", visited, do_print)
		
static func _dump_wire(graph, wire:int, indent:String, visited, do_print: bool = true):

	visited.wire[wire] = true

	var iter := OclNodeIterHandle.new()

	var coedges := _collect_iter(
		OclTopo.topo_coedges_of_wire_iter_create(
			graph,
			wire,
			iter
		) as OclCore.status,
		iter
	)

	for coedge in coedges:

		visited.coedge[coedge] = true

		var edge := OclNodeId.new()
		var st := OclTopo.topo_coedge_edge_of(
			graph,
			coedge,
			edge
		) as OclCore.status
		assert(st == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())])

		if do_print:
			var rev := OclInt32.new()
			var seam := OclInt32.new()

			st = OclTopo.topo_coedge_is_reversed(graph, coedge, rev) as OclCore.status
			assert(st == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())])

			st = OclTopo.topo_coedge_is_seam(graph, coedge, seam) as OclCore.status
			assert(st == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())])

			var flags := ""
			if rev.value != 0:
				flags += " rev"
			if seam.value != 0:
				flags += " seam"

			print(indent, "Coedge ", coedge, flags)

		_dump_edge(graph, edge.bits, indent + "  ", visited, do_print)
		
static func _dump_edge(graph, edge:int, indent:String, visited, do_print: bool = true):

	if visited.edge.has(edge):
		return

	visited.edge[edge] = true

	var sv := OclNodeId.new()
	var ev := OclNodeId.new()

	var st := OclTopo.topo_edge_start_vertex(graph, edge, sv)
	if st != OclCore.OK:
		visited.vertex[0] = true
		return
	st = OclTopo.topo_edge_end_vertex(graph, edge, ev)
	if st != OclCore.OK:
		visited.vertex[0] = true
		return

	if do_print:
		var boundary := OclInt32.new()
		var manifold := OclInt32.new()
		st = OclTopo.topo_edge_is_boundary(graph, edge, boundary)
		assert(st == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())])
		st = OclTopo.topo_edge_is_manifold(graph, edge, manifold)
		assert(st == OclCore.OK, "Got status %s - %s" % [OclCore.status_to_string(st), var_to_str(OclCore.error_last())])

		print(
			indent,
			"Edge ",
			edge,
			" (",
			sv.bits,
			"→",
			ev.bits,
			")",
			(" boundary" if boundary.value != 0 else ""),
			(" manifold" if manifold.value != 0 else "")
		)

	visited.vertex[sv.bits] = true
	visited.vertex[ev.bits] = true
	
static func _dump_orphans(graph, visited):

	print("\n----- ORPHANS -----")

	var mapping = [
		[OclCore.KIND_SHELL, "shell"],
		[OclCore.KIND_FACE, "face"],
		[OclCore.KIND_WIRE, "wire"],
		[OclCore.KIND_COEDGE, "coedge"],
		[OclCore.KIND_EDGE, "edge"],
		[OclCore.KIND_VERTEX, "vertex"],
	]

	for m in mapping:

		var ids = _collect_ids(graph, m[0])

		var found := false

		for id in ids:
			if !visited[m[1]].has(id):
				if !found:
					found = true
					print(OclCore.node_kind_to_string(m[0]), ":")

				print("   ", id)


static func collect_kinds(
	graph: OclGraphHandle,
	kinds: Array[OclCore.node_kind],
) -> Dictionary:
	var visited := {
		"solid": {},
		"shell": {},
		"face": {},
		"wire": {},
		"coedge": {},
		"edge": {},
		"vertex": {},
	}

	# Traverse every solid exactly like dump_graph_tree().
	for kind in kinds:
		match kind:
			OclCore.KIND_SOLID:
				for id in _collect_ids(graph, kind):
					_dump_solid(graph, id, "", visited, false)

			OclCore.KIND_SHELL:
				for id in _collect_ids(graph, kind):
					_dump_shell(graph, id, "", visited, false)

			OclCore.KIND_FACE:
				for id in _collect_ids(graph, kind):
					_dump_face(graph, id, "", visited, false)

			OclCore.KIND_WIRE:
				for id in _collect_ids(graph, kind):
					_dump_wire(graph, id, "", visited, false)

			OclCore.KIND_EDGE:
				for id in _collect_ids(graph, kind):
					_dump_edge(graph, id, "", visited, false)
	
	return visited

## Deletes every orphan node whose kind is present in `kinds`.
##
## A node is considered an orphan if it is not reachable from any root node
## (typically KIND_SOLID) through the topology hierarchy.
##
## Example:
##     delete_orphans(graph, [OclCore.KIND_SHELL], [
##         OclCore.KIND_EDGE, OclCore.KIND_WIRE,
##     ])
##
## Returns the number of nodes successfully removed.
static func delete_orphans(
	graph: OclGraphHandle,
	roots: Array[OclCore.node_kind],
	kinds: Array[OclCore.node_kind],
) -> int:
	var visited := collect_kinds(graph, roots)

	var removed := 0

	var mapping := {
		OclCore.KIND_SOLID: ["solid"],
		OclCore.KIND_SHELL: ["shell"],
		OclCore.KIND_FACE: ["face"],
		OclCore.KIND_WIRE: ["wire"],
		OclCore.KIND_COEDGE: ["coedge"],
		OclCore.KIND_EDGE: ["edge"],
		OclCore.KIND_VERTEX: ["vertex"],
	}

	for kind in kinds:
		assert(mapping.has(kind), "Unsupported node kind: %d" % kind)

		var visited_map: Dictionary = visited[mapping[kind][0]]

		for id in _collect_ids(graph, kind):
			if visited_map.has(id):
				continue

			var st := OclTopoBuild.topo_remove_subgraph(graph, id) as OclCore.status
			assert(
				st == OclCore.OK,
				"Failed removing orphan %d (%s): %s" % [
					id,
					OclCore.node_kind_to_string(kind),
					OclCore.status_to_string(st),
				]
			)

			removed += 1

	return removed
