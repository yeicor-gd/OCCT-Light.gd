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
	print()
	var ocl_graph := OclGraphHandle.new()
	var ocl_status := OclTopo.graph_create(ocl_graph)
	assert(ocl_status == OclCore.OK)
	
	var ocl_curve := OclCurveBezierCreateInfo.new()
	ocl_curve.poles = range(path.curve.point_count).map(func(i: int): return v3_to_p3(path.curve.get_point_position(i)))
	ocl_curve.pole_count = ocl_curve.poles.size()
	print("POLES: ", ocl_curve.poles.map(func(v: OclPoint3): return p3_to_v3(v)))
	var ocl_rep_id := OclRepId.new()
	ocl_status = OclCurves.create_bezier(ocl_graph, ocl_curve, ocl_rep_id) as OclCore.status
	assert(ocl_status == OclCore.OK)
		
	OclTopo.graph_free(ocl_graph)
