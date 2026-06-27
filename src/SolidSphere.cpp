#include "SolidSphere.h"

#include "OCCTUtils.h"

#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/string.hpp>

#include <BRepPrimAPI_MakeSphere.hxx>

using namespace godot;

void SolidSphere::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build_sphere", "radius", "center"), &SolidSphere::build_sphere, DEFVAL(Vector3()));
}

SolidSphere::SolidSphere() = default;

void SolidSphere::build_sphere(double p_radius, const Vector3 &p_center) {
    ERR_FAIL_COND_MSG(p_radius <= 0.0, "SolidSphere.build_sphere requires a radius greater than zero.");

    try {
        BRepPrimAPI_MakeSphere sphere(occt_utils::to_occt_point(p_center), p_radius);
        sphere.Build();
        if (!sphere.IsDone()) {
            ERR_PRINT("SolidSphere.build_sphere: sphere construction did not complete");
            return;
        }
        set_occt_shape(sphere.Shape());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("SolidSphere.build_sphere failed: %s", occt_utils::exception_to_string(failure)));
    }
}
