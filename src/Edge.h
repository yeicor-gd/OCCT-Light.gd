#ifndef EDGE_H
#define EDGE_H

#include "TopoShape.h"

#include <TopoDS_Edge.hxx>

class Edge : public TopoShape {
    GDCLASS(Edge, TopoShape)

protected:
    static void _bind_methods();

public:
    Edge();

    static godot::Ref<Edge> from_occt(const TopoDS_Edge &p_edge);

    void build_line(const godot::Vector3 &p_start, const godot::Vector3 &p_end);
    godot::Vector3 get_start_position() const;
    godot::Vector3 get_end_position() const;
    double get_length() const;
    godot::PackedVector3Array get_polyline(double p_deflection = 0.1) const;
};

#endif // EDGE_H
