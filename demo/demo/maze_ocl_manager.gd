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
	
	# FIXME: Don't know how to remove things from the graph 
	#status = OclTopo.topo_remove_occurrence(graph, spline_wire_id.bits)
	#assert(status == OclCore.OK, "Got status " + str(OclCore.status_to_string(status)))
	#status = OclTopo.topo_remove_occurrence(graph, plane_face_id.bits)
	#assert(status == OclCore.OK, "Got status " + str(OclCore.status_to_string(status)))
	
	print("[OclManager] Generated solid in ", (Time.get_ticks_usec() - start_time) / 1000.0, " ms")
	start_time = Time.get_ticks_usec()
	
	var vertices_mesh := OclGodotMesher.mesh_vertices(graph, $Vertices)
	$Vertices.multimesh = vertices_mesh
	print("[OclManager] Meshed ", vertices_mesh.instance_count, " vertices in ", (Time.get_ticks_usec() - start_time) / 1000.0, " ms")
	start_time = Time.get_ticks_usec()
	
	var edges_mesh := OclGodotMesher.mesh_edges(graph, $Edges)
	$Edges.multimesh = edges_mesh
	print("[OclManager] Meshed ", edges_mesh.instance_count, " edge segments in ", (Time.get_ticks_usec() - start_time) / 1000.0, " ms")
	start_time = Time.get_ticks_usec()
	
	# FIXME: SOME FACES ARE SWAPPED (LOOKING INSIDE THE MODEL)
	#var faces_mesh := OclGodotMesher.mesh_faces(graph, $Faces, null, null, true, true, true, true)
	#$Faces.mesh = faces_mesh
	#print("Generated ", faces_mesh.get_faces().size(), " face segments in ", (Time.get_ticks_usec() - start_time) / 1000.0, " ms")
	# WORKAROUND FOR NOW:
	var stl_bytes := OclByteArray.new()
	status = OclDe.write_memory(graph, sweep_id.bits, "stl", stl_bytes)
	assert(status == OclCore.OK, "Got status " + str(OclCore.status_to_string(status)))
	print("[OclManager] Meshed ", stl_bytes.value.size(), "B for faces to memory in ", (Time.get_ticks_usec() - start_time) / 1000.0, " ms")
	start_time = Time.get_ticks_usec()
	var faces_mesh = StlImporter.LoadFromBytes(stl_bytes.value)
	assert(!StlImporter.IsError(faces_mesh), "StlImporter failed with result " + str(faces_mesh))
	var mesh: ArrayMesh = faces_mesh
	$Faces.mesh = faces_mesh
	print("[OclManager] Read ", faces_mesh.get_faces().size(), " faces (from GDScript) in ", (Time.get_ticks_usec() - start_time) / 1000.0, " ms")
	start_time = Time.get_ticks_usec()

func array_mesh_from_binary_stl(bytes: PackedByteArray) -> ArrayMesh:
	var stream := StreamPeerBuffer.new()
	stream.data_array = bytes
	stream.big_endian = false

	# Skip 80-byte header
	stream.seek(80)

	var triangle_count = stream.get_u32()

	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()

	vertices.resize(triangle_count * 3)
	normals.resize(triangle_count * 3)

	var vi = 0

	for i in triangle_count:
		# Face normal
		var normal = Vector3(
			stream.get_float(),
			stream.get_float(),
			stream.get_float()
		)

		for j in 3:
			vertices[vi] = Vector3(
				stream.get_float(),
				stream.get_float(),
				stream.get_float()
			)
			normals[vi] = normal
			vi += 1

		# Attribute byte count (usually zero)
		stream.get_u16()

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return mesh
