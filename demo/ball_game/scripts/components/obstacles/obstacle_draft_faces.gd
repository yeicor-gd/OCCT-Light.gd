class_name ObstacleDraftFaces
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var scale := Vector3(aabb.size.x * 0.85, aabb.size.y * 0.85, aabb.size.z * 0.85)
	var box_info := OclPrimBoxInfo.new()
	box_info.placement = _placement(Transform3D.IDENTITY)
	box_info.dx = scale.x
	box_info.dy = scale.y
	box_info.dz = scale.z
	var box := OclNodeId.new()
	if OclPrimSolid.box(graph, box_info, box) != OK:
		return PackedInt64Array()

	var face_iter := OclNodeIterHandle.new()
	if OclTopo.graph_face_iter_create(graph, face_iter) != OK:
		return PackedInt64Array()
	var face_id := OclNodeId.new()
	var top_faces := PackedInt64Array()
	while OclTopo.node_iter_next(face_iter, face_id) == OK:
		top_faces.append(face_id.get_bits())
		if top_faces.size() >= 2:
			break
	OclTopo.node_iter_free(face_iter)
	if top_faces.is_empty():
		return PackedInt64Array()

	var draft_opts := OclTopoDraftFacesOptions.new()
	draft_opts.root = box.get_bits()
	draft_opts.faces = top_faces
	draft_opts.pull_direction = _d3(Vector3(0, 1, 0))
	draft_opts.neutral_point = _p3(Vector3.ZERO)
	draft_opts.neutral_normal = _d3(Vector3(0, 1, 0))
	draft_opts.angle = OclCore.ANGLE_5_DEG_RAD()
	draft_opts.keep_inside = 1
	var out_graph := OclGraphHandle.new()
	var out_root := OclNodeId.new()
	var s := OclTopoAlgo.draft_faces(graph, draft_opts, out_graph, out_root) as int
	if s != OK:
		return PackedInt64Array()

	var h = out_graph.release()
	graph.free()
	graph.set_handle(h)
	if xf == Transform3D.IDENTITY:
		return PackedInt64Array([out_root.get_bits()])

	var xf_graph := OclGraphHandle.new()
	var xf_root := OclNodeId.new()
	var t := _transform_to_occl(xf)
	var ts := OclTopoAlgo.transformed(graph, out_root.get_bits(), t, xf_graph, xf_root) as int
	if ts != OK:
		return PackedInt64Array()
	var hx = xf_graph.release()
	graph.free()
	graph.set_handle(hx)
	return PackedInt64Array([xf_root.get_bits()])
