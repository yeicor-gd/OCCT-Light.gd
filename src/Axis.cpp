#include "Axis.h"

#include "Location.h"
#include "OCCTUtils.h"

#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

void Axis::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_axis", "origin", "direction"), &Axis::set_axis);
    ClassDB::bind_method(D_METHOD("get_origin"), &Axis::get_origin);
    ClassDB::bind_method(D_METHOD("get_direction"), &Axis::get_direction);
    ClassDB::bind_method(D_METHOD("reversed"), &Axis::reversed);
    ClassDB::bind_method(D_METHOD("transformed", "location"), &Axis::transformed);
}

Axis::Axis() :
        occt_axis(gp_Pnt(0.0, 0.0, 0.0), gp_Dir(0.0, 0.0, 1.0)) {}

void Axis::set_axis(const Vector3 &p_origin, const Vector3 &p_direction) {
    ERR_FAIL_COND_MSG(p_direction.length() == 0.0, "Axis.set_axis requires a non-zero direction.");

    try {
        occt_axis = gp_Ax1(occt_utils::to_occt_point(p_origin), occt_utils::to_occt_dir(p_direction));
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Axis.set_axis failed: %s", occt_utils::exception_to_string(failure)));
    }
}

Vector3 Axis::get_origin() const {
    return occt_utils::to_godot_vector3(occt_axis.Location());
}

Vector3 Axis::get_direction() const {
    return occt_utils::to_godot_vector3(occt_axis.Direction());
}

Ref<Axis> Axis::reversed() const {
    Ref<Axis> result;
    result.instantiate();
    result->set_occt_axis(occt_axis.Reversed());
    return result;
}

Ref<Axis> Axis::transformed(const Ref<Location> &p_location) const {
    ERR_FAIL_COND_V_MSG(p_location.is_null(), Ref<Axis>(), "Axis.transformed requires a non-null location.");

    try {
        Ref<Axis> result;
        result.instantiate();
        result->set_occt_axis(occt_axis.Transformed(p_location->get_occt_transform()));
        return result;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Axis.transformed failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<Axis>();
    }
}

void Axis::set_occt_axis(const gp_Ax1 &p_axis) {
    occt_axis = p_axis;
}

const gp_Ax1 &Axis::get_occt_axis() const {
    return occt_axis;
}
