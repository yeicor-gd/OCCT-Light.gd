#include "Solid.h"

#include "OCCTUtils.h"

#include <godot_cpp/core/error_macros.hpp>

#include <BRep_Tool.hxx>
#include <TopExp.hxx>
#include <NCollection_IndexedMap.hxx>
#include <TopTools_ShapeMapHasher.hxx>
#include <TopoDS.hxx>

using namespace godot;

void Solid::_bind_methods() {
    ClassDB::bind_method(D_METHOD("is_closed"), &Solid::is_closed);
    ClassDB::bind_method(D_METHOD("get_shell_count"), &Solid::get_shell_count);
}

Solid::Solid() = default;

Ref<Solid> Solid::from_occt(const TopoDS_Solid &p_solid) {
    Ref<Solid> result;
    result.instantiate();
    result->set_occt_shape(p_solid);
    return result;
}

bool Solid::is_closed() const {
    ERR_FAIL_COND_V_MSG(is_null(), false, "Solid.is_closed requires a non-null shape.");

    try {
        NCollection_IndexedMap<TopoDS_Shape, TopTools_ShapeMapHasher> indexed_shells;
        TopExp::MapShapes(get_occt_shape(), TopAbs_SHELL, indexed_shells);
        if (indexed_shells.IsEmpty()) {
            return false;
        }
        for (int index = 1; index <= indexed_shells.Extent(); ++index) {
            if (!BRep_Tool::IsClosed(indexed_shells(index))) {
                return false;
            }
        }
        return true;
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Solid.is_closed failed: %s", occt_utils::exception_to_string(failure)));
        return false;
    }
}

int Solid::get_shell_count() const {
    ERR_FAIL_COND_V_MSG(is_null(), 0, "Solid.get_shell_count requires a non-null shape.");

    try {
        NCollection_IndexedMap<TopoDS_Shape, TopTools_ShapeMapHasher> indexed_shells;
        TopExp::MapShapes(get_occt_shape(), TopAbs_SHELL, indexed_shells);
        return indexed_shells.Extent();
    } catch (const Standard_Failure &failure) {
        ERR_PRINT(vformat("Solid.get_shell_count failed: %s", occt_utils::exception_to_string(failure)));
        return 0;
    }
}
