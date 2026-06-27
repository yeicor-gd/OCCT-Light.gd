#ifndef SOLID_SPHERE_H
#define SOLID_SPHERE_H

#include "Solid.h"

class SolidSphere : public Solid {
    GDCLASS(SolidSphere, Solid)

protected:
    static void _bind_methods();

public:
    SolidSphere();

    void build_sphere(double p_radius, const godot::Vector3 &p_center = godot::Vector3());
};

#endif // SOLID_SPHERE_H
