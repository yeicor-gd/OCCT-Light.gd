#ifndef GEOMETRY_VECTOR_H
#define GEOMETRY_VECTOR_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <gp_Vec.hxx>

class GeometryVector : public godot::RefCounted {
    GDCLASS(GeometryVector, godot::RefCounted)

protected:
    static void _bind_methods();

private:
    gp_Vec occt_vector;

public:
    GeometryVector();

    static godot::Ref<GeometryVector> from_occt(const gp_Vec &p_vec);

    void set_xyz(double p_x, double p_y, double p_z);
    void set_vector3(const godot::Vector3 &p_vec);

    godot::Vector3 get_vector3() const;
    double length() const;
    double dot(const godot::Ref<GeometryVector> &p_other) const;

    godot::Ref<GeometryVector> add(const godot::Ref<GeometryVector> &p_other) const;
    godot::Ref<GeometryVector> subtract(const godot::Ref<GeometryVector> &p_other) const;
    godot::Ref<GeometryVector> cross(const godot::Ref<GeometryVector> &p_other) const;
    godot::Ref<GeometryVector> scaled(double p_factor) const;

    const gp_Vec &get_occt_vector() const;
};

#endif // GEOMETRY_VECTOR_H
