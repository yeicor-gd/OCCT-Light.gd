class_name TestAutoWrapper

static func test_occtl_pi():
	var w = OcctlCore.new()
	var pi = w.const_OCCTL_PI()
	if pi <= 0.0:
		return "OCCTL_PI returned non-positive value: " + str(pi)
	if abs(pi - 3.14159) > 0.01:
		return "OCCTL_PI seems unexpected: " + str(pi)
	return ""

static func test_version_major():
	var w = OcctlCore.new()
	var major = w.const_OCCTL_VERSION_MAJOR()
	if major < 0:
		return "version_major returned negative: " + str(major)
	return ""

static func test_version_minor():
	var w = OcctlCore.new()
	var minor = w.const_OCCTL_VERSION_MINOR()
	if minor < 0:
		return "version_minor returned negative: " + str(minor)
	return ""

static func test_version_patch():
	var w = OcctlCore.new()
	var patch = w.const_OCCTL_VERSION_PATCH()
	if patch < 0:
		return "version_patch returned negative: " + str(patch)
	return ""

static func test_occtl_abi_version():
	var w = OcctlCore.new()
	var version = w.const_OCCTL_ABI_VERSION()
	if version <= 0:
		return "occtl_abi_version returned non-positive value: " + str(version)
	return ""

static func test_occtl_ok():
	var w = OcctlCore.new()
	var result = w.OCCTL_OK()
	if result != 0:
		return "expected occtl_ok to be 0, got %d" % result
	return ""

static func test_occtl_error():
	var w = OcctlCore.new()
	var result = w.OCCTL_ERROR()
	if result != 1:
		return "expected occtl_error to be 1, got %d" % result
	return ""

static func test_occtl_invalid_argument():
	var w = OcctlCore.new()
	var result = w.OCCTL_INVALID_ARGUMENT()
	if result != 2:
		return "expected occtl_invalid_argument to be 2, got %d" % result
	return ""

static func test_occtl_invalid_handle():
	var w = OcctlCore.new()
	var result = w.OCCTL_INVALID_HANDLE()
	if result != 3:
		return "expected occtl_invalid_handle to be 3, got %d" % result
	return ""

static func test_occtl_not_found():
	var w = OcctlCore.new()
	var result = w.OCCTL_NOT_FOUND()
	if result != 4:
		return "expected occtl_not_found to be 4, got %d" % result
	return ""

static func test_occtl_out_of_memory():
	var w = OcctlCore.new()
	var result = w.OCCTL_OUT_OF_MEMORY()
	if result != 5:
		return "expected occtl_out_of_memory to be 5, got %d" % result
	return ""

static func test_occtl_out_of_range():
	var w = OcctlCore.new()
	var result = w.OCCTL_OUT_OF_RANGE()
	if result != 6:
		return "expected occtl_out_of_range to be 6, got %d" % result
	return ""

static func test_occtl_not_done():
	var w = OcctlCore.new()
	var result = w.OCCTL_NOT_DONE()
	if result != 7:
		return "expected occtl_not_done to be 7, got %d" % result
	return ""

static func test_occtl_geometry_invalid():
	var w = OcctlCore.new()
	var result = w.OCCTL_GEOMETRY_INVALID()
	if result != 8:
		return "expected occtl_geometry_invalid to be 8, got %d" % result
	return ""

static func test_occtl_topology_invalid():
	var w = OcctlCore.new()
	var result = w.OCCTL_TOPOLOGY_INVALID()
	if result != 9:
		return "expected occtl_topology_invalid to be 9, got %d" % result
	return ""

static func test_occtl_io_error():
	var w = OcctlCore.new()
	var result = w.OCCTL_IO_ERROR()
	if result != 10:
		return "expected occtl_io_error to be 10, got %d" % result
	return ""

static func test_occtl_format_error():
	var w = OcctlCore.new()
	var result = w.OCCTL_FORMAT_ERROR()
	if result != 11:
		return "expected occtl_format_error to be 11, got %d" % result
	return ""

static func test_occtl_unsupported():
	var w = OcctlCore.new()
	var result = w.OCCTL_UNSUPPORTED()
	if result != 12:
		return "expected occtl_unsupported to be 12, got %d" % result
	return ""

static func test_occtl_cancelled():
	var w = OcctlCore.new()
	var result = w.OCCTL_CANCELLED()
	if result != 13:
		return "expected occtl_cancelled to be 13, got %d" % result
	return ""

static func test_occtl_buffer_too_small():
	var w = OcctlCore.new()
	var result = w.OCCTL_BUFFER_TOO_SMALL()
	if result != 14:
		return "expected occtl_buffer_too_small to be 14, got %d" % result
	return ""

static func test_occtl_version_mismatch():
	var w = OcctlCore.new()
	var result = w.OCCTL_VERSION_MISMATCH()
	if result != 15:
		return "expected occtl_version_mismatch to be 15, got %d" % result
	return ""

static func test_occtl_internal():
	var w = OcctlCore.new()
	var result = w.OCCTL_INTERNAL()
	if result != 16:
		return "expected occtl_internal to be 16, got %d" % result
	return ""

static func test_occtl_wrong_kind():
	var w = OcctlCore.new()
	var result = w.OCCTL_WRONG_KIND()
	if result != 17:
		return "expected occtl_wrong_kind to be 17, got %d" % result
	return ""

static func test_occtl_status_reserved_future():
	var w = OcctlCore.new()
	var result = w.OCCTL_STATUS_RESERVED_FUTURE()
	if result != 0x7fffffff:
		return "expected reserved_future to be 0x7fffffff, got %d" % result
	return ""

static func test_status_to_string():
	var w = OcctlCore.new()
	var result = w.status_to_string(0)
	if result == "":
		return "FAIL: status_to_string returned empty string for status 0"
	return ""

static func test_occtl_kind_invalid():
	var w = OcctlCore.new()
	var v = w.OCCTL_KIND_INVALID()
	if v != 0:
		return "expected 0, got %d" % v
	return ""

static func test_occtl_kind_solid():
	var w = OcctlCore.new()
	var v = w.OCCTL_KIND_SOLID()
	if v != 1:
		return "expected 1, got %d" % v
	return ""

static func test_occtl_kind_shell():
	var w = OcctlCore.new()
	var v = w.OCCTL_KIND_SHELL()
	if v != 2:
		return "expected 2, got %d" % v
	return ""

static func test_occtl_kind_face():
	var w = OcctlCore.new()
	var v = w.OCCTL_KIND_FACE()
	if v != 3:
		return "expected 3, got %d" % v
	return ""

static func test_occtl_kind_wire():
	var w = OcctlCore.new()
	var v = w.OCCTL_KIND_WIRE()
	if v != 4:
		return "expected 4, got %d" % v
	return ""

static func test_occtl_kind_edge():
	var w = OcctlCore.new()
	var v = w.OCCTL_KIND_EDGE()
	if v != 5:
		return "expected 5, got %d" % v
	return ""

static func test_occtl_kind_vertex():
	var w = OcctlCore.new()
	var v = w.OCCTL_KIND_VERTEX()
	if v != 6:
		return "expected 6, got %d" % v
	return ""

static func test_occtl_kind_compound():
	var w = OcctlCore.new()
	var v = w.OCCTL_KIND_COMPOUND()
	if v != 7:
		return "expected 7, got %d" % v
	return ""

static func test_occtl_kind_compsolid():
	var w = OcctlCore.new()
	var v = w.OCCTL_KIND_COMPSOLID()
	if v != 8:
		return "expected 8, got %d" % v
	return ""

static func test_occtl_kind_coedge():
	var w = OcctlCore.new()
	var v = w.OCCTL_KIND_COEDGE()
	if v != 9:
		return "expected 9, got %d" % v
	return ""

static func test_occtl_kind_product():
	var w = OcctlCore.new()
	var v = w.OCCTL_KIND_PRODUCT()
	if v != 10:
		return "expected 10, got %d" % v
	return ""

static func test_occtl_kind_occurrence():
	var w = OcctlCore.new()
	var v = w.OCCTL_KIND_OCCURRENCE()
	if v != 11:
		return "expected 11, got %d" % v
	return ""

static func test_occtl_node_kind_reserved_future():
	var w = OcctlCore.new()
	var v = w.OCCTL_NODE_KIND_RESERVED_FUTURE()
	if v != 2147483647:
		return "expected 2147483647, got %d" % v
	return ""

static func test_occtl_rep_kind_invalid():
	var w = OcctlCore.new()
	var val = w.OCCTL_REP_KIND_INVALID()
	if val != 0:
		return "Expected OCCTL_REP_KIND_INVALID == 0, got " + str(val)
	return ""

static func test_occtl_rep_kind_surface():
	var w = OcctlCore.new()
	var val = w.OCCTL_REP_KIND_SURFACE()
	if val != 1:
		return "Expected OCCTL_REP_KIND_SURFACE == 1, got " + str(val)
	return ""

static func test_occtl_rep_kind_curve3d():
	var w = OcctlCore.new()
	var val = w.OCCTL_REP_KIND_CURVE3D()
	if val != 2:
		return "Expected OCCTL_REP_KIND_CURVE3D == 2, got " + str(val)
	return ""

static func test_occtl_rep_kind_curve2d():
	var w = OcctlCore.new()
	var val = w.OCCTL_REP_KIND_CURVE2D()
	if val != 3:
		return "Expected OCCTL_REP_KIND_CURVE2D == 3, got " + str(val)
	return ""

static func test_occtl_rep_kind_triangulation():
	var w = OcctlCore.new()
	var val = w.OCCTL_REP_KIND_TRIANGULATION()
	if val != 4:
		return "Expected OCCTL_REP_KIND_TRIANGULATION == 4, got " + str(val)
	return ""

static func test_occtl_rep_kind_polygon3d():
	var w = OcctlCore.new()
	var val = w.OCCTL_REP_KIND_POLYGON3D()
	if val != 5:
		return "Expected OCCTL_REP_KIND_POLYGON3D == 5, got " + str(val)
	return ""

static func test_occtl_rep_kind_polygon2d():
	var w = OcctlCore.new()
	var val = w.OCCTL_REP_KIND_POLYGON2D()
	if val != 6:
		return "Expected OCCTL_REP_KIND_POLYGON2D == 6, got " + str(val)
	return ""

static func test_occtl_rep_kind_polygon_on_tri():
	var w = OcctlCore.new()
	var val = w.OCCTL_REP_KIND_POLYGON_ON_TRI()
	if val != 7:
		return "Expected OCCTL_REP_KIND_POLYGON_ON_TRI == 7, got " + str(val)
	return ""

static func test_occtl_rep_kind_reserved_future():
	var w = OcctlCore.new()
	var val = w.OCCTL_REP_KIND_RESERVED_FUTURE()
	if val != 0x7fffffff:
		return "Expected OCCTL_REP_KIND_RESERVED_FUTURE == 0x7fffffff, got " + str(val)
	return ""

static func test_occtl_ref_kind_invalid():
	var w = OcctlCore.new()
	if w.OCCTL_REF_KIND_INVALID() != 0:
		return "occtl_ref_kind_invalid wrong: got %d" % w.OCCTL_REF_KIND_INVALID()
	return ""

static func test_occtl_ref_kind_shell():
	var w = OcctlCore.new()
	if w.OCCTL_REF_KIND_SHELL() != 1:
		return "occtl_ref_kind_shell wrong: got %d" % w.OCCTL_REF_KIND_SHELL()
	return ""

static func test_occtl_ref_kind_face():
	var w = OcctlCore.new()
	if w.OCCTL_REF_KIND_FACE() != 2:
		return "occtl_ref_kind_face wrong: got %d" % w.OCCTL_REF_KIND_FACE()
	return ""

static func test_occtl_ref_kind_wire():
	var w = OcctlCore.new()
	if w.OCCTL_REF_KIND_WIRE() != 3:
		return "occtl_ref_kind_wire wrong: got %d" % w.OCCTL_REF_KIND_WIRE()
	return ""

static func test_occtl_ref_kind_coedge():
	var w = OcctlCore.new()
	if w.OCCTL_REF_KIND_COEDGE() != 4:
		return "occtl_ref_kind_coedge wrong: got %d" % w.OCCTL_REF_KIND_COEDGE()
	return ""

static func test_occtl_ref_kind_vertex():
	var w = OcctlCore.new()
	if w.OCCTL_REF_KIND_VERTEX() != 5:
		return "occtl_ref_kind_vertex wrong: got %d" % w.OCCTL_REF_KIND_VERTEX()
	return ""

static func test_occtl_ref_kind_solid():
	var w = OcctlCore.new()
	if w.OCCTL_REF_KIND_SOLID() != 6:
		return "occtl_ref_kind_solid wrong: got %d" % w.OCCTL_REF_KIND_SOLID()
	return ""

static func test_occtl_ref_kind_child():
	var w = OcctlCore.new()
	if w.OCCTL_REF_KIND_CHILD() != 7:
		return "occtl_ref_kind_child wrong: got %d" % w.OCCTL_REF_KIND_CHILD()
	return ""

static func test_occtl_ref_kind_occurrence():
	var w = OcctlCore.new()
	if w.OCCTL_REF_KIND_OCCURRENCE() != 8:
		return "occtl_ref_kind_occurrence wrong: got %d" % w.OCCTL_REF_KIND_OCCURRENCE()
	return ""

static func test_occtl_ref_kind_reserved_future():
	var w = OcctlCore.new()
	if w.OCCTL_REF_KIND_RESERVED_FUTURE() != 2147483647:
		return "occtl_ref_kind_reserved_future wrong: got %d" % w.OCCTL_REF_KIND_RESERVED_FUTURE()
	return ""

static func test_occtl_error_last():
	var w = OcctlCore.new()
	var err = w.error_last()
	if err == null:
		return "error_last returned null"
	return ""

static func test_occtl_error_clear():
	var w = OcctlCore.new()
	w.error_clear()
	var err = w.error_last()
	if err == null:
		return "error_last returned null after clear"
	return ""

static func test_error_last():
	var w = OcctlCore.new()
	var err = w.error_last()
	if err == null:
		return "error_last returned null"
	if err.status < 0:
		return "unexpected negative status"
	return ""

static func test_occtl_runtime_init_info_version_1():
	var w = OcctlCore.new()
	var v = w.const_OCCTL_RUNTIME_INIT_INFO_VERSION_1()
	if v < 0:
		return "version should be non-negative"
	return ""

static func test_runtime_init_info_init():
	var w = OcctlCore.new()
	var info = OcctlRuntimeInitInfo.new()
	var result = w.runtime_init_info_init(info)
	if result != 0:
		return "runtime_init_info_init returned %d, expected 0" % result
	if info.struct_version != 1:
		return "Expected struct_version=1, got " + str(info.struct_version)
	return ""

static func test_runtime_init():
	var w = OcctlCore.new()
	var info = OcctlRuntimeInitInfo.new()
	w.runtime_init_info_init(info)
	var result = w.runtime_init(info)
	if result != 0:
		return "runtime_init returned %d, expected 0" % result
	return ""

static func test_occtl_runtime_shutdown():
	var w = OcctlCore.new()
	w.runtime_shutdown()
	return ""

static func test_occtl_runtime_abi_version():
	var w = OcctlCore.new()
	var version = w.runtime_abi_version()
	if version < 0:
		return "expected non-negative version, got: " + str(version)
	return ""

static func test_runtime_occt_version():
	var w = OcctlCore.new()
	var version = w.runtime_occt_version()
	if version == null or version == "":
		return "runtime_occt_version returned empty string"
	return ""

static func test_runtime_version():
	var w = OcctlCore.new()
	var major = OcctlUint32.new()
	var minor = OcctlUint32.new()
	var patch = OcctlUint32.new()
	w.runtime_version(major, minor, patch)
	if major.get_value() < 0:
		return "expected non-negative major version"
	if minor.get_value() < 0:
		return "expected non-negative minor version"
	if patch.get_value() < 0:
		return "expected non-negative patch version"
	return ""

static func test_occtl_uid_wire_size():
	var w = OcctlCore.new()
	var size = w.const_OCCTL_UID_WIRE_SIZE()
	if size < 0:
		return "expected non-negative size"
	return ""

static func test_uid_to_bytes():
	var w = OcctlCore.new()
	var buf = OcctlByteArray.new()
	var status = w.uid_to_bytes(0, buf)
	if status != 0:
		return "Expected status 0 for uid_to_bytes, got " + str(status)
	var bytes = buf.get_value()
	if bytes.size() != 16:
		return "Expected 16 bytes in result, got " + str(bytes.size())
	return ""

static func test_uid_equal():
	var w = OcctlCore.new()
	var eq_self = w.uid_equal(0, 0)
	if eq_self != 1:
		return "Expected 1 for equal zero UIDs, got " + str(eq_self)
	var neq = w.uid_equal(0, 1)
	if neq != 0:
		return "Expected 0 for unequal UIDs, got " + str(neq)
	var eq_vals = w.uid_equal(100, 100)
	if eq_vals != 1:
		return "Expected 1 for equal non-zero UIDs, got " + str(eq_vals)
	return ""

static func test_occtl_uid_from_bytes():
	var w = OcctlCore.new()
	var bytes = PackedByteArray()
	for i in range(16):
		bytes.append(0)
	var uid = OcctlUid.new()
	var status = w.uid_from_bytes(bytes, uid)
	if status != 0:
		return "Expected status 0, got " + str(status)
	if uid.get_bits() != 0:
		return "Expected uid_bits 0, got " + str(uid.get_bits())
	return ""

static func test_occtl_angle_1_deg_rad():
	var w = OcctlCore.new()
	var val = w.const_OCCTL_ANGLE_1_DEG_RAD()
	if val <= 0.0 or val > 0.1:
		return "Expected angle around 0.0175 rad, got " + str(val)
	return ""

static func test_occtl_angle_90_deg_rad():
	var w = OcctlCore.new()
	var val = w.const_OCCTL_ANGLE_90_DEG_RAD()
	if val <= 0.0 or val > 2.0:
		return "Expected angle around 1.57 rad, got " + str(val)
	return ""
