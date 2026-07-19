class_name ObstacleCheckTopology
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var info := OclPrimBoxInfo.new()
	info.placement = _placement(xf)
	info.dx = aabb.size.x * 0.8
	info.dy = aabb.size.y * 0.8
	info.dz = aabb.size.z * 0.8
	var box := OclNodeId.new()
	if OclPrimSolid.box(graph, info, box) != OK:
		return PackedInt64Array()

	var r := minf(aabb.size.x, aabb.size.y) * 0.35
	var sph_info := OclPrimSphereInfo.new()
	var sph_xf := xf
	sph_xf.origin += xf.basis * Vector3(0, aabb.size.y * 0.2, 0)
	sph_info.placement = _placement(sph_xf)
	sph_info.radius = r
	var sph := OclNodeId.new()
	if OclPrimSolid.sphere(graph, sph_info, sph) != OK:
		return PackedInt64Array()

	var fuse_out := OclNodeId.new()
	var s := OclBool.fuse(
		graph,
		PackedInt64Array([box.get_bits()]),
		PackedInt64Array([sph.get_bits()]),
		OclBoolOptions.new(),
		fuse_out,
	) as int
	if s != OK:
		return PackedInt64Array()

	var issues := OclTopoCheckIssueArray.new()
	OclTopoAlgo.check(graph, issues)
	return PackedInt64Array([fuse_out.get_bits()])
