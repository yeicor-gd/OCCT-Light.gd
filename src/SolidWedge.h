#ifndef SOLID_WEDGE_H
#define SOLID_WEDGE_H

#include "Solid.h"

class SolidWedge : public Solid {
    GDCLASS(SolidWedge, Solid)

protected:
    static void _bind_methods();

public:
    SolidWedge();

    void build_wedge(double p_dx, double p_dy, double p_dz, double p_ltx, const godot::Vector3 &p_origin = godot::Vector3());
};

#endif // SOLID_WEDGE_H
