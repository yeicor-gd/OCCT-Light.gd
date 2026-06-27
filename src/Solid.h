#ifndef SOLID_H
#define SOLID_H

#include "TopoShape.h"

#include <TopoDS_Solid.hxx>

class Solid : public TopoShape {
    GDCLASS(Solid, TopoShape)

protected:
    static void _bind_methods();

public:
    Solid();

    static godot::Ref<Solid> from_occt(const TopoDS_Solid &p_solid);

    bool is_closed() const;
    int get_shell_count() const;
};

#endif // SOLID_H
