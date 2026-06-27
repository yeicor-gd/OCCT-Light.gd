class_name TestImportExport


static func _approx(a: float, b: float, epsilon := 0.001) -> bool:
	return absf(a - b) <= epsilon


static func _approx_vec(a: Vector3, b: Vector3, epsilon := 0.001) -> bool:
	return _approx(a.x, b.x, epsilon) and _approx(a.y, b.y, epsilon) and _approx(a.z, b.z, epsilon)


static func _temp_path(extension: String) -> String:
	var temp_dir := OS.get_environment("TEMP")
	if temp_dir.is_empty():
		temp_dir = OS.get_environment("TMP")
	if temp_dir.is_empty():
		temp_dir = "/tmp"
	return "%s/build123d_gd_%d%s" % [temp_dir, Time.get_ticks_usec(), extension]


static func _box() -> SolidBox:
	var box := SolidBox.new()
	box.build_box(Vector3(1.0, 2.0, 3.0))
	return box


static func test_step_round_trip_file_and_bytes() -> String:
	var source := _box()
	var file_path := _temp_path(".step")

	if not source.export_step_file(file_path):
		return "failed to export STEP file"

	var from_file := TopoShape.new()
	if not from_file.import_step_file(file_path):
		return "failed to import STEP file"

	var bytes := source.export_step_bytes()
	if bytes.is_empty():
		return "STEP byte export returned no data"

	var from_bytes := TopoShape.new()
	if not from_bytes.import_step_bytes(bytes):
		return "failed to import STEP bytes"

	if not _approx(from_file.get_volume(), 6.0):
		return "unexpected STEP file round-trip volume: %s" % from_file.get_volume()
	if not _approx(from_bytes.get_volume(), 6.0):
		return "unexpected STEP byte round-trip volume: %s" % from_bytes.get_volume()
	if not _approx_vec(from_file.get_bounding_box_size(), Vector3(1.0, 2.0, 3.0)):
		return "unexpected STEP file round-trip bounds: %s" % str(from_file.get_bounding_box_size())

	DirAccess.remove_absolute(file_path)
	return ""


static func test_stl_round_trip_and_mesh_conversion() -> String:
	var source := _box()
	var file_path := _temp_path(".stl")

	if not source.export_stl_file(file_path, false):
		return "failed to export STL file"

	var from_file := TopoShape.new()
	if not from_file.import_stl_file(file_path):
		return "failed to import STL file"

	var bytes := source.export_stl_bytes(false)
	if bytes.is_empty():
		return "STL byte export returned no data"

	var from_bytes := TopoShape.new()
	if not from_bytes.import_stl_bytes(bytes):
		return "failed to import STL bytes"

	var mesh := source.to_array_mesh(0.05, 0.3)
	if mesh == null:
		return "mesh conversion returned null"
	if mesh.get_surface_count() < 1:
		return "mesh conversion returned no surfaces"
	if not _approx_vec(mesh.get_aabb().size, Vector3(1.0, 2.0, 3.0), 0.05):
		return "unexpected mesh AABB size: %s" % str(mesh.get_aabb().size)
	if not _approx_vec(from_file.get_bounding_box_size(), Vector3(1.0, 2.0, 3.0), 0.05):
		return "unexpected STL file round-trip bounds: %s" % str(from_file.get_bounding_box_size())
	if not _approx_vec(from_bytes.get_bounding_box_size(), Vector3(1.0, 2.0, 3.0), 0.05):
		return "unexpected STL byte round-trip bounds: %s" % str(from_bytes.get_bounding_box_size())

	DirAccess.remove_absolute(file_path)
	return ""
