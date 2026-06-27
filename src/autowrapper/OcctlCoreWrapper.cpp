#include "OcctlCoreWrapper.h" // NOLINT(misc-include-cleaner)

#include <godot_cpp/classes/ref.hpp> // NOLINT(misc-include-cleaner)
#include <godot_cpp/core/class_db.hpp> // NOLINT(misc-include-cleaner)
#include <godot_cpp/variant/string.hpp> // NOLINT(misc-include-cleaner)
#include <cstdint> // NOLINT(misc-include-cleaner)
#include "occtl/occtl_core.h" // NOLINT(misc-include-cleaner)
#include "occtl_core.h" // NOLINT(misc-include-cleaner)

void OcctlCoreWrapper::_bind_methods() {
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_pi"), &OcctlCoreWrapper::occtl_pi);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_two_pi"), &OcctlCoreWrapper::occtl_two_pi);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_pi_over_two"), &OcctlCoreWrapper::occtl_pi_over_two);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_rad_per_deg"), &OcctlCoreWrapper::occtl_rad_per_deg);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_angle_5_deg_rad"), &OcctlCoreWrapper::occtl_angle_5_deg_rad);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_angle_30_deg_rad"), &OcctlCoreWrapper::occtl_angle_30_deg_rad);
    godot::ClassDB::bind_method(godot::D_METHOD("angle_20_deg_rad"), &OcctlCoreWrapper::angle_20_deg_rad);
    godot::ClassDB::bind_method(godot::D_METHOD("version_major"), &OcctlCoreWrapper::version_major);
    godot::ClassDB::bind_method(godot::D_METHOD("version_minor"), &OcctlCoreWrapper::version_minor);
    godot::ClassDB::bind_method(godot::D_METHOD("version_patch"), &OcctlCoreWrapper::version_patch);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_abi_version"), &OcctlCoreWrapper::occtl_abi_version);
    godot::ClassDB::bind_method(godot::D_METHOD("angle_90_deg_rad"), &OcctlCoreWrapper::angle_90_deg_rad);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_angle_1_deg_rad"), &OcctlCoreWrapper::occtl_angle_1_deg_rad);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_ok"), &OcctlCoreWrapper::occtl_ok);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_error"), &OcctlCoreWrapper::occtl_error);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_invalid_argument"), &OcctlCoreWrapper::occtl_invalid_argument);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_invalid_handle"), &OcctlCoreWrapper::occtl_invalid_handle);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_not_found"), &OcctlCoreWrapper::occtl_not_found);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_out_of_memory"), &OcctlCoreWrapper::occtl_out_of_memory);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_out_of_range"), &OcctlCoreWrapper::occtl_out_of_range);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_not_done"), &OcctlCoreWrapper::occtl_not_done);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_geometry_invalid"), &OcctlCoreWrapper::occtl_geometry_invalid);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_topology_invalid"), &OcctlCoreWrapper::occtl_topology_invalid);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_io_error"), &OcctlCoreWrapper::occtl_io_error);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_format_error"), &OcctlCoreWrapper::occtl_format_error);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_unsupported"), &OcctlCoreWrapper::occtl_unsupported);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_cancelled"), &OcctlCoreWrapper::occtl_cancelled);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_buffer_too_small"), &OcctlCoreWrapper::occtl_buffer_too_small);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_version_mismatch"), &OcctlCoreWrapper::occtl_version_mismatch);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_internal"), &OcctlCoreWrapper::occtl_internal);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_wrong_kind"), &OcctlCoreWrapper::occtl_wrong_kind);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_status_reserved_future"), &OcctlCoreWrapper::occtl_status_reserved_future);
    godot::ClassDB::bind_method(godot::D_METHOD("status_to_string", "status"), &OcctlCoreWrapper::status_to_string);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_succeeded", "status"), &OcctlCoreWrapper::occtl_succeeded);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_kind_invalid"), &OcctlCoreWrapper::occtl_kind_invalid);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_kind_solid"), &OcctlCoreWrapper::occtl_kind_solid);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_kind_shell"), &OcctlCoreWrapper::occtl_kind_shell);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_kind_face"), &OcctlCoreWrapper::occtl_kind_face);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_kind_wire"), &OcctlCoreWrapper::occtl_kind_wire);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_kind_edge"), &OcctlCoreWrapper::occtl_kind_edge);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_kind_vertex"), &OcctlCoreWrapper::occtl_kind_vertex);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_kind_compound"), &OcctlCoreWrapper::occtl_kind_compound);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_kind_compsolid"), &OcctlCoreWrapper::occtl_kind_compsolid);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_kind_coedge"), &OcctlCoreWrapper::occtl_kind_coedge);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_kind_product"), &OcctlCoreWrapper::occtl_kind_product);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_kind_occurrence"), &OcctlCoreWrapper::occtl_kind_occurrence);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_node_kind_reserved_future"), &OcctlCoreWrapper::occtl_node_kind_reserved_future);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_rep_kind_invalid"), &OcctlCoreWrapper::occtl_rep_kind_invalid);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_rep_kind_surface"), &OcctlCoreWrapper::occtl_rep_kind_surface);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_rep_kind_curve3d"), &OcctlCoreWrapper::occtl_rep_kind_curve3d);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_rep_kind_curve2d"), &OcctlCoreWrapper::occtl_rep_kind_curve2d);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_rep_kind_triangulation"), &OcctlCoreWrapper::occtl_rep_kind_triangulation);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_rep_kind_polygon3d"), &OcctlCoreWrapper::occtl_rep_kind_polygon3d);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_rep_kind_polygon2d"), &OcctlCoreWrapper::occtl_rep_kind_polygon2d);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_rep_kind_polygon_on_tri"), &OcctlCoreWrapper::occtl_rep_kind_polygon_on_tri);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_rep_kind_reserved_future"), &OcctlCoreWrapper::occtl_rep_kind_reserved_future);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_ref_kind_invalid"), &OcctlCoreWrapper::occtl_ref_kind_invalid);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_ref_kind_shell"), &OcctlCoreWrapper::occtl_ref_kind_shell);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_ref_kind_face"), &OcctlCoreWrapper::occtl_ref_kind_face);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_ref_kind_wire"), &OcctlCoreWrapper::occtl_ref_kind_wire);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_ref_kind_coedge"), &OcctlCoreWrapper::occtl_ref_kind_coedge);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_ref_kind_vertex"), &OcctlCoreWrapper::occtl_ref_kind_vertex);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_ref_kind_solid"), &OcctlCoreWrapper::occtl_ref_kind_solid);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_ref_kind_child"), &OcctlCoreWrapper::occtl_ref_kind_child);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_ref_kind_occurrence"), &OcctlCoreWrapper::occtl_ref_kind_occurrence);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_ref_kind_reserved_future"), &OcctlCoreWrapper::occtl_ref_kind_reserved_future);
    godot::ClassDB::bind_method(godot::D_METHOD("rep_id_invalid"), &OcctlCoreWrapper::rep_id_invalid);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_error_last"), &OcctlCoreWrapper::occtl_error_last);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_error_clear"), &OcctlCoreWrapper::occtl_error_clear);
    godot::ClassDB::bind_method(godot::D_METHOD("error_last"), &OcctlCoreWrapper::error_last);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_runtime_init_info_version_1"), &OcctlCoreWrapper::occtl_runtime_init_info_version_1);
    godot::ClassDB::bind_method(godot::D_METHOD("runtime_init_info_init"), &OcctlCoreWrapper::runtime_init_info_init);
    godot::ClassDB::bind_method(godot::D_METHOD("runtime_init"), &OcctlCoreWrapper::runtime_init);
#ifdef __cplusplus
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_uid_invalid"), &OcctlCoreWrapper::occtl_uid_invalid);
#endif
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_runtime_shutdown"), &OcctlCoreWrapper::occtl_runtime_shutdown);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_runtime_abi_version"), &OcctlCoreWrapper::occtl_runtime_abi_version);
    godot::ClassDB::bind_method(godot::D_METHOD("runtime_occt_version"), &OcctlCoreWrapper::runtime_occt_version);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_uid_wire_size"), &OcctlCoreWrapper::occtl_uid_wire_size);
    godot::ClassDB::bind_method(godot::D_METHOD("uid_to_bytes", "uid"), &OcctlCoreWrapper::uid_to_bytes);
    godot::ClassDB::bind_method(godot::D_METHOD("uid_equal", "a", "b"), &OcctlCoreWrapper::uid_equal);
    godot::ClassDB::bind_method(godot::D_METHOD("occtl_uid_from_bytes", "in_bytes"), &OcctlCoreWrapper::occtl_uid_from_bytes);
}

double OcctlCoreWrapper::occtl_pi(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_PI;
}

double OcctlCoreWrapper::occtl_two_pi(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 2.0 * OCCTL_PI;
}

double OcctlCoreWrapper::occtl_pi_over_two(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 0.5 * OCCTL_PI;
}

double OcctlCoreWrapper::occtl_rad_per_deg(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_RAD_PER_DEG;
}

double OcctlCoreWrapper::occtl_angle_5_deg_rad(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 5.0 * OCCTL_RAD_PER_DEG;
}

float OcctlCoreWrapper::occtl_angle_30_deg_rad(void) { // NOLINT(readability-convert-member-functions-to-static)
    return (float)(30.0 * OCCTL_RAD_PER_DEG);
}

float OcctlCoreWrapper::angle_20_deg_rad(void) { // NOLINT(readability-convert-member-functions-to-static)
    return (20.0 * OCCTL_RAD_PER_DEG);
}

int OcctlCoreWrapper::version_major(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_VERSION_MAJOR;
}

int OcctlCoreWrapper::version_minor(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_VERSION_MINOR;
}

int OcctlCoreWrapper::version_patch(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_VERSION_PATCH;
}

int OcctlCoreWrapper::occtl_abi_version(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 1;
}

double OcctlCoreWrapper::angle_90_deg_rad(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_ANGLE_90_DEG_RAD;
}

double OcctlCoreWrapper::occtl_angle_1_deg_rad(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_RAD_PER_DEG;
}

int OcctlCoreWrapper::occtl_ok(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_OK);
}

int OcctlCoreWrapper::occtl_error(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_ERROR);
}

int OcctlCoreWrapper::occtl_invalid_argument(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_INVALID_ARGUMENT);
}

int OcctlCoreWrapper::occtl_invalid_handle(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_INVALID_HANDLE);
}

int OcctlCoreWrapper::occtl_not_found(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_NOT_FOUND);
}

int OcctlCoreWrapper::occtl_out_of_memory(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_OUT_OF_MEMORY);
}

int OcctlCoreWrapper::occtl_out_of_range(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_OUT_OF_RANGE);
}

int OcctlCoreWrapper::occtl_not_done(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_NOT_DONE);
}

int OcctlCoreWrapper::occtl_geometry_invalid(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_GEOMETRY_INVALID);
}

int OcctlCoreWrapper::occtl_topology_invalid(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_TOPOLOGY_INVALID);
}

int OcctlCoreWrapper::occtl_io_error(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_IO_ERROR);
}

int OcctlCoreWrapper::occtl_format_error(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_FORMAT_ERROR);
}

int OcctlCoreWrapper::occtl_unsupported(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_UNSUPPORTED);
}

int OcctlCoreWrapper::occtl_cancelled(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_CANCELLED);
}

int OcctlCoreWrapper::occtl_buffer_too_small(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_BUFFER_TOO_SMALL);
}

int OcctlCoreWrapper::occtl_version_mismatch(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_VERSION_MISMATCH);
}

int OcctlCoreWrapper::occtl_internal(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_INTERNAL);
}

int OcctlCoreWrapper::occtl_wrong_kind(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_WRONG_KIND);
}

int OcctlCoreWrapper::occtl_status_reserved_future(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(OCCTL_STATUS_RESERVED_FUTURE);
}

String OcctlCoreWrapper::status_to_string(int status) { // NOLINT(readability-convert-member-functions-to-static)
    occtl_status_t s = static_cast<occtl_status_t>(status);
    const char* result = ::occtl_status_to_string(s);
    return String(result);
}

bool OcctlCoreWrapper::occtl_succeeded(int status) { // NOLINT(readability-convert-member-functions-to-static)
    return status == 0;
}

int OcctlCoreWrapper::occtl_kind_invalid(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 0;
}

int OcctlCoreWrapper::occtl_kind_solid(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 1;
}

int OcctlCoreWrapper::occtl_kind_shell(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 2;
}

int OcctlCoreWrapper::occtl_kind_face(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 3;
}

int OcctlCoreWrapper::occtl_kind_wire(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 4;
}

int OcctlCoreWrapper::occtl_kind_edge(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 5;
}

int OcctlCoreWrapper::occtl_kind_vertex(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 6;
}

int OcctlCoreWrapper::occtl_kind_compound(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 7;
}

int OcctlCoreWrapper::occtl_kind_compsolid(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 8;
}

int OcctlCoreWrapper::occtl_kind_coedge(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 9;
}

int OcctlCoreWrapper::occtl_kind_product(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 10;
}

int OcctlCoreWrapper::occtl_kind_occurrence(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 11;
}

int OcctlCoreWrapper::occtl_node_kind_reserved_future(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 2147483647;
}

int OcctlCoreWrapper::occtl_rep_kind_invalid(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_REP_KIND_INVALID;
}

int OcctlCoreWrapper::occtl_rep_kind_surface(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_REP_KIND_SURFACE;
}

int OcctlCoreWrapper::occtl_rep_kind_curve3d(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_REP_KIND_CURVE3D;
}

int OcctlCoreWrapper::occtl_rep_kind_curve2d(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_REP_KIND_CURVE2D;
}

int OcctlCoreWrapper::occtl_rep_kind_triangulation(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_REP_KIND_TRIANGULATION;
}

int OcctlCoreWrapper::occtl_rep_kind_polygon3d(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_REP_KIND_POLYGON3D;
}

int OcctlCoreWrapper::occtl_rep_kind_polygon2d(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_REP_KIND_POLYGON2D;
}

int OcctlCoreWrapper::occtl_rep_kind_polygon_on_tri(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_REP_KIND_POLYGON_ON_TRI;
}

int OcctlCoreWrapper::occtl_rep_kind_reserved_future(void) { // NOLINT(readability-convert-member-functions-to-static)
    return OCCTL_REP_KIND_RESERVED_FUTURE;
}

int OcctlCoreWrapper::occtl_ref_kind_invalid(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 0;
}

int OcctlCoreWrapper::occtl_ref_kind_shell(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 1;
}

int OcctlCoreWrapper::occtl_ref_kind_face(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 2;
}

int OcctlCoreWrapper::occtl_ref_kind_wire(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 3;
}

int OcctlCoreWrapper::occtl_ref_kind_coedge(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 4;
}

int OcctlCoreWrapper::occtl_ref_kind_vertex(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 5;
}

int OcctlCoreWrapper::occtl_ref_kind_solid(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 6;
}

int OcctlCoreWrapper::occtl_ref_kind_child(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 7;
}

int OcctlCoreWrapper::occtl_ref_kind_occurrence(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 8;
}

int OcctlCoreWrapper::occtl_ref_kind_reserved_future(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 2147483647;
}

int64_t OcctlCoreWrapper::rep_id_invalid(void) { // NOLINT(readability-convert-member-functions-to-static)
    occtl_rep_id_t val = {};
    return static_cast<int64_t>(val.bits);
}

Dictionary OcctlCoreWrapper::occtl_error_last(void) { // NOLINT(readability-convert-member-functions-to-static)
    const occtl_error_t* err = ::occtl_error_last();
    Dictionary d;
    d["status"] = static_cast<int>(err->status);
    d["message"] = String(err->message);
    d["source_bits"] = static_cast<int64_t>(err->source.bits);
    d["extended"] = static_cast<int64_t>(err->extended);
    return d;
}

void OcctlCoreWrapper::occtl_error_clear(void) { // NOLINT(readability-convert-member-functions-to-static)
    ::occtl_error_clear();
}

Dictionary OcctlCoreWrapper::error_last(void) { // NOLINT(readability-convert-member-functions-to-static)
    const occtl_error_t* err = ::occtl_error_last();
    Dictionary d;
    d["status"] = static_cast<int64_t>(err->status);
    d["message"] = String(err->message);
    d["source"] = static_cast<int64_t>(err->source.bits);
    d["extended"] = static_cast<int64_t>(err->extended);
    return d;
}

int64_t OcctlCoreWrapper::occtl_runtime_init_info_version_1(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int64_t>(OCCTL_RUNTIME_INIT_INFO_VERSION_1);
}

Dictionary OcctlCoreWrapper::runtime_init_info_init(void) { // NOLINT(readability-convert-member-functions-to-static)
    Dictionary d;
      d["struct_version"] = static_cast<int64_t>(OCCTL_RUNTIME_INIT_INFO_VERSION_1);
      d["p_next"] = static_cast<int64_t>(0);
      return d;
}

int OcctlCoreWrapper::runtime_init(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int>(::occtl_runtime_init(nullptr));
}

#ifdef __cplusplus
int64_t OcctlCoreWrapper::occtl_uid_invalid(void) { // NOLINT(readability-convert-member-functions-to-static)
    occtl_uid_t uid = {0};
    return static_cast<int64_t>(uid.bits);
}
#endif

void OcctlCoreWrapper::occtl_runtime_shutdown(void) { // NOLINT(readability-convert-member-functions-to-static)
    ::occtl_runtime_shutdown();
}

int64_t OcctlCoreWrapper::occtl_runtime_abi_version(void) { // NOLINT(readability-convert-member-functions-to-static)
    return static_cast<int64_t>(::occtl_runtime_abi_version());
}

String OcctlCoreWrapper::runtime_occt_version(void) { // NOLINT(readability-convert-member-functions-to-static)
    return String(::occtl_runtime_occt_version());
}

int OcctlCoreWrapper::occtl_uid_wire_size(void) { // NOLINT(readability-convert-member-functions-to-static)
    return 16;
}

Dictionary OcctlCoreWrapper::uid_to_bytes(int64_t uid) { // NOLINT(readability-convert-member-functions-to-static)
    uint8_t bytes[16] = {};
    occtl_uid_t uid_val = {static_cast<uint64_t>(uid)};
    occtl_status_t status = ::occtl_uid_to_bytes(uid_val, bytes);
    Dictionary d;
    d["status"] = static_cast<int>(status);
    if (status != OCCTL_OK) {
        return d;
    }
    PackedByteArray arr;
    arr.resize(16);
    for (int i = 0; i < 16; i++) arr.set(i, bytes[i]);
    d["bytes"] = arr;
    return d;
}

int OcctlCoreWrapper::uid_equal(int64_t a, int64_t b) { // NOLINT(readability-convert-member-functions-to-static)
    occtl_uid_t ua = {0};
    ua.bits = static_cast<uint64_t>(a);
    occtl_uid_t ub = {0};
    ub.bits = static_cast<uint64_t>(b);
    return static_cast<int>(::occtl_uid_equal(ua, ub));
}

Dictionary OcctlCoreWrapper::occtl_uid_from_bytes(const PackedByteArray& in_bytes) { // NOLINT(readability-convert-member-functions-to-static)
    occtl_uid_t uid = {};
    int status = static_cast<int>(::occtl_uid_from_bytes(in_bytes.ptr(), &uid));
    Dictionary d;
    d["status"] = status;
    d["uid_bits"] = static_cast<int64_t>(uid.bits);
    return d;
}
