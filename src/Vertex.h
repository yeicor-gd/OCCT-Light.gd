#ifndef VERTEX_H
#define VERTEX_H

#include "TopoShape.h"

#include <TopoDS_Vertex.hxx>

class Vertex : public TopoShape {
    GDCLASS(Vertex, TopoShape)

protected:
    static void _bind_methods();

public:
    Vertex();

    static godot::Ref<Vertex> from_occt(const TopoDS_Vertex &p_vertex);

    void build_vertex(const godot::Vector3 &p_position);
    godot::Vector3 get_position() const;
};

#endif // VERTEX_H
