@tool
class_name OcctConversionUtils
extends RefCounted

## Conversion utilities between Godot types and OCCT types.
## All methods are static — no state needed.


static func v3_to_p3(v3: Vector3) -> OclPoint3:
	var p3 := OclPoint3.new()
	p3.x = v3.x
	p3.y = v3.y
	p3.z = v3.z
	return p3


static func v3_to_d3(v3: Vector3) -> OclDirection3:
	var d3 := OclDirection3.new()
	d3.x = v3.x
	d3.y = v3.y
	d3.z = v3.z
	return d3


static func p3_to_v3(p3: OclPoint3) -> Vector3:
	return Vector3(p3.x, p3.y, p3.z)


static func transform3d_to_occt_array(t: Transform3D) -> PackedFloat64Array:
	var b := t.basis
	var o := t.origin
	return PackedFloat64Array(
		[
			# Row 0
			b.x.x, b.y.x, b.z.x, o.x,
			# Row 1
			b.x.y, b.y.y, b.z.y, o.y,
			# Row 2
			b.x.z, b.y.z, b.z.z, o.z,
		],
	)


static func transform3d_to_occt_placement(t: Transform3D) -> OclAxis2Placement:
	var res := OclAxis2Placement.new()
	res.location = v3_to_p3(t.origin)
	res.x_dir = v3_to_d3(t.basis.z)
	res.x_dir_ref = v3_to_d3(t.basis.x)
	return res
