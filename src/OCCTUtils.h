#ifndef OCCT_UTILS_H
#define OCCT_UTILS_H

#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <Standard_Failure.hxx>
#include <gp_Dir.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>

namespace occt_utils {

    inline godot::String exception_to_string(const Standard_Failure &p_failure) {
        const char* message = p_failure.what();
        const char* stack_trace = p_failure.GetStackString();
        godot::String result;
        if (message == nullptr || message[0] == '\0') {
            result = godot::String("OpenCASCADE operation failed");
        } else {
            result = godot::String(message);
        }
        if (stack_trace != nullptr && stack_trace[0] != '\0') {
            result += "\nStack trace:\n";
            result += godot::String(stack_trace);
        }
        return result;
    }

inline godot::Vector3 to_godot_vector3(const gp_Vec &p_vec) {
    return godot::Vector3(
        static_cast<godot::real_t>(p_vec.X()),
        static_cast<godot::real_t>(p_vec.Y()),
        static_cast<godot::real_t>(p_vec.Z())
    );
}

inline godot::Vector3 to_godot_vector3(const gp_Pnt &p_point) {
    return godot::Vector3(
        static_cast<godot::real_t>(p_point.X()),
        static_cast<godot::real_t>(p_point.Y()),
        static_cast<godot::real_t>(p_point.Z())
    );
}

inline godot::Vector3 to_godot_vector3(const gp_Dir &p_dir) {
    return godot::Vector3(
        static_cast<godot::real_t>(p_dir.X()),
        static_cast<godot::real_t>(p_dir.Y()),
        static_cast<godot::real_t>(p_dir.Z())
    );
}

inline gp_Vec to_occt_vec(const godot::Vector3 &p_vec) {
    return gp_Vec(
        static_cast<double>(p_vec.x),
        static_cast<double>(p_vec.y),
        static_cast<double>(p_vec.z)
    );
}

inline gp_Pnt to_occt_point(const godot::Vector3 &p_point) {
    return gp_Pnt(
        static_cast<double>(p_point.x),
        static_cast<double>(p_point.y),
        static_cast<double>(p_point.z)
    );
}

inline gp_Dir to_occt_dir(const godot::Vector3 &p_direction) {
    return gp_Dir(
        static_cast<double>(p_direction.x),
        static_cast<double>(p_direction.y),
        static_cast<double>(p_direction.z)
    );
}

} // namespace occt_utils

#endif // OCCT_UTILS_H
