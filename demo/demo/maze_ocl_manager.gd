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
	assert(ocl_status == OclCore.OK)
	(func(): OclTopo.graph_free(ocl_graph)).call_deferred()
	
	var ocl_curve := OclCurveApproximatedInfo.new()
	ocl_curve.points = range(path.curve.point_count).map(func(i: int): return v3_to_p3(path.curve.get_point_position(i)))
	var ocl_rep_id := OclRepId.new()
	ocl_status = OclCurves.create_approximated(ocl_graph, ocl_curve, ocl_rep_id) as OclCore.status
	assert(ocl_status == OclCore.OK)
	
