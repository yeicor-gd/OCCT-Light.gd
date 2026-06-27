#ifndef LOCATION_H
#define LOCATION_H

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <gp_Trsf.hxx>

class Axis;

class Location : public godot::RefCounted {
    GDCLASS(Location, godot::RefCounted)

protected:
    static void _bind_methods();

    gp_Trsf occt_transform;

public:
    Location();

    void set_identity();
    void set_translation(const godot::Vector3 &p_offset);
    void set_rotation(const godot::Ref<Axis> &p_axis, double p_angle_radians);
    void set_scale(const godot::Vector3 &p_center, double p_factor);
    godot::Ref<Location> multiplied(const godot::Ref<Location> &p_other) const;
    godot::Ref<Location> inverted() const;
    godot::Vector3 transform_point(const godot::Vector3 &p_point) const;
    godot::Vector3 transform_vector(const godot::Vector3 &p_vector) const;

    void set_occt_transform(const gp_Trsf &p_transform);
    const gp_Trsf &get_occt_transform() const;
};

#endif // LOCATION_H
