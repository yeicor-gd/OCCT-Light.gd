#include "EllipseWire.h"

#include "Plane.h"
#include "OCCTUtils.h"

#include <godot_cpp/core/error_macros.hpp>

#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <gp_Ax2.hxx>
#include <gp_Elips.hxx>

using namespace godot;

namespace {

Ref<CadPlane> default_xy_plane() {
    Ref<CadPlane> plane;
    plane.instantiate();
    plane->set_plane(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0));
    return plane;
}

} // namespace

void EllipseWire::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build_ellipse", "major_radius", "minor_radius", "plane"), &EllipseWire::build_ellipse, DEFVAL(Ref<CadPlane>()));
}

EllipseWire::EllipseWire() = default;

void EllipseWire::build_ellipse(double p_major_radius, double p_minor_radius, const Ref<CadPlane> &p_plane) {
    ERR_FAIL_COND_MSG(p_major_radius <= 0.0, "EllipseWire.build_ellipse requires a positive major radius.");
    ERR_FAIL_COND_MSG(p_minor_radius <= 0.0, "EllipseWire.build_ellipse requires a positive minor radius.");
    ERR_FAIL_COND_MSG(p_minor_radius > p_major_radius, "EllipseWire.build_ellipse requires minor_radius <= major_radius.");

    Ref<CadPlane> plane = p_plane;
    if (plane.is_null()) {
        plane = default_xy_plane();
    }

    try {
        const gp_Ax2 axis(
            occt_utils::to_occt_point(plane->get_origin()),
            occt_utils::to_occt_dir(plane->get_normal()),
            occt_utils::to_occt_dir(plane->get_x_direction()));
        const gp_Elips ellipse(axis, p_major_radius, p_minor_radius);
        
        BRepBuilderAPI_MakeEdge edge_builder(ellipse);
        if (!edge_builder.IsDone()) {
            ERR_PRINT(vformat("EllipseWire.build_ellipse: edge construction did not complete"));
            return;
        }

        BRepBuilderAPI_MakeWire wire_builder;
        wire_builder.Add(edge_builder.Edge());
        wire_builder.Build();
        if (!wire_builder.IsDone()) {
            ERR_PRINT(vformat("EllipseWire.build_ellipse: wire construction did not complete"));
            return;
        }
        set_occt_shape(wire_builder.Shape());
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("EllipseWire.build_ellipse failed: %s", occt_utils::exception_to_string(e)));
    }
}
