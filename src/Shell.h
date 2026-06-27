#ifndef SHELL_H
#define SHELL_H

#include "TopoShape.h"

#include <TopoDS_Shell.hxx>

class Shell : public TopoShape {
    GDCLASS(Shell, TopoShape)

protected:
    static void _bind_methods();

public:
    Shell();

    static godot::Ref<Shell> from_occt(const TopoDS_Shell &p_shell);

    bool is_closed() const;
    int get_face_count() const;
};

#endif // SHELL_H
