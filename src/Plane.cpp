#include "Plane.h"

#include "Location.h"
#include "OCCTUtils.h"

#include <godot_cpp/core/error_macros.hpp>

#include <gp_Ax3.hxx>
#include <gp_Dir.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>

#include <cmath>

namespace {

bool is_valid_x_direction(const godot::Vector3 &p_normal, const godot::Vector3 &p_x_direction) {
    return p_x_direction.length() > 0.0 && std::abs(p_normal.normalized().dot(p_x_direction.normalized())) < 0.999;
}

} // namespace

void CadPlane::_bind_methods() {
    godot::ClassDB::bind_method(godot::D_METHOD("set_plane", "origin", "normal", "x_direction"), &CadPlane::set_plane, DEFVAL(godot::Vector3(1.0, 0.0, 0.0)));
    godot::ClassDB::bind_method(godot::D_METHOD("get_origin"), &CadPlane::get_origin);
    godot::ClassDB::bind_method(godot::D_METHOD("get_normal"), &CadPlane::get_normal);
    godot::ClassDB::bind_method(godot::D_METHOD("get_x_direction"), &CadPlane::get_x_direction);
    godot::ClassDB::bind_method(godot::D_METHOD("get_y_direction"), &CadPlane::get_y_direction);
    godot::ClassDB::bind_method(godot::D_METHOD("signed_distance_to_point", "point"), &CadPlane::signed_distance_to_point);
    godot::ClassDB::bind_method(godot::D_METHOD("project_point", "point"), &CadPlane::project_point);
    godot::ClassDB::bind_method(godot::D_METHOD("offsetted", "distance"), &CadPlane::offsetted);
    godot::ClassDB::bind_method(godot::D_METHOD("transformed", "location"), &CadPlane::transformed);
}

CadPlane::CadPlane() = default;

void CadPlane::set_plane(const godot::Vector3 &p_origin, const godot::Vector3 &p_normal, const godot::Vector3 &p_x_direction) {
    ERR_FAIL_COND_MSG(p_normal.length() == 0.0, "Plane.set_plane requires a non-zero normal.");

    try {
        const gp_Pnt origin = occt_utils::to_occt_point(p_origin);
        const gp_Dir normal = occt_utils::to_occt_dir(p_normal);
        if (is_valid_x_direction(p_normal, p_x_direction)) {
            occt_plane = gp_Pln(gp_Ax3(origin, normal, occt_utils::to_occt_dir(p_x_direction)));
        } else {
            occt_plane = gp_Pln(origin, normal);
        }
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("CadPlane.set_plane failed: %s", occt_utils::exception_to_string(failure)));
    }
}

godot::Vector3 CadPlane::get_origin() const {
    return occt_utils::to_godot_vector3(occt_plane.Location());
}

godot::Vector3 CadPlane::get_normal() const {
    return occt_utils::to_godot_vector3(occt_plane.Axis().Direction());
}

godot::Vector3 CadPlane::get_x_direction() const {
    return occt_utils::to_godot_vector3(occt_plane.Position().XDirection());
}

godot::Vector3 CadPlane::get_y_direction() const {
    return occt_utils::to_godot_vector3(occt_plane.Position().YDirection());
}

double CadPlane::signed_distance_to_point(const godot::Vector3 &p_point) const {
    const gp_Pnt plane_origin = occt_plane.Location();
    const gp_Dir plane_normal = occt_plane.Axis().Direction();
    const gp_Vec offset(plane_origin, occt_utils::to_occt_point(p_point));
    return offset.Dot(gp_Vec(plane_normal));
}

godot::Vector3 CadPlane::project_point(const godot::Vector3 &p_point) const {
    try {
        const double signed_distance = signed_distance_to_point(p_point);
        const gp_Pnt point = occt_utils::to_occt_point(p_point);
        const gp_Vec correction(gp_Vec(occt_plane.Axis().Direction()) * (-signed_distance));
        return occt_utils::to_godot_vector3(point.Translated(correction));
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("CadPlane.project_point failed: %s", occt_utils::exception_to_string(failure)));
        return godot::Vector3();
    }
}

godot::Ref<CadPlane> CadPlane::offsetted(double p_distance) const {
    try {
        godot::Ref<CadPlane> result;
        result.instantiate();
        result->set_occt_plane(occt_plane.Translated(gp_Vec(occt_plane.Axis().Direction()) * p_distance));
        return result;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("CadPlane.offsetted failed: %s", occt_utils::exception_to_string(failure)));
        return godot::Ref<CadPlane>();
    }
}

godot::Ref<CadPlane> CadPlane::transformed(const godot::Ref<Location> &p_location) const {
    ERR_FAIL_COND_V_MSG(p_location.is_null(), godot::Ref<CadPlane>(), "CadPlane.transformed requires a non-null location.");

    try {
        godot::Ref<CadPlane> result;
        result.instantiate();
        gp_Pln transformed = occt_plane;
        transformed.Transform(p_location->get_occt_transform());
        result->set_occt_plane(transformed);
        return result;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("CadPlane.transformed failed: %s", occt_utils::exception_to_string(failure)));
        return godot::Ref<CadPlane>();
    }
}

void CadPlane::set_occt_plane(const gp_Pln &p_plane) {
    occt_plane = p_plane;
}

const gp_Pln &CadPlane::get_occt_plane() const {
    return occt_plane;
}
