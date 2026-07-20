class_name ObstacleBase
extends RefCounted

const OK := 0

static func _init_runtime() -> int:
	var s = OclCore.runtime_init(null)
	if s != OK and s != 2:
		return s
	return OK

static func _p3(v: Vector3) -> OclPoint3:
	return OcctConversionUtils.v3_to_p3(v)

static func _d3(v: Vector3) -> OclDirection3:
	return OcctConversionUtils.v3_to_d3(v)

static func _v3(v: Vector3) -> OclVector3:
	return OcctConversionUtils.v3_to_ov3(v)

static func _placement(xf: Transform3D) -> OclAxis2Placement:
	return OcctConversionUtils.transform3d_to_occt_placement(xf)

static func _axis1(loc: Vector3, dir: Vector3) -> OclAxis1Placement:
	return OcctConversionUtils.v3_to_axis1(loc, dir)

static func _status_str(s: int) -> String:
	return "%s (%d)" % [OclCore.status_to_string(s), s]

static func _check(status: int, op: String) -> String:
	if status != OK:
		return "%s failed: %s" % [op, _status_str(status)]
	return ""

static func _transform_to_occl(xf: Transform3D) -> OclTransform:
	var placement := _placement(xf)
	var t := OclTransform.new()
	var err := OclGeom.transform_from_axis2(placement, t)
	assert(err == OK, "transform_from_axis2 failed: %s" % _status_str(err))
	return t

static func _apply_transform(graph: OclGraphHandle, root_bits: int, xf: Transform3D) -> Dictionary:
	if xf == Transform3D.IDENTITY:
		return {"graph": graph, "root": root_bits}
	var out_graph := OclGraphHandle.new()
	var out_root := OclNodeId.new()
	var t := _transform_to_occl(xf)
	var status := OclTopoAlgo.transformed(graph, root_bits, t, out_graph, out_root) as int
	if status != OK:
		return {}
	return {"graph": out_graph, "root": out_root.get_bits()}

static func _aabb_center(aabb: AABB, xf: Transform3D) -> Vector3:
	return xf.origin + xf.basis * (aabb.position + aabb.size * 0.5)

static func _make_box(graph: OclGraphHandle, xf: Transform3D, aabb: AABB, dx: float, dy: float, dz: float, out: OclNodeId) -> int:
	var box_xf := xf
	box_xf.origin += xf.basis * (aabb.position + aabb.size * 0.5 - Vector3(dx * 0.5, dy * 0.5, dz * 0.5))
	var info := OclPrimBoxInfo.new()
	info.placement = _placement(box_xf)
	info.dx = dx
	info.dy = dy
	info.dz = dz
	return OclPrimSolid.box(graph, info, out) as int

static func _make_wedge(graph: OclGraphHandle, xf: Transform3D, aabb: AABB, dx: float, dy: float, dz: float, ltx: float, out: OclNodeId) -> int:
	var box_xf := xf
	box_xf.origin += xf.basis * (aabb.position + aabb.size * 0.5 - Vector3(dx * 0.5, dy * 0.5, dz * 0.5))
	var info := OclPrimWedgeInfo.new()
	info.placement = _placement(box_xf)
	info.dx = dx
	info.dy = dy
	info.dz = dz
	info.ltx = ltx
	return OclPrimSolid.wedge(graph, info, out) as int
