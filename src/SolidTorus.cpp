#include "SolidTorus.h"

#include "OCCTUtils.h"

#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/string.hpp>

#include <BRepPrimAPI_MakeTorus.hxx>
#include <gp_Ax2.hxx>
#include <gp_Dir.hxx>

using namespace godot;

void SolidTorus::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build_torus", "major_radius", "minor_radius", "center"), &SolidTorus::build_torus, DEFVAL(Vector3()));
}

SolidTorus::SolidTorus() = default;

void SolidTorus::build_torus(double p_major_radius, double p_minor_radius, const Vector3 &p_center) {
    ERR_FAIL_COND_MSG(p_major_radius <= 0.0, "SolidTorus.build_torus requires a major radius greater than zero.");
    ERR_FAIL_COND_MSG(p_minor_radius <= 0.0, "SolidTorus.build_torus requires a minor radius greater than zero.");

    try {
        const gp_Ax2 axis(occt_utils::to_occt_point(p_center), gp_Dir(0.0, 0.0, 1.0));
        BRepPrimAPI_MakeTorus torus(axis, p_major_radius, p_minor_radius);
        torus.Build();
        if (!torus.IsDone()) {
            ERR_PRINT("SolidTorus.build_torus: torus construction did not complete");
            return;
        }
        set_occt_shape(torus.Shape());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("SolidTorus.build_torus failed: %s", occt_utils::exception_to_string(failure)));
    }
}
