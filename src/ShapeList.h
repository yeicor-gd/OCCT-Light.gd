#ifndef SHAPE_LIST_H
#define SHAPE_LIST_H

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/variant.hpp>

class TopoShape;
class Axis;
class CadPlane;

class ShapeList : public godot::RefCounted {
    GDCLASS(ShapeList, godot::RefCounted)

protected:
    static void _bind_methods();

    godot::Array shapes;

public:
    ShapeList();

    void append(const godot::Ref<TopoShape> &p_shape);
    int64_t size() const;
    bool is_empty() const;
    godot::Ref<TopoShape> get_item(int64_t p_index) const;
    godot::Array to_array() const;
    godot::Ref<TopoShape> first() const;
    godot::Ref<TopoShape> last() const;
    godot::Vector3 center() const;
    godot::Vector3 get_bounding_box_min() const;
    godot::Vector3 get_bounding_box_max() const;
    godot::Vector3 get_bounding_box_size() const;

    godot::Ref<ShapeList> vertices() const;
    godot::Ref<ShapeList> edges() const;
    godot::Ref<ShapeList> wires() const;
    godot::Ref<ShapeList> faces() const;
    godot::Ref<ShapeList> shells() const;
    godot::Ref<ShapeList> compounds() const;
    godot::Ref<ShapeList> solids() const;

    godot::Ref<ShapeList> filter_by_position(const godot::Ref<Axis> &p_axis, double p_minimum, double p_maximum, bool p_min_inclusive = true, bool p_max_inclusive = true) const;
    godot::Ref<ShapeList> filter_by_axis(const godot::Ref<Axis> &p_axis, double p_minimum, double p_maximum, bool p_min_inclusive = true, bool p_max_inclusive = true) const;
    godot::Ref<ShapeList> filter_by_plane(const godot::Ref<CadPlane> &p_plane, bool p_reverse = false, double p_tolerance = 1e-5) const;
    godot::Ref<ShapeList> filter_by_length(double p_minimum, double p_maximum, bool p_min_inclusive = true, bool p_max_inclusive = true) const;
    godot::Ref<ShapeList> filter_by_area(double p_minimum, double p_maximum, bool p_min_inclusive = true, bool p_max_inclusive = true) const;
    godot::Ref<ShapeList> filter_by_volume(double p_minimum, double p_maximum, bool p_min_inclusive = true, bool p_max_inclusive = true) const;
    godot::Ref<ShapeList> filter_by_distance_to_point(const godot::Vector3 &p_point, double p_minimum, double p_maximum, bool p_min_inclusive = true, bool p_max_inclusive = true) const;
    godot::Ref<ShapeList> filter_by_shape_type(const godot::String &p_shape_type_name, bool p_reverse = false) const;
    godot::Ref<ShapeList> filter_by_geom_type(const godot::String &p_geom_type_name, bool p_reverse = false) const;
    godot::Ref<ShapeList> filter_by(const godot::Callable &p_filter_by, bool p_reverse = false, double p_tolerance = 1e-5) const;
    godot::Array group_by_axis(const godot::Ref<Axis> &p_axis, bool p_reverse = false, int64_t p_tol_digits = 6) const;
    godot::Array group_by_length(bool p_reverse = false, int64_t p_tol_digits = 6) const;
    godot::Array group_by_area(bool p_reverse = false, int64_t p_tol_digits = 6) const;
    godot::Array group_by_volume(bool p_reverse = false, int64_t p_tol_digits = 6) const;
    godot::Array group_by_shape_type(bool p_reverse = false) const;
    godot::Array group_by_geom_type(bool p_reverse = false) const;
    godot::Array group_by(const godot::Callable &p_group_by, bool p_reverse = false, int64_t p_tol_digits = 6) const;
    godot::Ref<ShapeList> sort_by_axis(const godot::Ref<Axis> &p_axis, bool p_reverse = false) const;
    godot::Ref<ShapeList> sort_by_length(bool p_reverse = false) const;
    godot::Ref<ShapeList> sort_by_area(bool p_reverse = false) const;
    godot::Ref<ShapeList> sort_by_volume(bool p_reverse = false) const;
    godot::Ref<ShapeList> sort_by_shape_type(bool p_reverse = false) const;
    godot::Ref<ShapeList> sort_by_geom_type(bool p_reverse = false) const;
    godot::Ref<ShapeList> sort_by(const godot::Callable &p_sort_by, bool p_reverse = false) const;
    godot::Ref<ShapeList> sort_by_distance(const godot::Ref<TopoShape> &p_other, bool p_reverse = false) const;
    godot::Ref<ShapeList> sort_by_distance_to_point(const godot::Vector3 &p_point, bool p_reverse = false) const;
};

#endif // SHAPE_LIST_H
