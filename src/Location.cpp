#include "Location.h"

#include "Axis.h"
#include "OCCTUtils.h"

#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

void Location::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_identity"), &Location::set_identity);
    ClassDB::bind_method(D_METHOD("set_translation", "offset"), &Location::set_translation);
    ClassDB::bind_method(D_METHOD("set_rotation", "axis", "angle_radians"), &Location::set_rotation);
    ClassDB::bind_method(D_METHOD("set_scale", "center", "factor"), &Location::set_scale);
    ClassDB::bind_method(D_METHOD("multiplied", "other"), &Location::multiplied);
    ClassDB::bind_method(D_METHOD("inverted"), &Location::inverted);
    ClassDB::bind_method(D_METHOD("transform_point", "point"), &Location::transform_point);
    ClassDB::bind_method(D_METHOD("transform_vector", "vector"), &Location::transform_vector);
}

Location::Location() {
    occt_transform = gp_Trsf();
}

void Location::set_identity() {
    occt_transform = gp_Trsf();
}

void Location::set_translation(const Vector3 &p_offset) {
    try {
        occt_transform.SetTranslation(occt_utils::to_occt_vec(p_offset));
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Location.set_translation failed: %s", occt_utils::exception_to_string(failure)));
    }
}

void Location::set_rotation(const Ref<Axis> &p_axis, double p_angle_radians) {
    ERR_FAIL_COND_MSG(p_axis.is_null(), "Location.set_rotation requires a non-null axis.");

    try {
        occt_transform.SetRotation(p_axis->get_occt_axis(), p_angle_radians);
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Location.set_rotation failed: %s", occt_utils::exception_to_string(failure)));
    }
}

void Location::set_scale(const Vector3 &p_center, double p_factor) {
    ERR_FAIL_COND_MSG(p_factor == 0.0, "Location.set_scale requires a non-zero factor.");

    try {
        occt_transform.SetScale(occt_utils::to_occt_point(p_center), p_factor);
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Location.set_scale failed: %s", occt_utils::exception_to_string(failure)));
    }
}

Ref<Location> Location::multiplied(const Ref<Location> &p_other) const {
    ERR_FAIL_COND_V_MSG(p_other.is_null(), Ref<Location>(), "Location.multiplied requires a non-null other location.");

    try {
        Ref<Location> result;
        result.instantiate();
        gp_Trsf combined = occt_transform;
        combined.Multiply(p_other->occt_transform);
        result->set_occt_transform(combined);
        return result;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Location.multiplied failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<Location>();
    }
}

Ref<Location> Location::inverted() const {
    try {
        Ref<Location> result;
        result.instantiate();
        gp_Trsf inverse = occt_transform;
        inverse.Invert();
        result->set_occt_transform(inverse);
        return result;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Location.inverted failed: %s", occt_utils::exception_to_string(failure)));
        return Ref<Location>();
    }
}

Vector3 Location::transform_point(const Vector3 &p_point) const {
    try {
        return occt_utils::to_godot_vector3(occt_utils::to_occt_point(p_point).Transformed(occt_transform));
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Location.transform_point failed: %s", occt_utils::exception_to_string(failure)));
        return Vector3();
    }
}

Vector3 Location::transform_vector(const Vector3 &p_vector) const {
    try {
        return occt_utils::to_godot_vector3(occt_utils::to_occt_vec(p_vector).Transformed(occt_transform));
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Location.transform_vector failed: %s", occt_utils::exception_to_string(failure)));
        return Vector3();
    }
}

void Location::set_occt_transform(const gp_Trsf &p_transform) {
    occt_transform = p_transform;
}

const gp_Trsf &Location::get_occt_transform() const {
    return occt_transform;
}
