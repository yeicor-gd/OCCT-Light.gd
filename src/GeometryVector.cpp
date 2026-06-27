#include "GeometryVector.h"

#include "OCCTUtils.h"

#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

void GeometryVector::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_xyz", "x", "y", "z"), &GeometryVector::set_xyz);
    ClassDB::bind_method(D_METHOD("set_vector3", "vec"), &GeometryVector::set_vector3);
    ClassDB::bind_method(D_METHOD("get_vector3"), &GeometryVector::get_vector3);
    ClassDB::bind_method(D_METHOD("length"), &GeometryVector::length);
    ClassDB::bind_method(D_METHOD("dot", "other"), &GeometryVector::dot);
    ClassDB::bind_method(D_METHOD("add", "other"), &GeometryVector::add);
    ClassDB::bind_method(D_METHOD("subtract", "other"), &GeometryVector::subtract);
    ClassDB::bind_method(D_METHOD("cross", "other"), &GeometryVector::cross);
    ClassDB::bind_method(D_METHOD("scaled", "factor"), &GeometryVector::scaled);
}

GeometryVector::GeometryVector() :
        occt_vector(0.0, 0.0, 0.0) {}

Ref<GeometryVector> GeometryVector::from_occt(const gp_Vec &p_vec) {
    Ref<GeometryVector> result;
    result.instantiate();
    result->occt_vector = p_vec;
    return result;
}

void GeometryVector::set_xyz(double p_x, double p_y, double p_z) {
    occt_vector.SetCoord(p_x, p_y, p_z);
}

void GeometryVector::set_vector3(const Vector3 &p_vec) {
    occt_vector = occt_utils::to_occt_vec(p_vec);
}

Vector3 GeometryVector::get_vector3() const {
    return occt_utils::to_godot_vector3(occt_vector);
}

double GeometryVector::length() const {
    return occt_vector.Magnitude();
}

double GeometryVector::dot(const Ref<GeometryVector> &p_other) const {
    ERR_FAIL_COND_V_MSG(p_other.is_null(), 0.0, "GeometryVector.dot requires a non-null other vector.");
    try {
        return occt_vector.Dot(p_other->occt_vector);
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("GeometryVector.dot failed: %s", occt_utils::exception_to_string(e)));
        return 0.0;
    }
}

Ref<GeometryVector> GeometryVector::add(const Ref<GeometryVector> &p_other) const {
    ERR_FAIL_COND_V_MSG(p_other.is_null(), Ref<GeometryVector>(), "GeometryVector.add requires a non-null other vector.");
    try {
        return from_occt(occt_vector.Added(p_other->occt_vector));
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("GeometryVector.add failed: %s", occt_utils::exception_to_string(e)));
        return Ref<GeometryVector>();
    }
}

Ref<GeometryVector> GeometryVector::subtract(const Ref<GeometryVector> &p_other) const {
    ERR_FAIL_COND_V_MSG(p_other.is_null(), Ref<GeometryVector>(), "GeometryVector.subtract requires a non-null other vector.");
    try {
        return from_occt(occt_vector.Subtracted(p_other->occt_vector));
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("GeometryVector.subtract failed: %s", occt_utils::exception_to_string(e)));
        return Ref<GeometryVector>();
    }
}

Ref<GeometryVector> GeometryVector::cross(const Ref<GeometryVector> &p_other) const {
    ERR_FAIL_COND_V_MSG(p_other.is_null(), Ref<GeometryVector>(), "GeometryVector.cross requires a non-null other vector.");
    try {
        return from_occt(occt_vector.Crossed(p_other->occt_vector));
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("GeometryVector.cross failed: %s", occt_utils::exception_to_string(e)));
        return Ref<GeometryVector>();
    }
}

Ref<GeometryVector> GeometryVector::scaled(double p_factor) const {
    try {
        return from_occt(occt_vector.Multiplied(p_factor));
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("GeometryVector.scaled failed: %s", occt_utils::exception_to_string(e)));
        return Ref<GeometryVector>();
    }
}

const gp_Vec &GeometryVector::get_occt_vector() const {
    return occt_vector;
}
