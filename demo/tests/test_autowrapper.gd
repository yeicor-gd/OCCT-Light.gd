class_name TestAutoWrapper

static func test_occtl_pi():
	var w = OcctlCoreWrapper.new()
	var pi = w.occtl_pi()
	if pi <= 0.0:
		return "OCCTL_PI returned non-positive value: " + str(pi)
	if abs(pi - 3.14159) > 0.01:
		return "OCCTL_PI seems unexpected: " + str(pi)
	return ""

static func test_occtl_two_pi():
	var w = OcctlCoreWrapper.new()
	var val = w.occtl_two_pi()
	if val <= 6.0:
		return "Expected OCCTL_TWO_PI > 6.0, got " + str(val)
	return ""

static func test_occtl_pi_over_two():
	var w = OcctlCoreWrapper.new();
	var val = w.occtl_pi_over_two();
	var expected_min = 1.5;
	var expected_max = 1.6;
	if (val < expected_min or val > expected_max):
		return "Expected pi/2 to be around 1.57, got: " + str(val);
	return "";

static func test_occtl_rad_per_deg():
	var w = OcctlCoreWrapper.new()
	var val = w.occtl_rad_per_deg()
	if val <= 0 or val >= 1:
		return "rad_per_deg should be between 0 and 1"
	return ""

static func test_occtl_angle_5_deg_rad():
	var w = OcctlCoreWrapper.new()
	var val = w.occtl_angle_5_deg_rad()
	if val < 0.0 or val > 1.0:
		return "Expected angle in [0, 1] radians, got " + str(val)
	return ""

static func test_occtl_angle_30_deg_rad():
	var w = OcctlCoreWrapper.new()
	var val = w.occtl_angle_30_deg_rad()
	if val <= 0:
		return "Expected positive value for 30 degrees in radians"
	if val > 1.0:
		return "Expected value around 0.524 for 30 degrees"
	return ""

static func test_angle_20_deg_rad():
	var w = OcctlCoreWrapper.new()
	var val = w.angle_20_deg_rad()
	if val <= 0:
		return "angle_20_deg_rad returned non-positive value: %s" % val
	return ""

static func test_version_major():
	var w = OcctlCoreWrapper.new()
	var major = w.version_major()
	if major < 0:
		return "version_major returned negative: " + str(major)
	return ""

static func test_version_minor():
	var w = OcctlCoreWrapper.new()
	var minor = w.version_minor()
	if minor < 0:
		return "version_minor returned negative: " + str(minor)
	return ""

static func test_version_patch():
	var w = OcctlCoreWrapper.new()
	var patch = w.version_patch()
	if patch < 0:
		return "version_patch returned negative: " + str(patch)
	return ""

static func test_occtl_abi_version():
	var w = OcctlCoreWrapper.new()
	var version = w.occtl_abi_version()
	if version <= 0:
		return "occtl_abi_version returned non-positive value: " + str(version)
	return ""

static func test_angle_90_deg_rad():
	var w = OcctlCoreWrapper.new()
	var v = w.angle_90_deg_rad()
	# 90 degrees in radians is pi/2 ≈ 1.570796
	if v < 1.5 or v > 1.6:
		return "Expected ~1.5708, got " + str(v)
	return ""

static func test_occtl_angle_1_deg_rad():
	var w = OcctlCoreWrapper.new()
	var val = w.occtl_angle_1_deg_rad()
	if val <= 0.0:
		return "Expected positive value for OCCTL_ANGLE_1_DEG_RAD"
	return ""

static func test_occtl_ok():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_ok()
	if result != 0:
		return "expected occtl_ok to be 0, got %d" % result
	return ""

static func test_occtl_error():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_error()
	if result != 1:
		return "expected occtl_error to be 1, got %d" % result
	return ""

static func test_occtl_invalid_argument():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_invalid_argument()
	if result != 2:
		return "expected occtl_invalid_argument to be 2, got %d" % result
	return ""

static func test_occtl_invalid_handle():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_invalid_handle()
	if result != 3:
		return "expected occtl_invalid_handle to be 3, got %d" % result
	return ""

static func test_occtl_not_found():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_not_found()
	if result != 4:
		return "expected occtl_not_found to be 4, got %d" % result
	return ""

static func test_occtl_out_of_memory():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_out_of_memory()
	if result != 5:
		return "expected occtl_out_of_memory to be 5, got %d" % result
	return ""

static func test_occtl_out_of_range():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_out_of_range()
	if result != 6:
		return "expected occtl_out_of_range to be 6, got %d" % result
	return ""

static func test_occtl_not_done():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_not_done()
	if result != 7:
		return "expected occtl_not_done to be 7, got %d" % result
	return ""

static func test_occtl_geometry_invalid():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_geometry_invalid()
	if result != 8:
		return "expected occtl_geometry_invalid to be 8, got %d" % result
	return ""

static func test_occtl_topology_invalid():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_topology_invalid()
	if result != 9:
		return "expected occtl_topology_invalid to be 9, got %d" % result
	return ""

static func test_occtl_io_error():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_io_error()
	if result != 10:
		return "expected occtl_io_error to be 10, got %d" % result
	return ""

static func test_occtl_format_error():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_format_error()
	if result != 11:
		return "expected occtl_format_error to be 11, got %d" % result
	return ""

static func test_occtl_unsupported():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_unsupported()
	if result != 12:
		return "expected occtl_unsupported to be 12, got %d" % result
	return ""

static func test_occtl_cancelled():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_cancelled()
	if result != 13:
		return "expected occtl_cancelled to be 13, got %d" % result
	return ""

static func test_occtl_buffer_too_small():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_buffer_too_small()
	if result != 14:
		return "expected occtl_buffer_too_small to be 14, got %d" % result
	return ""

static func test_occtl_version_mismatch():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_version_mismatch()
	if result != 15:
		return "expected occtl_version_mismatch to be 15, got %d" % result
	return ""

static func test_occtl_internal():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_internal()
	if result != 16:
		return "expected occtl_internal to be 16, got %d" % result
	return ""

static func test_occtl_wrong_kind():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_wrong_kind()
	if result != 17:
		return "expected occtl_wrong_kind to be 17, got %d" % result
	return ""

static func test_occtl_status_reserved_future():
	var w = OcctlCoreWrapper.new()
	var result = w.occtl_status_reserved_future()
	if result != 0x7fffffff:
		return "expected reserved_future to be 0x7fffffff, got %d" % result
	return ""

static func test_status_to_string():
	var w = OcctlCoreWrapper.new()
	var result = w.status_to_string(0)
	if result == "":
		return "FAIL: status_to_string returned empty string for status 0"
	return ""

static func test_occtl_succeeded():
	var w = OcctlCoreWrapper.new()
	var result_success = w.occtl_succeeded(0)
	if result_success != true:
		return "Expected occtl_succeeded(0) to return true"
	var result_fail = w.occtl_succeeded(1)
	if result_fail != false:
		return "Expected occtl_succeeded(1) to return false"
	return ""

static func test_occtl_kind_invalid():
	var w = OcctlCoreWrapper.new()
	var v = w.occtl_kind_invalid()
	if v != 0:
		return "expected 0, got %d" % v
	return ""

static func test_occtl_kind_solid():
	var w = OcctlCoreWrapper.new()
	var v = w.occtl_kind_solid()
	if v != 1:
		return "expected 1, got %d" % v
	return ""

static func test_occtl_kind_shell():
	var w = OcctlCoreWrapper.new()
	var v = w.occtl_kind_shell()
	if v != 2:
		return "expected 2, got %d" % v
	return ""

static func test_occtl_kind_face():
	var w = OcctlCoreWrapper.new()
	var v = w.occtl_kind_face()
	if v != 3:
		return "expected 3, got %d" % v
	return ""

static func test_occtl_kind_wire():
	var w = OcctlCoreWrapper.new()
	var v = w.occtl_kind_wire()
	if v != 4:
		return "expected 4, got %d" % v
	return ""

static func test_occtl_kind_edge():
	var w = OcctlCoreWrapper.new()
	var v = w.occtl_kind_edge()
	if v != 5:
		return "expected 5, got %d" % v
	return ""

static func test_occtl_kind_vertex():
	var w = OcctlCoreWrapper.new()
	var v = w.occtl_kind_vertex()
	if v != 6:
		return "expected 6, got %d" % v
	return ""

static func test_occtl_kind_compound():
	var w = OcctlCoreWrapper.new()
	var v = w.occtl_kind_compound()
	if v != 7:
		return "expected 7, got %d" % v
	return ""

static func test_occtl_kind_compsolid():
	var w = OcctlCoreWrapper.new()
	var v = w.occtl_kind_compsolid()
	if v != 8:
		return "expected 8, got %d" % v
	return ""

static func test_occtl_kind_coedge():
	var w = OcctlCoreWrapper.new()
	var v = w.occtl_kind_coedge()
	if v != 9:
		return "expected 9, got %d" % v
	return ""

static func test_occtl_kind_product():
	var w = OcctlCoreWrapper.new()
	var v = w.occtl_kind_product()
	if v != 10:
		return "expected 10, got %d" % v
	return ""

static func test_occtl_kind_occurrence():
	var w = OcctlCoreWrapper.new()
	var v = w.occtl_kind_occurrence()
	if v != 11:
		return "expected 11, got %d" % v
	return ""

static func test_occtl_node_kind_reserved_future():
	var w = OcctlCoreWrapper.new()
	var v = w.occtl_node_kind_reserved_future()
	if v != 2147483647:
		return "expected 2147483647, got %d" % v
	return ""

static func test_occtl_rep_kind_invalid():
	var w = OcctlCoreWrapper.new()
	var val = w.occtl_rep_kind_invalid()
	if val != 0:
		return "Expected OCCTL_REP_KIND_INVALID == 0, got " + str(val)
	return ""

static func test_occtl_rep_kind_surface():
	var w = OcctlCoreWrapper.new()
	var val = w.occtl_rep_kind_surface()
	if val != 1:
		return "Expected OCCTL_REP_KIND_SURFACE == 1, got " + str(val)
	return ""

static func test_occtl_rep_kind_curve3d():
	var w = OcctlCoreWrapper.new()
	var val = w.occtl_rep_kind_curve3d()
	if val != 2:
		return "Expected OCCTL_REP_KIND_CURVE3D == 2, got " + str(val)
	return ""

static func test_occtl_rep_kind_curve2d():
	var w = OcctlCoreWrapper.new()
	var val = w.occtl_rep_kind_curve2d()
	if val != 3:
		return "Expected OCCTL_REP_KIND_CURVE2D == 3, got " + str(val)
	return ""

static func test_occtl_rep_kind_triangulation():
	var w = OcctlCoreWrapper.new()
	var val = w.occtl_rep_kind_triangulation()
	if val != 4:
		return "Expected OCCTL_REP_KIND_TRIANGULATION == 4, got " + str(val)
	return ""

static func test_occtl_rep_kind_polygon3d():
	var w = OcctlCoreWrapper.new()
	var val = w.occtl_rep_kind_polygon3d()
	if val != 5:
		return "Expected OCCTL_REP_KIND_POLYGON3D == 5, got " + str(val)
	return ""

static func test_occtl_rep_kind_polygon2d():
	var w = OcctlCoreWrapper.new()
	var val = w.occtl_rep_kind_polygon2d()
	if val != 6:
		return "Expected OCCTL_REP_KIND_POLYGON2D == 6, got " + str(val)
	return ""

static func test_occtl_rep_kind_polygon_on_tri():
	var w = OcctlCoreWrapper.new()
	var val = w.occtl_rep_kind_polygon_on_tri()
	if val != 7:
		return "Expected OCCTL_REP_KIND_POLYGON_ON_TRI == 7, got " + str(val)
	return ""

static func test_occtl_rep_kind_reserved_future():
	var w = OcctlCoreWrapper.new()
	var val = w.occtl_rep_kind_reserved_future()
	if val != 0x7fffffff:
		return "Expected OCCTL_REP_KIND_RESERVED_FUTURE == 0x7fffffff, got " + str(val)
	return ""

static func test_occtl_ref_kind_invalid():
	var w = OcctlCoreWrapper.new()
	if w.occtl_ref_kind_invalid() != 0:
		return "occtl_ref_kind_invalid wrong: got %d" % w.occtl_ref_kind_invalid()
	return ""

static func test_occtl_ref_kind_shell():
	var w = OcctlCoreWrapper.new()
	if w.occtl_ref_kind_shell() != 1:
		return "occtl_ref_kind_shell wrong: got %d" % w.occtl_ref_kind_shell()
	return ""

static func test_occtl_ref_kind_face():
	var w = OcctlCoreWrapper.new()
	if w.occtl_ref_kind_face() != 2:
		return "occtl_ref_kind_face wrong: got %d" % w.occtl_ref_kind_face()
	return ""

static func test_occtl_ref_kind_wire():
	var w = OcctlCoreWrapper.new()
	if w.occtl_ref_kind_wire() != 3:
		return "occtl_ref_kind_wire wrong: got %d" % w.occtl_ref_kind_wire()
	return ""

static func test_occtl_ref_kind_coedge():
	var w = OcctlCoreWrapper.new()
	if w.occtl_ref_kind_coedge() != 4:
		return "occtl_ref_kind_coedge wrong: got %d" % w.occtl_ref_kind_coedge()
	return ""

static func test_occtl_ref_kind_vertex():
	var w = OcctlCoreWrapper.new()
	if w.occtl_ref_kind_vertex() != 5:
		return "occtl_ref_kind_vertex wrong: got %d" % w.occtl_ref_kind_vertex()
	return ""

static func test_occtl_ref_kind_solid():
	var w = OcctlCoreWrapper.new()
	if w.occtl_ref_kind_solid() != 6:
		return "occtl_ref_kind_solid wrong: got %d" % w.occtl_ref_kind_solid()
	return ""

static func test_occtl_ref_kind_child():
	var w = OcctlCoreWrapper.new()
	if w.occtl_ref_kind_child() != 7:
		return "occtl_ref_kind_child wrong: got %d" % w.occtl_ref_kind_child()
	return ""

static func test_occtl_ref_kind_occurrence():
	var w = OcctlCoreWrapper.new()
	if w.occtl_ref_kind_occurrence() != 8:
		return "occtl_ref_kind_occurrence wrong: got %d" % w.occtl_ref_kind_occurrence()
	return ""

static func test_occtl_ref_kind_reserved_future():
	var w = OcctlCoreWrapper.new()
	if w.occtl_ref_kind_reserved_future() != 2147483647:
		return "occtl_ref_kind_reserved_future wrong: got %d" % w.occtl_ref_kind_reserved_future()
	return ""

static func test_rep_id_invalid():
	var w = OcctlCoreWrapper.new()
	var invalid = w.rep_id_invalid()
	if invalid != 0:
		return "expected OCCTL_REP_ID_INVALID to be 0 but got " + str(invalid)
	return ""

static func test_occtl_error_last():
	var w = OcctlCoreWrapper.new()
	var err = w.occtl_error_last()
	if not err.has("status"):
		return "missing status"
	if not err.has("message"):
		return "missing message"
	if not err.has("source_bits"):
		return "missing source_bits"
	if not err.has("extended"):
		return "missing extended"
	return ""

static func test_occtl_error_clear():
	var w = OcctlCoreWrapper.new()
	w.occtl_error_clear()
	var err = w.occtl_error_last()
	var status = err.get("status")
	if status != 0:
		return "expected status 0 after clear"
	return ""

static func test_error_last():
	var w = OcctlCoreWrapper.new()
	var result = w.error_last()
	if result["status"] < 0:
		return "unexpected negative status"
	return ""

static func test_occtl_runtime_init_info_version_1():
	var w = OcctlCoreWrapper.new()
	var v = w.occtl_runtime_init_info_version_1()
	if v < 0:
		return "version should be non-negative"
	return ""

static func test_runtime_init_info_init():
	var w = OcctlCoreWrapper.new()
	var info = w.runtime_init_info_init()
	if info["struct_version"] != 1:
		return "Expected struct_version=1, got " + str(info["struct_version"])
	if info["p_next"] != 0:
		return "Expected p_next=0, got " + str(info["p_next"])
	return ""

static func test_runtime_init():
	var w = OcctlCoreWrapper.new()
	var result = w.runtime_init()
	if result != 0:
		return "runtime_init returned %d, expected 0" % result
	return ""

static func test_occtl_uid_invalid():
	var w = OcctlCoreWrapper.new()
	var bits = w.occtl_uid_invalid()
	if bits != 0:
		return "Expected OCCTL_UID_INVALID to be 0, got %d" % bits
	return ""

static func test_occtl_runtime_shutdown():
	var w = OcctlCoreWrapper.new()
	w.occtl_runtime_shutdown()
	return ""

static func test_occtl_runtime_abi_version():
	var w = OcctlCoreWrapper.new()
	var version = w.occtl_runtime_abi_version()
	if version < 0:
		return "expected non-negative version, got: " + str(version)
	return ""

static func test_runtime_occt_version():
	var w = OcctlCoreWrapper.new()
	var version = w.runtime_occt_version()
	if version == null or version == "":
		return "runtime_occt_version returned empty string"

static func test_occtl_uid_wire_size():
	var w = OcctlCoreWrapper.new()
	var size = w.occtl_uid_wire_size()
	if size < 0:
		return "expected non-negative size"
	return ""

static func test_uid_to_bytes():
	var w = OcctlCoreWrapper.new()
	var result = w.uid_to_bytes(0)
	if result["status"] != 0:
		return "Expected status 0 for uid_to_bytes"
	var bytes = result["bytes"]
	if bytes.size() != 16:
		return "Expected 16 bytes in result"
	return ""

static func test_uid_equal():
	var w = OcctlCoreWrapper.new()
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
	var w = OcctlCoreWrapper.new()
	var bytes = PackedByteArray()
	for i in range(16):
		bytes.append(0)
	var result = w.occtl_uid_from_bytes(bytes)
	if result["status"] != 0:
		return "Expected status 0, got " + str(result["status"])
	if result["uid_bits"] != 0:
		return "Expected uid_bits 0, got " + str(result["uid_bits"])
	return ""

