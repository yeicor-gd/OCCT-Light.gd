@tool
extends Node3D

@export_node_path("Path3D") var path_node: NodePath
@export_tool_button("Generate") var generate_ := _generate

func _generate():
	var path : Path3D = get_node(path_node)
	print()
	var ocl_graph := OclTopo.graph_create()
	var ocl_curve := OclCurveBsplineCreateInfo.new()
	ocl_curve.poles = range(path.curve.point_count).map(func(i): path.curve.sample_baked_with_rotation(i / path.curve.point_count * path.curve.get_baked_length(), true, true))
	var ocl_rep_id := OclRepId.new()
	var ocl_status : OclCore.status = OclCurves.create_bspline(ocl_graph, ocl_curve, ocl_rep_id)
	if ocl_status != OclCore.OK:
		push_error(OclCore.status_to_string(ocl_status))
		return
	
	pass
