#include "SolidBox.h"

#include "OCCTUtils.h"

#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/string.hpp>

#include <BRepPrimAPI_MakeBox.hxx>

using namespace godot;

void SolidBox::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build_box", "size", "origin"), &SolidBox::build_box, DEFVAL(Vector3()));
}

SolidBox::SolidBox() = default;

void SolidBox::build_box(const Vector3 &p_size, const Vector3 &p_origin) {
    ERR_FAIL_COND_MSG(p_size.x <= 0.0 || p_size.y <= 0.0 || p_size.z <= 0.0, "SolidBox.build_box requires all size components to be greater than zero.");

    try {
        BRepPrimAPI_MakeBox box(
            occt_utils::to_occt_point(p_origin),
            static_cast<double>(p_size.x),
            static_cast<double>(p_size.y),
            static_cast<double>(p_size.z)
        );
        box.Build();
        if (!box.IsDone()) {
            ERR_PRINT("SolidBox.build_box: box construction did not complete");
            return;
        }
        set_occt_shape(box.Shape());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("SolidBox.build_box failed: %s", occt_utils::exception_to_string(failure)));
    }
}
