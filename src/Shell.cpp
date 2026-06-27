#include "Shell.h"

#include "OCCTUtils.h"

#include <godot_cpp/core/error_macros.hpp>

#include <BRep_Tool.hxx>
#include <TopExp.hxx>
#include <NCollection_IndexedMap.hxx>
#include <TopTools_ShapeMapHasher.hxx>
#include <TopoDS.hxx>

using namespace godot;

void Shell::_bind_methods() {
    ClassDB::bind_method(D_METHOD("is_closed"), &Shell::is_closed);
    ClassDB::bind_method(D_METHOD("get_face_count"), &Shell::get_face_count);
}

Shell::Shell() = default;

Ref<Shell> Shell::from_occt(const TopoDS_Shell &p_shell) {
    Ref<Shell> result;
    result.instantiate();
    result->set_occt_shape(p_shell);
    return result;
}

bool Shell::is_closed() const {
    ERR_FAIL_COND_V_MSG(is_null(), false, "Shell.is_closed requires a non-null shape.");

    try {
        return BRep_Tool::IsClosed(get_occt_shape());
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Shell.is_closed failed: %s", occt_utils::exception_to_string(failure)));
        return false;
    }
}

int Shell::get_face_count() const {
    ERR_FAIL_COND_V_MSG(is_null(), 0, "Shell.get_face_count requires a non-null shape.");

    try {
        NCollection_IndexedMap<TopoDS_Shape, TopTools_ShapeMapHasher> indexed_faces;
        TopExp::MapShapes(get_occt_shape(), TopAbs_FACE, indexed_faces);
        return indexed_faces.Extent();
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Shell.get_face_count failed: %s", occt_utils::exception_to_string(failure)));
        return 0;
    }
}
