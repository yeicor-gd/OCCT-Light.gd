@tool
extends Node3D

@export_node_path("Path3D") var path_node: NodePath
@export_tool_button("Generate") var generate_ := _generate
@onready var maze := $".."

func v3_to_p3(v3: Vector3) -> OclPoint3:
	var p3 := OclPoint3.new()
	p3.x = v3.x
	p3.y = v3.y
	p3.z = v3.z
	return p3

func v3_to_d3(v3: Vector3) -> OclDirection3:
	var p3 := OclDirection3.new()
	p3.x = v3.x
	p3.y = v3.y
	p3.z = v3.z
	return p3

func p3_to_v3(p3: OclPoint3) -> Vector3:
	return Vector3(p3.x, p3.y, p3.z)

func _generate():
	var start_time := Time.get_ticks_usec()
	var path : Path3D = get_node(path_node)
	var graph := OclGraphHandle.new()
	var status := OclTopo.graph_create(graph)  as OclCore.status
	assert(status == OclCore.OK, "Got status " + str(OclCore.status_to_string(status)))
	(func(): OclTopo.graph_free(graph)).call_deferred()
	
	var spline_info := OclPrimSplineInfo.new()
	spline_info.points = OclPoint3Array.from(range(path.curve.point_count).map(func(i: int): return v3_to_p3(path.curve.get_point_position(i))))
	var spline_wire_id := OclNodeId.new()
	status = OclPrimSketch.spline(graph, spline_info, spline_wire_id) as OclCore.status
	assert(status == OclCore.OK, "Got status " + str(OclCore.status_to_string(status)))
	
	var plane_info := OclPrimPlaneInfo.new()
	plane_info.width = maze.ball_radius / maze.ball_to_path_min_ratio
	plane_info.height = plane_info.width * 0.4
	var spline_start := path.curve.sample_baked_with_rotation(0.0)
	var plane_info_placement := OclAxis2Placement.new()
	plane_info_placement.x_dir = v3_to_d3(-Vector3(0,0,1))
	plane_info_placement.x_dir_ref = v3_to_d3(-Vector3(1,0,0))
	plane_info_placement.location = v3_to_p3(spline_start.origin)
	plane_info.placement = plane_info_placement
	var plane_face_id := OclNodeId.new()
	status = OclPrimSketch.plane(graph, plane_info, plane_face_id) as OclCore.status
	assert(status == OclCore.OK, "Got status " + str(OclCore.status_to_string(status)))
	
	var sweep_info := OclPrimPipeInfo.new()
	sweep_info.spine_wire = spline_wire_id.bits
	sweep_info.profile = plane_face_id.bits
	var sweep_id := OclNodeId.new()
	status = OclPrimSweep.pipe(graph, sweep_info, sweep_id) as OclCore.status
	assert(status == OclCore.OK, "Got status " + str(OclCore.status_to_string(status)))
	
	#status = OclTopo.topo_remove_occurrence(graph, spline_wire_id.bits)
	#assert(status == OclCore.OK, "Got status " + str(OclCore.status_to_string(status)))
	#status = OclTopo.topo_remove_occurrence(graph, plane_face_id.bits)
	#assert(status == OclCore.OK, "Got status " + str(OclCore.status_to_string(status)))
	
	var vertices_mesh := OclGodotMesher.mesh_vertices(graph, $Vertices, null, null, 0.002)
	$Vertices.multimesh = vertices_mesh
	print("Generated ", vertices_mesh.instance_count, " vertices in ", (Time.get_ticks_usec() - start_time) / 1000.0, " ms")
	
	var edges_mesh := OclGodotMesher.mesh_edges(graph, $Edges, null, null, 0.001)
	$Edges.multimesh = edges_mesh
	print("Generated ", edges_mesh.instance_count, " edge segments in ", (Time.get_ticks_usec() - start_time) / 1000.0, " ms")
	
	var faces_mesh := OclGodotMesher.mesh_faces(graph, $Faces, null, null, true, true, true, true)
	$Faces.mesh = faces_mesh
	print("Generated ", faces_mesh.get_faces().size(), " face segments in ", (Time.get_ticks_usec() - start_time) / 1000.0, " ms")
	
