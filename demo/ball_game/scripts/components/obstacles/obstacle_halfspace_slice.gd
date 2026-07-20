class_name ObstacleHalfspaceSlice
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var box := OclNodeId.new()
	if _make_box(graph, xf, aabb, aabb.size.x, aabb.size.y, aabb.size.z, box) != OK:
		return PackedInt64Array()

	var cutter_basis := xf.basis * Basis(Vector3(1, 0, 0), deg_to_rad(30))
	var cutter_center_local := aabb.position + Vector3(aabb.size.x * 0.5, aabb.size.y * 0.4, aabb.size.z * 0.5)
	var cutter_center := xf.origin + xf.basis * cutter_center_local
	var half_dims := Vector3(aabb.size.x * 0.6, aabb.size.y * 0.2, aabb.size.z * 0.6)
	var cutter_corner := cutter_center - cutter_basis * half_dims

	var cutter_info := OclPrimBoxInfo.new()
	cutter_info.placement = _placement(Transform3D(cutter_basis, cutter_corner))
	cutter_info.dx = aabb.size.x * 1.2
	cutter_info.dy = aabb.size.y * 0.4
	cutter_info.dz = aabb.size.z * 1.2
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
