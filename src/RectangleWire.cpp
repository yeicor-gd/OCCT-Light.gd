#include "RectangleWire.h"

#include "Plane.h"

#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

namespace {

Ref<CadPlane> default_xy_plane() {
    Ref<CadPlane> plane;
    plane.instantiate();
    plane->set_plane(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0));
    return plane;
}

Vector3 plane_point(const Ref<CadPlane> &p_plane, double p_u, double p_v) {
    return p_plane->get_origin()
        + p_plane->get_x_direction() * static_cast<real_t>(p_u)
        + p_plane->get_y_direction() * static_cast<real_t>(p_v);
}

} // namespace

void RectangleWire::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build_rectangle", "size", "plane", "centered"), &RectangleWire::build_rectangle, DEFVAL(Ref<CadPlane>()), DEFVAL(true));
}

RectangleWire::RectangleWire() = default;

void RectangleWire::build_rectangle(const Vector2 &p_size, const Ref<CadPlane> &p_plane, bool p_centered) {
    ERR_FAIL_COND_MSG(p_size.x <= 0.0 || p_size.y <= 0.0, "RectangleWire.build_rectangle requires positive size components.");

    Ref<CadPlane> plane = p_plane;
    if (plane.is_null()) {
        plane = default_xy_plane();
    }

    const double min_u = p_centered ? -static_cast<double>(p_size.x) * 0.5 : 0.0;
    const double min_v = p_centered ? -static_cast<double>(p_size.y) * 0.5 : 0.0;
    const double max_u = min_u + static_cast<double>(p_size.x);
    const double max_v = min_v + static_cast<double>(p_size.y);

    PackedVector3Array corners;
    corners.push_back(plane_point(plane, min_u, min_v));
    corners.push_back(plane_point(plane, max_u, min_v));
    corners.push_back(plane_point(plane, max_u, max_v));
    corners.push_back(plane_point(plane, min_u, max_v));
    build_polygon(corners, true);
}
