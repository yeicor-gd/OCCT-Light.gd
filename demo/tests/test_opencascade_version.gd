class_name TestOpenCascadeVersion


static func _occ() -> OpenCascadeVersion:
	return OpenCascadeVersion.new()


static func test_get_version_string() -> String:
	var occ := _occ()

	TestRunner.ctx.log_info("Creating version object")

	var version_str := occ.get_version_string()
	occ.free()

	if not version_str is String or version_str == "":
		TestRunner.ctx.log_error("Invalid version string: %s" % str(version_str))
		return "expected non-empty String, got: %s" % str(version_str)

	return ""


static func test_get_version_major() -> String:
	var occ := _occ()

	var major := occ.get_version_major()
	occ.free()

	TestRunner.ctx.log_debug("major=%s" % str(major))

	if not major is int or major < 0:
		return "expected non-negative int, got: %s" % str(major)

	return ""


static func test_get_version_minor() -> String:
	var occ := _occ()

	var minor := occ.get_version_minor()
	occ.free()

	if not minor is int or minor < 0:
		return "expected non-negative int, got: %s" % str(minor)

	return ""


static func test_get_version_maintenance() -> String:
	var occ := _occ()

	var maintenance := occ.get_version_maintenance()
	occ.free()

	if not maintenance is int or maintenance < 0:
		return "expected non-negative int, got: %s" % str(maintenance)

	return ""


static func test_version_string_contains_major() -> String:
	var occ := _occ()

	var version_str := occ.get_version_string()
	var major := occ.get_version_major()

	occ.free()

	TestRunner.ctx.log_debug("version=%s major=%d" % [version_str, major])

	if not version_str.contains(str(major)):
		return "version string %s does not contain major %d" % [version_str, major]

	return ""


static func test_version_immutability() -> String:
	var occ := _occ()

	var major_1 := occ.get_version_major()
	var minor_1 := occ.get_version_minor()
	var maintenance_1 := occ.get_version_maintenance()
	var string_1 := occ.get_version_string()

	var major_2 := occ.get_version_major()
	var minor_2 := occ.get_version_minor()
	var maintenance_2 := occ.get_version_maintenance()
	var string_2 := occ.get_version_string()

	occ.free()

	if major_1 != major_2:
		return "major changed: %d -> %d" % [major_1, major_2]
	if minor_1 != minor_2:
		return "minor changed: %d -> %d" % [minor_1, minor_2]
	if maintenance_1 != maintenance_2:
		return "maintenance changed: %d -> %d" % [maintenance_1, maintenance_2]
	if string_1 != string_2:
		return "string changed: %s -> %s" % [string_1, string_2]

	return ""
