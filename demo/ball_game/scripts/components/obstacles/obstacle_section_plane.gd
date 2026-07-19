class_name ObstacleSectionPlane
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var half := aabb.size * 0.5

	var info := OclPrimBoxInfo.new()
	info.placement = _placement(xf)
	info.dx = aabb.size.x
	info.dy = aabb.size.y
	info.dz = aabb.size.z
	var box := OclNodeId.new()
	if OclPrimSolid.box(graph, info, box) != OK:
		return PackedInt64Array()

	var plane1 := OclTopoSplitByPlaneOptions.new()
	plane1.root = box.get_bits()
	plane1.point = _p3(xf.origin + xf.basis * Vector3(0, half.y * 0.3, 0))
	plane1.normal = _d3(xf.basis * Vector3(0, 1, 0))
	plane1.keep = 1
	var g1 := OclGraphHandle.new()
	var r1 := OclNodeId.new()
	if OclTopoAlgo.make_split_by_plane(graph, plane1, g1, r1) != OK:
		return PackedInt64Array()

	var plane2 := OclTopoSplitByPlaneOptions.new()
	plane2.root = r1.get_bits()
	plane2.point = _p3(xf.origin + xf.basis * Vector3(half.x * 0.3, 0, 0))
	plane2.normal = _d3(xf.basis * Vector3(1, 0, 0))
	plane2.keep = 1
	var g2 := OclGraphHandle.new()
	var r2 := OclNodeId.new()
	if OclTopoAlgo.make_split_by_plane(g1, plane2, g2, r2) != OK:
		return PackedInt64Array()
	var h = g2.release()
	graph.free()
	graph.set_handle(h)
	return PackedInt64Array([r2.get_bits()])
