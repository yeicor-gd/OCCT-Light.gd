class_name ObstacleHalfspaceSlice
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var info := OclPrimBoxInfo.new()
	info.placement = _placement(xf)
	info.dx = aabb.size.x
	info.dy = aabb.size.y
	info.dz = aabb.size.z
	var box := OclNodeId.new()
	if OclPrimSolid.box(graph, info, box) != OK:
		return PackedInt64Array()

	var cutter_info := OclPrimBoxInfo.new()
	var cutter_xf := xf
	cutter_xf.origin += xf.basis * Vector3(0, aabb.size.y * 0.2, 0)
	cutter_xf.basis = xf.basis * Basis(Vector3(1, 0, 0), deg_to_rad(30))
	cutter_info.placement = _placement(cutter_xf)
	cutter_info.dx = aabb.size.x * 1.5
	cutter_info.dy = aabb.size.y * 0.6
	cutter_info.dz = aabb.size.z * 1.5
	var cutter := OclNodeId.new()
	if OclPrimSolid.box(graph, cutter_info, cutter) != OK:
		return PackedInt64Array()

	var out := OclNodeId.new()
	var s := OclBool.cut(
		graph,
		PackedInt64Array([box.get_bits()]),
		PackedInt64Array([cutter.get_bits()]),
		OclBoolOptions.new(),
		out,
	) as int
	return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()
