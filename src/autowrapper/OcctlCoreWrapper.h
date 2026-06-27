#ifndef OCCTLCOREWRAPPER_H
#define OCCTLCOREWRAPPER_H

#include <godot_cpp/classes/object.hpp> // NOLINT(misc-include-cleaner)
#include <godot_cpp/classes/ref.hpp> // NOLINT(misc-include-cleaner)
#include <godot_cpp/core/class_db.hpp> // NOLINT(misc-include-cleaner)
#include <godot_cpp/variant/callable.hpp> // NOLINT(misc-include-cleaner)
#include <godot_cpp/variant/array.hpp> // NOLINT(misc-include-cleaner)
#include <godot_cpp/variant/utility_functions.hpp> // NOLINT(misc-include-cleaner)
#include <cstdint> // NOLINT(misc-include-cleaner)
#include "occtl/occtl_core.h" // NOLINT(misc-include-cleaner)
#include "occtl_core.h" // NOLINT(misc-include-cleaner)

using namespace godot;

class Uint64THandle : public godot::RefCounted { // NOLINT(cppcoreguidelines-special-member-functions)
    GDCLASS(Uint64THandle, godot::RefCounted) // NOLINT
protected:
    static void _bind_methods() {
        godot::ClassDB::bind_method(godot::D_METHOD("set_handle", "handle"), &Uint64THandle::set_handle);
        godot::ClassDB::bind_method(godot::D_METHOD("get_handle"), &Uint64THandle::get_handle);
        godot::ClassDB::bind_method(godot::D_METHOD("is_valid"), &Uint64THandle::is_valid);
    }
public:
    uint64_t* handle = nullptr; // NOLINT
    void set_handle(int64_t _handle) { handle = reinterpret_cast<uint64_t*>(static_cast<uintptr_t>(_handle)); } // NOLINT
    [[nodiscard]] int64_t get_handle() const { return static_cast<int64_t>(reinterpret_cast<uintptr_t>(handle)); } // NOLINT
    [[nodiscard]] bool is_valid() const { return handle != nullptr; }
};

class OcctlRuntimeInitInfoTHandle : public godot::RefCounted { // NOLINT(cppcoreguidelines-special-member-functions)
    GDCLASS(OcctlRuntimeInitInfoTHandle, godot::RefCounted) // NOLINT
protected:
    static void _bind_methods() {
        godot::ClassDB::bind_method(godot::D_METHOD("set_handle", "handle"), &OcctlRuntimeInitInfoTHandle::set_handle);
        godot::ClassDB::bind_method(godot::D_METHOD("get_handle"), &OcctlRuntimeInitInfoTHandle::get_handle);
        godot::ClassDB::bind_method(godot::D_METHOD("is_valid"), &OcctlRuntimeInitInfoTHandle::is_valid);
    }
public:
    occtl_runtime_init_info_t* handle = nullptr; // NOLINT
    void set_handle(int64_t _handle) { handle = reinterpret_cast<occtl_runtime_init_info_t*>(static_cast<uintptr_t>(_handle)); } // NOLINT
    [[nodiscard]] int64_t get_handle() const { return static_cast<int64_t>(reinterpret_cast<uintptr_t>(handle)); } // NOLINT
    [[nodiscard]] bool is_valid() const { return handle != nullptr; }
};

class OcctlCoreWrapper : public godot::RefCounted { // NOLINT(cppcoreguidelines-special-member-functions, hicpp-special-member-functions)
    GDCLASS(OcctlCoreWrapper, godot::RefCounted) // NOLINT
protected:
    static void _bind_methods();
public:
    double occtl_pi(void); // NOLINT(readability-convert-member-functions-to-static)
    double occtl_two_pi(void); // NOLINT(readability-convert-member-functions-to-static)
    double occtl_pi_over_two(void); // NOLINT(readability-convert-member-functions-to-static)
    double occtl_rad_per_deg(void); // NOLINT(readability-convert-member-functions-to-static)
    double occtl_angle_5_deg_rad(void); // NOLINT(readability-convert-member-functions-to-static)
    float occtl_angle_30_deg_rad(void); // NOLINT(readability-convert-member-functions-to-static)
    float angle_20_deg_rad(void); // NOLINT(readability-convert-member-functions-to-static)
    int version_major(void); // NOLINT(readability-convert-member-functions-to-static)
    int version_minor(void); // NOLINT(readability-convert-member-functions-to-static)
    int version_patch(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_abi_version(void); // NOLINT(readability-convert-member-functions-to-static)
    double angle_90_deg_rad(void); // NOLINT(readability-convert-member-functions-to-static)
    double occtl_angle_1_deg_rad(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_ok(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_error(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_invalid_argument(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_invalid_handle(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_not_found(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_out_of_memory(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_out_of_range(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_not_done(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_geometry_invalid(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_topology_invalid(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_io_error(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_format_error(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_unsupported(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_cancelled(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_buffer_too_small(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_version_mismatch(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_internal(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_wrong_kind(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_status_reserved_future(void); // NOLINT(readability-convert-member-functions-to-static)
    String status_to_string(int status); // NOLINT(readability-convert-member-functions-to-static)
    bool occtl_succeeded(int status); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_kind_invalid(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_kind_solid(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_kind_shell(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_kind_face(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_kind_wire(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_kind_edge(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_kind_vertex(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_kind_compound(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_kind_compsolid(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_kind_coedge(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_kind_product(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_kind_occurrence(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_node_kind_reserved_future(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_rep_kind_invalid(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_rep_kind_surface(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_rep_kind_curve3d(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_rep_kind_curve2d(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_rep_kind_triangulation(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_rep_kind_polygon3d(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_rep_kind_polygon2d(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_rep_kind_polygon_on_tri(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_rep_kind_reserved_future(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_ref_kind_invalid(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_ref_kind_shell(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_ref_kind_face(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_ref_kind_wire(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_ref_kind_coedge(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_ref_kind_vertex(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_ref_kind_solid(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_ref_kind_child(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_ref_kind_occurrence(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_ref_kind_reserved_future(void); // NOLINT(readability-convert-member-functions-to-static)
    int64_t rep_id_invalid(void); // NOLINT(readability-convert-member-functions-to-static)
    Dictionary occtl_error_last(void); // NOLINT(readability-convert-member-functions-to-static)
    void occtl_error_clear(void); // NOLINT(readability-convert-member-functions-to-static)
    Dictionary error_last(void); // NOLINT(readability-convert-member-functions-to-static)
    int64_t occtl_runtime_init_info_version_1(void); // NOLINT(readability-convert-member-functions-to-static)
    Dictionary runtime_init_info_init(void); // NOLINT(readability-convert-member-functions-to-static)
    int runtime_init(void); // NOLINT(readability-convert-member-functions-to-static)
#ifdef __cplusplus
    int64_t occtl_uid_invalid(void); // NOLINT(readability-convert-member-functions-to-static)
#endif
    void occtl_runtime_shutdown(void); // NOLINT(readability-convert-member-functions-to-static)
    int64_t occtl_runtime_abi_version(void); // NOLINT(readability-convert-member-functions-to-static)
    String runtime_occt_version(void); // NOLINT(readability-convert-member-functions-to-static)
    int occtl_uid_wire_size(void); // NOLINT(readability-convert-member-functions-to-static)
    Dictionary uid_to_bytes(int64_t uid); // NOLINT(readability-convert-member-functions-to-static)
    int uid_equal(int64_t a, int64_t b); // NOLINT(readability-convert-member-functions-to-static)
    Dictionary occtl_uid_from_bytes(const PackedByteArray& in_bytes); // NOLINT(readability-convert-member-functions-to-static)
};


#endif // OCCTLCOREWRAPPER_H
