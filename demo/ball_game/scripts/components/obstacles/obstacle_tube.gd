class_name ObstacleTube
extends ObstacleBase

const INNER_RATIO := 0.55

static func build(graph: OclGraphHandle, aabb: AABB, xf: Transform3D) -> PackedInt64Array:
	var h := aabb.size.y * 0.9
	var aabb_vol := aabb.size.x * aabb.size.y * aabb.size.z
	var wall_factor := 1.0 - INNER_RATIO * INNER_RATIO
	var outer_r := sqrt(aabb_vol * 0.7 / (PI * h * wall_factor))
	var inner_r := outer_r * INNER_RATIO

	var xf_tube := xf
	xf_tube.origin += xf.basis * (aabb.position + Vector3(aabb.size.x * 0.5, 0, aabb.size.z * 0.5))
	xf_tube.basis = xf.basis * Basis(Vector3(1, 0, 0), -PI / 2)

	var outer_circle := OclPrimCircleInfo.new()
	outer_circle.placement = _placement(xf_tube)
	outer_circle.radius = outer_r
	var outer_wire := OclNodeId.new()
	if OclPrimSketch.circle(graph, outer_circle, outer_wire) != OK:
		return PackedInt64Array()

	var outer_prism := OclPrimPrismInfo.new()
	outer_prism.profile = outer_wire.get_bits()
	outer_prism.direction = _v3(xf.basis * Vector3(0, h, 0))
	var outer_solid := OclNodeId.new()
	if OclPrimSweep.prism(graph, outer_prism, outer_solid) != OK:
		return PackedInt64Array()

	var inner_circle := OclPrimCircleInfo.new()
	inner_circle.placement = _placement(xf_tube)
	inner_circle.radius = inner_r
	var inner_wire := OclNodeId.new()
	if OclPrimSketch.circle(graph, inner_circle, inner_wire) != OK:
		return PackedInt64Array()

	var inner_prism := OclPrimPrismInfo.new()
	inner_prism.profile = inner_wire.get_bits()
	inner_prism.direction = _v3(xf.basis * Vector3(0, h, 0))
	var inner_solid := OclNodeId.new()
	if OclPrimSweep.prism(graph, inner_prism, inner_solid) != OK:
		return PackedInt64Array()

	var out := OclNodeId.new()
	var s := OclBool.cut(
		graph,
		PackedInt64Array([outer_solid.get_bits()]),
		PackedInt64Array([inner_solid.get_bits()]),
		OclBoolOptions.new(),
		out,
	) as int
	return PackedInt64Array([out.get_bits()]) if s == OK else PackedInt64Array()
