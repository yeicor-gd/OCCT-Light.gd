#ifndef COMPOUND_H
#define COMPOUND_H

#include "TopoShape.h"

#include <TopoDS_Compound.hxx>

class Compound : public TopoShape {
    GDCLASS(Compound, TopoShape)

protected:
    static void _bind_methods();

public:
    Compound();

    static godot::Ref<Compound> from_occt(const TopoDS_Compound &p_compound);

    void build_compound(const godot::Array &p_shapes);
    int get_child_count() const;
};

#endif // COMPOUND_H
