#include "SolidWedge.h"

#include "OCCTUtils.h"

#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/string.hpp>

#include <BRepPrimAPI_MakeWedge.hxx>
#include <gp_Ax2.hxx>
#include <gp_Dir.hxx>

using namespace godot;

void SolidWedge::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build_wedge", "dx", "dy", "dz", "ltx", "origin"), &SolidWedge::build_wedge, DEFVAL(Vector3()));
}

SolidWedge::SolidWedge() = default;

void SolidWedge::build_wedge(double p_dx, double p_dy, double p_dz, double p_ltx, const Vector3 &p_origin) {
    ERR_FAIL_COND_MSG(p_dx <= 0.0 || p_dy <= 0.0 || p_dz <= 0.0, "SolidWedge.build_wedge requires positive dx, dy, and dz.");
    ERR_FAIL_COND_MSG(p_ltx < 0.0, "SolidWedge.build_wedge requires a non-negative ltx.");

    try {
        const gp_Ax2 axis(occt_utils::to_occt_point(p_origin), gp_Dir(0.0, 0.0, 1.0));
        BRepPrimAPI_MakeWedge wedge(axis, p_dx, p_dy, p_dz, p_ltx);
        wedge.Build();
        if (!wedge.IsDone()) {
            ERR_PRINT("SolidWedge.build_wedge: wedge construction did not complete");
            return;
        }
        set_occt_shape(wedge.Shape());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("SolidWedge.build_wedge failed: %s", occt_utils::exception_to_string(failure)));
    }
}
