@tool
extends Node3D

@export_node_path("Path3D") var path_node: NodePath
@export_tool_button("Generate") var generate_ := _generate

func v3_to_p3(v3: Vector3) -> OclPoint3:
	var p3 := OclPoint3.new()
	p3.x = v3.x
	p3.y = v3.y
	p3.z = v3.z
	return p3

func p3_to_v3(p3: OclPoint3) -> Vector3:
	return Vector3(p3.x, p3.y, p3.z)

func _generate():
	var path : Path3D = get_node(path_node)
	var ocl_graph := OclGraphHandle.new()
	var ocl_status := OclTopo.graph_create(ocl_graph)  as OclCore.status
	assert(ocl_status == OclCore.OK, "Got ocl_status " + str(OclCore.status_to_string(ocl_status)))
	(func(): OclTopo.graph_free(ocl_graph)).call_deferred()
	
	var ocl_spline := OclPrimSplineInfo.new()
	print("SETTING POLES TO: ", range(path.curve.point_count).map(func(i: int): return path.curve.get_point_position(i)))
	ocl_spline.points = OclPoint3Array.from(range(path.curve.point_count).map(func(i: int): return v3_to_p3(path.curve.get_point_position(i))))
	print("POLES READ BACK FROM C: ", ocl_spline.points.data.map(func(p: OclPoint3): return p3_to_v3(p)))
	var ocl_node_id := OclNodeId.new()
	ocl_status = OclPrimSketch.spline(ocl_graph, ocl_spline, ocl_node_id) as OclCore.status
	assert(ocl_status == OclCore.OK, "Got ocl_status " + str(OclCore.status_to_string(ocl_status)))
	
	var ocl_edge_count := OclSize.new()
	ocl_status = OclTopo.graph_node_count(ocl_graph, ocl_edge_count) as OclCore.status
	assert(ocl_status == OclCore.OK, "Got ocl_status " + str(OclCore.status_to_string(ocl_status)))
	print("Got ", ocl_edge_count.value, " edges -- node id: ", ocl_node_id.bits)
	
	ocl_status = OclMesh.generate(ocl_graph, PackedInt64Array([ocl_node_id.bits]), OclMeshOptions.new()) as OclCore.status
	assert(ocl_status == OclCore.OK, "Got ocl_status " + str(OclCore.status_to_string(ocl_status)))
	
	var ocl_edge_iter := OclNodeIterHandle.new()
	ocl_status = OclTopo.graph_edge_iter_create(ocl_graph, ocl_edge_iter) as OclCore.status
	assert(ocl_status == OclCore.OK, "Got ocl_status " + str(OclCore.status_to_string(ocl_status)))
	
	OclSurfaceBspline.new()
	
	var edge_ids: Array[OclNodeId] = []
	for _i in range(ocl_edge_count.value):
		var ocl_edge_id := OclNodeId.new()
		ocl_status = OclTopo.node_iter_next(ocl_edge_iter, ocl_edge_id) as OclCore.status
		assert(ocl_status == OclCore.OK, "Got ocl_status " + str(OclCore.status_to_string(ocl_status)))
		edge_ids.push_back(ocl_edge_id)
	OclTopo.node_iter_free(ocl_edge_iter)
	
	var ocl_edge_view := OclPolygon3dView.new()
	for edge_id in edge_ids:
		ocl_status = OclMesh.edge_polygon3d(ocl_graph, edge_id.bits, ocl_edge_view) as OclCore.status
		assert(ocl_status == OclCore.OK, "Got ocl_status " + str(OclCore.status_to_string(ocl_status)))
	
