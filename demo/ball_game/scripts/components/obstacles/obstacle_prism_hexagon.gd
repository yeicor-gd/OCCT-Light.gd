class_name ObstaclePrismHexagon
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var r := minf(aabb.size.x, aabb.size.z) * 0.5
	var poly_info := OclPrimRegularPolygonInfo.new()
	var center_xf := xf
	center_xf.origin += xf.basis * Vector3(0, -aabb.size.y * 0.5, 0)
	center_xf.basis = xf.basis * Basis(Vector3(1, 0, 0), -PI / 2)
	poly_info.placement = _placement(center_xf)
	poly_info.circumradius = r
	poly_info.sides = 6
	var wire := OclNodeId.new()
	if OclPrimSketch.regular_polygon(graph, poly_info, wire) != OK:
		return PackedInt64Array()

	var prism_info := OclPrimPrismInfo.new()
	prism_info.profile = wire.get_bits()
	prism_info.direction = _v3(xf.basis * Vector3(0, aabb.size.y, 0))
	var out := OclNodeId.new()
	var s := OclPrimSweep.prism(graph, prism_info, out) as int
	return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()
