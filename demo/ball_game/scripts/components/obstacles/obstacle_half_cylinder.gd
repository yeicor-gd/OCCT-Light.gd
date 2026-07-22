class_name ObstacleHalfCylinder
extends ObstacleBase

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var h := aabb.size.y * 0.9
	var aabb_vol := aabb.size.x * aabb.size.y * aabb.size.z
	var r := sqrt(aabb_vol * 0.7 * 2.0 / (PI * h))

	var xf_cyl := xf
	xf_cyl.origin += xf.basis * (aabb.position + Vector3(aabb.size.x * 0.5, 0, aabb.size.z * 0.5))
	xf_cyl.basis = xf.basis * Basis(Vector3(1, 0, 0), -PI / 2)

	var info := OclPrimCylinderInfo.new()
	info.placement = _placement(xf_cyl)
	info.radius = r
	info.height = h
	info.angle = PI
	var out := OclNodeId.new()
	var s := OclPrimSolid.cylinder(graph, info, out) as int
	return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()
