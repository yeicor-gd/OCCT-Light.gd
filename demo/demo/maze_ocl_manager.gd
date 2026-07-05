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
	var ocl_status := OclTopo.graph_create(ocl_graph)
	assert(ocl_status == OclCore.OK, "Got ocl_status " + str(OclCore.status_to_string(ocl_status)))
	(func(): OclTopo.graph_free(ocl_graph)).call_deferred()
	
	var ocl_curve := OclCurveBezierCreateInfo.new()
	ocl_curve.poles = range(path.curve.point_count).map(func(i: int): return v3_to_p3(path.curve.get_point_position(i)))
	var ocl_rep_id := OclRepId.new()
	ocl_status = OclCurves.create_bezier(ocl_graph, ocl_curve, ocl_rep_id) as OclCore.status
	assert(ocl_status == OclCore.OK, "Got ocl_status " + str(OclCore.status_to_string(ocl_status)))
	
	var ocl_edge_count := OclSize.new()
	ocl_status = OclTopo.graph_edge_count(ocl_graph, ocl_edge_count)
	assert(ocl_status == OclCore.OK, "Got ocl_status " + str(OclCore.status_to_string(ocl_status)))
	print("Got ", ocl_edge_count.value, " edges")
	
	var ocl_edge_iter := OclNodeIterHandle.new()
	ocl_status = OclTopo.graph_edge_iter_create(ocl_graph, ocl_edge_iter)
	assert(ocl_status == OclCore.OK, "Got ocl_status " + str(OclCore.status_to_string(ocl_status)))
	
	var ocl_edge_id := OclNodeId.new()
	ocl_status = OclTopo.node_iter_next(ocl_edge_iter, ocl_edge_id)
	assert(ocl_status == OclCore.OK, "Got ocl_status " + str(OclCore.status_to_string(ocl_status)))
	OclTopo.node_iter_free(ocl_edge_iter)
	
	ocl_status = OclMesh.generate(ocl_graph, PackedInt64Array([ocl_edge_id.bits]), OclMeshOptions.new())
	assert(ocl_status == OclCore.OK, "Got ocl_status " + str(OclCore.status_to_string(ocl_status)))
	
	var ocl_edge_view := OclPolygon3dView.new()
	ocl_status = OclMesh.edge_polygon3d(ocl_graph, ocl_edge_id.bits, ocl_edge_view)
	assert(ocl_status == OclCore.OK, "Got ocl_status " + str(OclCore.status_to_string(ocl_status)))
	
