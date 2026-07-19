class_name ObstacleFilletBox
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var info := OclPrimBoxInfo.new()
	info.placement = _placement(xf)
	info.dx = aabb.size.x * 0.8
	info.dy = aabb.size.y * 0.8
	info.dz = aabb.size.z * 0.8
	var box := OclNodeId.new()
	if OclPrimSolid.box(graph, info, box) != OK:
		return PackedInt64Array()

	var edge_iter := OclNodeIterHandle.new()
	if OclTopo.graph_edge_iter_create(graph, edge_iter) != OK:
		return PackedInt64Array()
	var edges := PackedInt64Array()
	var eid := OclNodeId.new()
	var sv := OclNodeId.new()
	var ev := OclNodeId.new()
	var s_pt := OclPoint3.new()
	var e_pt := OclPoint3.new()
	var center_y := xf.origin.y
	while OclTopo.node_iter_next(edge_iter, eid) == OK:
		if OclTopo.topo_edge_start_vertex(graph, eid.get_bits(), sv) != OK:
			continue
		if OclTopo.topo_edge_end_vertex(graph, eid.get_bits(), ev) != OK:
			continue
		if OclTopo.topo_vertex_point(graph, sv.get_bits(), s_pt) != OK:
			continue
		if OclTopo.topo_vertex_point(graph, ev.get_bits(), e_pt) != OK:
			continue
		if s_pt.get_y() > center_y or e_pt.get_y() > center_y:
			edges.append(eid.get_bits())
	OclTopo.node_iter_free(edge_iter)
	if edges.is_empty():
		return PackedInt64Array()

	var blend_opts := OclTopoEdgeBlendOptions.new()
	blend_opts.root = box.get_bits()
	blend_opts.edges = edges
	blend_opts.radius = minf(aabb.size.x, minf(aabb.size.y, aabb.size.z)) * 0.08
	var out_graph := OclGraphHandle.new()
	var out_root := OclNodeId.new()
	var s := OclTopoAlgo.blend_edges(graph, blend_opts, out_graph, out_root) as int
	if s != OK:
		return PackedInt64Array()
	var h = out_graph.release()
	graph.free()
	graph.set_handle(h)
	return PackedInt64Array([out_root.get_bits()])
