#include "RegularPolygonWire.h"

#include "Plane.h"

#include <godot_cpp/core/error_macros.hpp>

#include <cmath>

using namespace godot;

namespace {

Ref<CadPlane> default_xy_plane() {
    Ref<CadPlane> plane;
    plane.instantiate();
    plane->set_plane(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0));
    return plane;
}

} // namespace

void RegularPolygonWire::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build_regular_polygon", "radius", "side_count", "plane", "start_angle_radians"), &RegularPolygonWire::build_regular_polygon, DEFVAL(Ref<CadPlane>()), DEFVAL(0.0));
}

RegularPolygonWire::RegularPolygonWire() = default;

void RegularPolygonWire::build_regular_polygon(double p_radius, int p_side_count, const Ref<CadPlane> &p_plane, double p_start_angle_radians) {
    ERR_FAIL_COND_MSG(p_radius <= 0.0, vformat("RegularPolygonWire.build_regular_polygon: requires a positive radius, got %f", p_radius));
    ERR_FAIL_COND_MSG(p_side_count < 3, vformat("RegularPolygonWire.build_regular_polygon: requires at least 3 sides, got %d", p_side_count));

    Ref<CadPlane> plane = p_plane;
    if (plane.is_null()) {
        plane = default_xy_plane();
    }

    PackedVector3Array corners;
    corners.resize(p_side_count);

    const double angle_step = Math_TAU / static_cast<double>(p_side_count);
    const Vector3 origin = plane->get_origin();
    const Vector3 x_direction = plane->get_x_direction();
    const Vector3 y_direction = plane->get_y_direction();
    for (int index = 0; index < p_side_count; ++index) {
        const double angle = p_start_angle_radians + angle_step * static_cast<double>(index);
        corners.set(index, origin
            + x_direction * static_cast<real_t>(std::cos(angle) * p_radius)
            + y_direction * static_cast<real_t>(std::sin(angle) * p_radius));
    }

    build_polygon(corners, true);
}
