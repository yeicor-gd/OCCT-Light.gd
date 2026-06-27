#include "ShapeList.h"

#include "Axis.h"
#include "OCCTUtils.h"
#include "Plane.h"
#include "TopoShape.h"

#include <godot_cpp/core/error_macros.hpp>

#include <algorithm>
#include <cmath>
#include <map>
#include <vector>

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <GeomAbs_CurveType.hxx>
#include <GeomAbs_SurfaceType.hxx>
#include <gp_Dir.hxx>

using namespace godot;

namespace {

Vector3 shape_center(const Ref<TopoShape> &p_shape) {
    return (p_shape->get_bounding_box_min() + p_shape->get_bounding_box_max()) * 0.5;
}

Ref<ShapeList> shape_list_from_flattened(const Array &p_shapes) {
    Ref<ShapeList> list;
    list.instantiate();
    for (int64_t index = 0; index < p_shapes.size(); ++index) {
        const Ref<TopoShape> shape = p_shapes[index];
        if (shape.is_null() || shape->is_null()) {
            continue;
        }
        list->append(shape);
    }
    return list;
}

double shape_metric_value(const Ref<TopoShape> &p_shape, const StringName &p_method_name) {
    ERR_FAIL_COND_V_MSG(p_shape.is_null() || p_shape->is_null(), 0.0, "ShapeList metric evaluation requires a non-null shape.");
    ERR_FAIL_COND_V_MSG(!p_shape->has_method(p_method_name), 0.0, "ShapeList metric evaluation requires a supported metric method.");

    const Variant value = p_shape->call(p_method_name);
    ERR_FAIL_COND_V_MSG(value.get_type() != Variant::FLOAT && value.get_type() != Variant::INT, 0.0, "ShapeList metric evaluation returned a non-numeric value.");
    return static_cast<double>(value);
}

bool shape_matches_plane(const Ref<TopoShape> &p_shape, const Ref<CadPlane> &p_plane, double p_tolerance) {
    ERR_FAIL_COND_V_MSG(p_plane.is_null(), false, "ShapeList.filter_by_plane requires a non-null plane.");
    ERR_FAIL_COND_V_MSG(p_shape.is_null() || p_shape->is_null(), false, "ShapeList.filter_by_plane requires a non-null shape.");

    const Vector3 plane_normal = p_plane->get_normal().normalized();
    if (p_shape->has_method("get_normal")) {
        const Vector3 normal = p_shape->call("get_normal");
        if (normal.length() == 0.0) {
            return false;
        }
        return std::abs(normal.normalized().dot(plane_normal)) >= 1.0 - p_tolerance;
    }

    if (p_shape->has_method("get_start_position") && p_shape->has_method("get_end_position")) {
        const Vector3 start = p_shape->call("get_start_position");
        const Vector3 end = p_shape->call("get_end_position");
        const Vector3 direction = end - start;
        if (direction.length() == 0.0) {
            return false;
        }
        return std::abs(direction.normalized().dot(plane_normal)) <= p_tolerance;
    }

    if (p_shape->has_method("get_edges")) {
        const Array edges = p_shape->call("get_edges");
        if (edges.is_empty()) {
            return false;
        }
        for (int64_t index = 0; index < edges.size(); ++index) {
            const Ref<TopoShape> edge = edges[index];
            if (!shape_matches_plane(edge, p_plane, p_tolerance)) {
                return false;
            }
        }
        return true;
    }

    return false;
}

Ref<ShapeList> sort_shapes_by_metric(const Array &p_shapes, const StringName &p_method_name, bool p_reverse) {
    std::vector<std::pair<double, Ref<TopoShape>>> ordered;
    ordered.reserve(p_shapes.size());
    for (int64_t index = 0; index < p_shapes.size(); ++index) {
        const Ref<TopoShape> shape = p_shapes[index];
        if (shape.is_null() || shape->is_null() || !shape->has_method(p_method_name)) {
            continue;
        }
        ordered.emplace_back(shape_metric_value(shape, p_method_name), shape);
    }

    std::sort(ordered.begin(), ordered.end(), [p_reverse](const auto &p_a, const auto &p_b) {
        if (p_reverse) {
            return p_a.first > p_b.first;
        }
        return p_a.first < p_b.first;
    });

    Array sorted;
    for (const auto &entry : ordered) {
        sorted.push_back(entry.second);
    }
    return shape_list_from_flattened(sorted);
}

Ref<ShapeList> filter_shapes_by_metric(const Array &p_shapes, const StringName &p_method_name, double p_minimum, double p_maximum, bool p_min_inclusive, bool p_max_inclusive) {
    ERR_FAIL_COND_V_MSG(p_minimum > p_maximum, Ref<ShapeList>(), "ShapeList metric filtering requires minimum <= maximum.");

    Ref<ShapeList> result;
    result.instantiate();
    for (int64_t index = 0; index < p_shapes.size(); ++index) {
        const Ref<TopoShape> shape = p_shapes[index];
        if (shape.is_null() || shape->is_null() || !shape->has_method(p_method_name)) {
            continue;
        }

        const double value = shape_metric_value(shape, p_method_name);
        const bool above_min = p_min_inclusive ? value >= p_minimum : value > p_minimum;
        const bool below_max = p_max_inclusive ? value <= p_maximum : value < p_maximum;
        if (above_min && below_max) {
            result->append(shape);
        }
    }
    return result;
}

bool callable_predicate_matches(const Ref<TopoShape> &p_shape, const Callable &p_callable) {
    ERR_FAIL_COND_V_MSG(p_shape.is_null() || p_shape->is_null(), false, "ShapeList.filter_by requires a non-null shape.");
    ERR_FAIL_COND_V_MSG(!p_callable.is_valid(), false, "ShapeList.filter_by requires a valid callable.");

    const Variant value = p_callable.call(p_shape);
    ERR_FAIL_COND_V_MSG(value.get_type() != Variant::BOOL, false, "ShapeList.filter_by callable must return a bool.");
    return value;
}

bool shape_type_matches(const Ref<TopoShape> &p_shape, const String &p_shape_type_name) {
    ERR_FAIL_COND_V_MSG(p_shape.is_null() || p_shape->is_null(), false, "ShapeList.filter_by_shape_type requires a non-null shape.");

    const String type_name = p_shape->get_shape_type_name();
    return type_name == p_shape_type_name;
}

bool geom_type_matches(const Ref<TopoShape> &p_shape, const String &p_geom_type_name) {
    ERR_FAIL_COND_V_MSG(p_shape.is_null() || p_shape->is_null(), false, "ShapeList.filter_by_geom_type requires a non-null shape.");

    const String type_name = p_shape->get_geom_type_name();
    return type_name == p_geom_type_name;
}

double callable_metric_value(const Ref<TopoShape> &p_shape, const Callable &p_callable) {
    ERR_FAIL_COND_V_MSG(p_shape.is_null() || p_shape->is_null(), 0.0, "ShapeList sort/group callable requires a non-null shape.");
    ERR_FAIL_COND_V_MSG(!p_callable.is_valid(), 0.0, "ShapeList sort/group callable requires a valid callable.");

    const Variant value = p_callable.call(p_shape);
    ERR_FAIL_COND_V_MSG(value.get_type() != Variant::FLOAT && value.get_type() != Variant::INT, 0.0, "ShapeList sort/group callable must return a numeric value.");
    return static_cast<double>(value);
}

double shape_type_rank(const Ref<TopoShape> &p_shape) {
    ERR_FAIL_COND_V_MSG(p_shape.is_null() || p_shape->is_null(), 0.0, "ShapeList shape-type sorting requires a non-null shape.");

    const String type_name = p_shape->get_shape_type_name();
    if (type_name == "SHAPE") return 0.0;
    if (type_name == "COMPOUND") return 1.0;
    if (type_name == "COMPSOLID") return 2.0;
    if (type_name == "SOLID") return 3.0;
    if (type_name == "SHELL") return 4.0;
    if (type_name == "FACE") return 5.0;
    if (type_name == "WIRE") return 6.0;
    if (type_name == "EDGE") return 7.0;
    if (type_name == "VERTEX") return 8.0;
    return 9.0;
}

double round_to_digits(double p_value, int64_t p_tol_digits) {
    const double factor = std::pow(10.0, static_cast<double>(std::max<int64_t>(0, p_tol_digits)));
    return std::round(p_value * factor) / factor;
}

Array grouped_shape_arrays_from_map(const std::map<double, Array> &p_groups, bool p_reverse) {
    Array grouped;
    if (p_reverse) {
        for (auto it = p_groups.rbegin(); it != p_groups.rend(); ++it) {
            grouped.push_back(shape_list_from_flattened(it->second));
        }
    } else {
        for (const auto &entry : p_groups) {
            grouped.push_back(shape_list_from_flattened(entry.second));
        }
    }
    return grouped;
}

template <typename TKeyFn>
Array group_shapes_by_key(const Array &p_shapes, TKeyFn &&p_key_fn, int64_t p_tol_digits, bool p_reverse) {
    std::map<double, Array> groups;
    for (int64_t index = 0; index < p_shapes.size(); ++index) {
        const Ref<TopoShape> shape = p_shapes[index];
        if (shape.is_null() || shape->is_null()) {
            continue;
        }
        const double key = round_to_digits(p_key_fn(shape), p_tol_digits);
        groups[key].push_back(shape);
    }
    return grouped_shape_arrays_from_map(groups, p_reverse);
}

Array group_shapes_by_metric(const Array &p_shapes, const StringName &p_method_name, int64_t p_tol_digits, bool p_reverse) {
    std::map<double, Array> groups;
    for (int64_t index = 0; index < p_shapes.size(); ++index) {
        const Ref<TopoShape> shape = p_shapes[index];
        if (shape.is_null() || shape->is_null() || !shape->has_method(p_method_name)) {
            continue;
        }
        const double key = round_to_digits(shape_metric_value(shape, p_method_name), p_tol_digits);
        groups[key].push_back(shape);
    }
    return grouped_shape_arrays_from_map(groups, p_reverse);
}

Array group_shapes_by_callable(const Array &p_shapes, const Callable &p_callable, int64_t p_tol_digits, bool p_reverse) {
    ERR_FAIL_COND_V_MSG(!p_callable.is_valid(), Array(), "ShapeList.group_by requires a valid callable.");

    std::map<double, Array> groups;
    for (int64_t index = 0; index < p_shapes.size(); ++index) {
        const Ref<TopoShape> shape = p_shapes[index];
        if (shape.is_null() || shape->is_null()) {
            continue;
        }
        const double key = round_to_digits(callable_metric_value(shape, p_callable), p_tol_digits);
        groups[key].push_back(shape);
    }
    return grouped_shape_arrays_from_map(groups, p_reverse);
}

Ref<ShapeList> sort_shapes_by_callable(const Array &p_shapes, const Callable &p_callable, bool p_reverse) {
    ERR_FAIL_COND_V_MSG(!p_callable.is_valid(), Ref<ShapeList>(), "ShapeList.sort_by requires a valid callable.");

    std::vector<std::pair<double, Ref<TopoShape>>> ordered;
    ordered.reserve(p_shapes.size());
    for (int64_t index = 0; index < p_shapes.size(); ++index) {
        const Ref<TopoShape> shape = p_shapes[index];
        if (shape.is_null() || shape->is_null()) {
            continue;
        }
        ordered.emplace_back(callable_metric_value(shape, p_callable), shape);
    }

    std::sort(ordered.begin(), ordered.end(), [p_reverse](const auto &p_a, const auto &p_b) {
        if (p_reverse) {
            return p_a.first > p_b.first;
        }
        return p_a.first < p_b.first;
    });

    Array sorted;
    for (const auto &entry : ordered) {
        sorted.push_back(entry.second);
    }
    return shape_list_from_flattened(sorted);
}

Ref<ShapeList> sort_shapes_by_shape_type(const Array &p_shapes, bool p_reverse) {
    std::vector<std::pair<double, Ref<TopoShape>>> ordered;
    ordered.reserve(p_shapes.size());
    for (int64_t index = 0; index < p_shapes.size(); ++index) {
        const Ref<TopoShape> shape = p_shapes[index];
        if (shape.is_null() || shape->is_null()) {
            continue;
        }
        ordered.emplace_back(shape_type_rank(shape), shape);
    }

    std::sort(ordered.begin(), ordered.end(), [p_reverse](const auto &p_a, const auto &p_b) {
        if (p_reverse) {
            return p_a.first > p_b.first;
        }
        return p_a.first < p_b.first;
    });

    Array sorted;
    for (const auto &entry : ordered) {
        sorted.push_back(entry.second);
    }
    return shape_list_from_flattened(sorted);
}

Array group_shapes_by_shape_type(const Array &p_shapes, bool p_reverse) {
    std::map<String, Array> groups;
    for (int64_t index = 0; index < p_shapes.size(); ++index) {
        const Ref<TopoShape> shape = p_shapes[index];
        if (shape.is_null() || shape->is_null()) {
            continue;
        }
        groups[shape->get_shape_type_name()].push_back(shape);
    }

    Array grouped;
    if (p_reverse) {
        for (auto it = groups.rbegin(); it != groups.rend(); ++it) {
            grouped.push_back(shape_list_from_flattened(it->second));
        }
    } else {
        for (const auto &entry : groups) {
            grouped.push_back(shape_list_from_flattened(entry.second));
        }
    }
    return grouped;
}

Ref<ShapeList> sort_shapes_by_geom_type(const Array &p_shapes, bool p_reverse) {
    std::vector<std::pair<String, Ref<TopoShape>>> ordered;
    ordered.reserve(p_shapes.size());
    for (int64_t index = 0; index < p_shapes.size(); ++index) {
        const Ref<TopoShape> shape = p_shapes[index];
        if (shape.is_null() || shape->is_null()) {
            continue;
        }
        ordered.emplace_back(shape->get_geom_type_name(), shape);
    }

    std::sort(ordered.begin(), ordered.end(), [p_reverse](const auto &p_a, const auto &p_b) {
        if (p_reverse) {
            return p_a.first > p_b.first;
        }
        return p_a.first < p_b.first;
    });

    Array sorted;
    for (const auto &entry : ordered) {
        sorted.push_back(entry.second);
    }
    return shape_list_from_flattened(sorted);
}

Array group_shapes_by_geom_type(const Array &p_shapes, bool p_reverse) {
    std::map<String, Array> groups;
    for (int64_t index = 0; index < p_shapes.size(); ++index) {
        const Ref<TopoShape> shape = p_shapes[index];
        if (shape.is_null() || shape->is_null()) {
            continue;
        }
        groups[shape->get_geom_type_name()].push_back(shape);
    }

    Array grouped;
    if (p_reverse) {
        for (auto it = groups.rbegin(); it != groups.rend(); ++it) {
            grouped.push_back(shape_list_from_flattened(it->second));
        }
    } else {
        for (const auto &entry : groups) {
            grouped.push_back(shape_list_from_flattened(entry.second));
        }
    }
    return grouped;
}

} // namespace

void ShapeList::_bind_methods() {
    ClassDB::bind_method(D_METHOD("append", "shape"), &ShapeList::append);
    ClassDB::bind_method(D_METHOD("size"), &ShapeList::size);
    ClassDB::bind_method(D_METHOD("is_empty"), &ShapeList::is_empty);
    ClassDB::bind_method(D_METHOD("get_item", "index"), &ShapeList::get_item);
    ClassDB::bind_method(D_METHOD("to_array"), &ShapeList::to_array);
    ClassDB::bind_method(D_METHOD("first"), &ShapeList::first);
    ClassDB::bind_method(D_METHOD("last"), &ShapeList::last);
    ClassDB::bind_method(D_METHOD("center"), &ShapeList::center);
    ClassDB::bind_method(D_METHOD("get_bounding_box_min"), &ShapeList::get_bounding_box_min);
    ClassDB::bind_method(D_METHOD("get_bounding_box_max"), &ShapeList::get_bounding_box_max);
    ClassDB::bind_method(D_METHOD("get_bounding_box_size"), &ShapeList::get_bounding_box_size);
    ClassDB::bind_method(D_METHOD("vertices"), &ShapeList::vertices);
    ClassDB::bind_method(D_METHOD("edges"), &ShapeList::edges);
    ClassDB::bind_method(D_METHOD("wires"), &ShapeList::wires);
    ClassDB::bind_method(D_METHOD("faces"), &ShapeList::faces);
    ClassDB::bind_method(D_METHOD("shells"), &ShapeList::shells);
    ClassDB::bind_method(D_METHOD("compounds"), &ShapeList::compounds);
    ClassDB::bind_method(D_METHOD("solids"), &ShapeList::solids);
    ClassDB::bind_method(D_METHOD("filter_by_position", "axis", "minimum", "maximum", "min_inclusive", "max_inclusive"), &ShapeList::filter_by_position, DEFVAL(true), DEFVAL(true));
    ClassDB::bind_method(D_METHOD("filter_by_axis", "axis", "minimum", "maximum", "min_inclusive", "max_inclusive"), &ShapeList::filter_by_axis, DEFVAL(true), DEFVAL(true));
    ClassDB::bind_method(D_METHOD("filter_by_plane", "plane", "reverse", "tolerance"), &ShapeList::filter_by_plane, DEFVAL(false), DEFVAL(1e-5));
    ClassDB::bind_method(D_METHOD("filter_by_length", "minimum", "maximum", "min_inclusive", "max_inclusive"), &ShapeList::filter_by_length, DEFVAL(true), DEFVAL(true));
    ClassDB::bind_method(D_METHOD("filter_by_area", "minimum", "maximum", "min_inclusive", "max_inclusive"), &ShapeList::filter_by_area, DEFVAL(true), DEFVAL(true));
    ClassDB::bind_method(D_METHOD("filter_by_volume", "minimum", "maximum", "min_inclusive", "max_inclusive"), &ShapeList::filter_by_volume, DEFVAL(true), DEFVAL(true));
    ClassDB::bind_method(D_METHOD("filter_by_distance_to_point", "point", "minimum", "maximum", "min_inclusive", "max_inclusive"), &ShapeList::filter_by_distance_to_point, DEFVAL(true), DEFVAL(true));
    ClassDB::bind_method(D_METHOD("filter_by_shape_type", "shape_type_name", "reverse"), &ShapeList::filter_by_shape_type, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("filter_by_geom_type", "geom_type_name", "reverse"), &ShapeList::filter_by_geom_type, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("filter_by", "predicate", "reverse", "tolerance"), &ShapeList::filter_by, DEFVAL(false), DEFVAL(1e-5));
    ClassDB::bind_method(D_METHOD("group_by_axis", "axis", "reverse", "tol_digits"), &ShapeList::group_by_axis, DEFVAL(false), DEFVAL(6));
    ClassDB::bind_method(D_METHOD("group_by_length", "reverse", "tol_digits"), &ShapeList::group_by_length, DEFVAL(false), DEFVAL(6));
    ClassDB::bind_method(D_METHOD("group_by_area", "reverse", "tol_digits"), &ShapeList::group_by_area, DEFVAL(false), DEFVAL(6));
    ClassDB::bind_method(D_METHOD("group_by_volume", "reverse", "tol_digits"), &ShapeList::group_by_volume, DEFVAL(false), DEFVAL(6));
    ClassDB::bind_method(D_METHOD("group_by_shape_type", "reverse"), &ShapeList::group_by_shape_type, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("group_by_geom_type", "reverse"), &ShapeList::group_by_geom_type, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("group_by", "key_fn", "reverse", "tol_digits"), &ShapeList::group_by, DEFVAL(false), DEFVAL(6));
    ClassDB::bind_method(D_METHOD("sort_by_axis", "axis", "reverse"), &ShapeList::sort_by_axis, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("sort_by_length", "reverse"), &ShapeList::sort_by_length, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("sort_by_area", "reverse"), &ShapeList::sort_by_area, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("sort_by_volume", "reverse"), &ShapeList::sort_by_volume, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("sort_by_shape_type", "reverse"), &ShapeList::sort_by_shape_type, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("sort_by_geom_type", "reverse"), &ShapeList::sort_by_geom_type, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("sort_by", "key_fn", "reverse"), &ShapeList::sort_by, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("sort_by_distance", "other", "reverse"), &ShapeList::sort_by_distance, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("sort_by_distance_to_point", "point", "reverse"), &ShapeList::sort_by_distance_to_point, DEFVAL(false));
}

ShapeList::ShapeList() = default;

void ShapeList::append(const Ref<TopoShape> &p_shape) {
    ERR_FAIL_COND_MSG(p_shape.is_null() || p_shape->is_null(), "ShapeList.append requires a non-null TopoShape.");
    shapes.push_back(p_shape);
}

int64_t ShapeList::size() const {
    return shapes.size();
}

bool ShapeList::is_empty() const {
    return shapes.is_empty();
}

Ref<TopoShape> ShapeList::get_item(int64_t p_index) const {
    ERR_FAIL_INDEX_V_MSG(p_index, shapes.size(), Ref<TopoShape>(), "ShapeList.get_item index out of range.");
    return shapes[p_index];
}

Array ShapeList::to_array() const {
    return shapes;
}

Ref<TopoShape> ShapeList::first() const {
    ERR_FAIL_COND_V_MSG(shapes.is_empty(), Ref<TopoShape>(), "ShapeList.first requires at least one shape.");
    return shapes[0];
}

Ref<TopoShape> ShapeList::last() const {
    ERR_FAIL_COND_V_MSG(shapes.is_empty(), Ref<TopoShape>(), "ShapeList.last requires at least one shape.");
    return shapes[shapes.size() - 1];
}

Vector3 ShapeList::center() const {
    try {
        ERR_FAIL_COND_V_MSG(shapes.is_empty(), Vector3(), "ShapeList.center requires at least one shape.");

        Vector3 total_center;
        int64_t count = 0;
        for (int64_t index = 0; index < shapes.size(); ++index) {
            const Ref<TopoShape> shape = shapes[index];
            if (shape.is_null() || shape->is_null()) {
                continue;
            }
            total_center += shape_center(shape);
            ++count;
        }

        ERR_FAIL_COND_V_MSG(count == 0, Vector3(), "ShapeList.center requires at least one non-null shape.");
        return total_center / static_cast<real_t>(count);
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("ShapeList.center failed: %s", occt_utils::exception_to_string(e)));
        return Vector3();
    }
}

Vector3 ShapeList::get_bounding_box_min() const {
    try {
        ERR_FAIL_COND_V_MSG(shapes.is_empty(), Vector3(), "ShapeList.get_bounding_box_min requires at least one shape.");

        bool initialized = false;
        Vector3 minimum;
        for (int64_t index = 0; index < shapes.size(); ++index) {
            const Ref<TopoShape> shape = shapes[index];
            if (shape.is_null() || shape->is_null()) {
                continue;
            }
            const Vector3 shape_min = shape->get_bounding_box_min();
            if (!initialized) {
                minimum = shape_min;
                initialized = true;
                continue;
            }
            minimum.x = std::min(minimum.x, shape_min.x);
            minimum.y = std::min(minimum.y, shape_min.y);
            minimum.z = std::min(minimum.z, shape_min.z);
        }

        ERR_FAIL_COND_V_MSG(!initialized, Vector3(), "ShapeList.get_bounding_box_min requires at least one non-null shape.");
        return minimum;
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("ShapeList.get_bounding_box_min failed: %s", occt_utils::exception_to_string(e)));
        return Vector3();
    }
}

Vector3 ShapeList::get_bounding_box_max() const {
    try {
        ERR_FAIL_COND_V_MSG(shapes.is_empty(), Vector3(), "ShapeList.get_bounding_box_max requires at least one shape.");

        bool initialized = false;
        Vector3 maximum;
        for (int64_t index = 0; index < shapes.size(); ++index) {
            const Ref<TopoShape> shape = shapes[index];
            if (shape.is_null() || shape->is_null()) {
                continue;
            }
            const Vector3 shape_max = shape->get_bounding_box_max();
            if (!initialized) {
                maximum = shape_max;
                initialized = true;
                continue;
            }
            maximum.x = std::max(maximum.x, shape_max.x);
            maximum.y = std::max(maximum.y, shape_max.y);
            maximum.z = std::max(maximum.z, shape_max.z);
        }

        ERR_FAIL_COND_V_MSG(!initialized, Vector3(), "ShapeList.get_bounding_box_max requires at least one non-null shape.");
        return maximum;
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("ShapeList.get_bounding_box_max failed: %s", occt_utils::exception_to_string(e)));
        return Vector3();
    }
}

Vector3 ShapeList::get_bounding_box_size() const {
    try {
        return get_bounding_box_max() - get_bounding_box_min();
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("ShapeList.get_bounding_box_size failed: %s", occt_utils::exception_to_string(e)));
        return Vector3();
    }
}

Ref<ShapeList> ShapeList::vertices() const {
    try {
        Ref<ShapeList> result;
        result.instantiate();
        for (int64_t index = 0; index < shapes.size(); ++index) {
            const Ref<TopoShape> shape = shapes[index];
            if (shape.is_null() || shape->is_null()) {
                continue;
            }
            const Array nested = shape->get_vertices();
            for (int64_t nested_index = 0; nested_index < nested.size(); ++nested_index) {
                result->append(nested[nested_index]);
            }
        }
        return result;
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("ShapeList.vertices failed: %s", occt_utils::exception_to_string(e)));
        Ref<ShapeList> empty;
        empty.instantiate();
        return empty;
    }
}

Ref<ShapeList> ShapeList::edges() const {
    try {
        Ref<ShapeList> result;
        result.instantiate();
        for (int64_t index = 0; index < shapes.size(); ++index) {
            const Ref<TopoShape> shape = shapes[index];
            if (shape.is_null() || shape->is_null()) {
                continue;
            }
            const Array nested = shape->get_edges();
            for (int64_t nested_index = 0; nested_index < nested.size(); ++nested_index) {
                result->append(nested[nested_index]);
            }
        }
        return result;
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("ShapeList.edges failed: %s", occt_utils::exception_to_string(e)));
        Ref<ShapeList> empty;
        empty.instantiate();
        return empty;
    }
}

Ref<ShapeList> ShapeList::wires() const {
    try {
        Ref<ShapeList> result;
        result.instantiate();
        for (int64_t index = 0; index < shapes.size(); ++index) {
            const Ref<TopoShape> shape = shapes[index];
            if (shape.is_null() || shape->is_null()) {
                continue;
            }
            const Array nested = shape->get_wires();
            for (int64_t nested_index = 0; nested_index < nested.size(); ++nested_index) {
                result->append(nested[nested_index]);
            }
        }
        return result;
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("ShapeList.wires failed: %s", occt_utils::exception_to_string(e)));
        Ref<ShapeList> empty;
        empty.instantiate();
        return empty;
    }
}

Ref<ShapeList> ShapeList::faces() const {
    try {
        Ref<ShapeList> result;
        result.instantiate();
        for (int64_t index = 0; index < shapes.size(); ++index) {
            const Ref<TopoShape> shape = shapes[index];
            if (shape.is_null() || shape->is_null()) {
                continue;
            }
            const Array nested = shape->get_faces();
            for (int64_t nested_index = 0; nested_index < nested.size(); ++nested_index) {
                result->append(nested[nested_index]);
            }
        }
        return result;
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("ShapeList.faces failed: %s", occt_utils::exception_to_string(e)));
        Ref<ShapeList> empty;
        empty.instantiate();
        return empty;
    }
}

Ref<ShapeList> ShapeList::shells() const {
    try {
        Ref<ShapeList> result;
        result.instantiate();
        for (int64_t index = 0; index < shapes.size(); ++index) {
            const Ref<TopoShape> shape = shapes[index];
            if (shape.is_null() || shape->is_null()) {
                continue;
            }
            const Array nested = shape->get_shells();
            for (int64_t nested_index = 0; nested_index < nested.size(); ++nested_index) {
                result->append(nested[nested_index]);
            }
        }
        return result;
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("ShapeList.shells failed: %s", occt_utils::exception_to_string(e)));
        Ref<ShapeList> empty;
        empty.instantiate();
        return empty;
    }
}

Ref<ShapeList> ShapeList::compounds() const {
    try {
        Ref<ShapeList> result;
        result.instantiate();
        for (int64_t index = 0; index < shapes.size(); ++index) {
            const Ref<TopoShape> shape = shapes[index];
            if (shape.is_null() || shape->is_null()) {
                continue;
            }
            const Array nested = shape->get_compounds();
            for (int64_t nested_index = 0; nested_index < nested.size(); ++nested_index) {
                result->append(nested[nested_index]);
            }
        }
        return result;
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("ShapeList.compounds failed: %s", occt_utils::exception_to_string(e)));
        Ref<ShapeList> empty;
        empty.instantiate();
        return empty;
    }
}

Ref<ShapeList> ShapeList::solids() const {
    try {
        Ref<ShapeList> result;
        result.instantiate();
        for (int64_t index = 0; index < shapes.size(); ++index) {
            const Ref<TopoShape> shape = shapes[index];
            if (shape.is_null() || shape->is_null()) {
                continue;
            }
            const Array nested = shape->get_solids();
            for (int64_t nested_index = 0; nested_index < nested.size(); ++nested_index) {
                result->append(nested[nested_index]);
            }
        }
        return result;
    } catch (const Standard_Failure &e) {
        ERR_PRINT(vformat("ShapeList.solids failed: %s", occt_utils::exception_to_string(e)));
        Ref<ShapeList> empty;
        empty.instantiate();
        return empty;
    }
}

Ref<ShapeList> ShapeList::filter_by_position(const Ref<Axis> &p_axis, double p_minimum, double p_maximum, bool p_min_inclusive, bool p_max_inclusive) const {
    ERR_FAIL_COND_V_MSG(p_axis.is_null(), Ref<ShapeList>(), "ShapeList.filter_by_position requires a non-null axis.");
    ERR_FAIL_COND_V_MSG(p_minimum > p_maximum, Ref<ShapeList>(), "ShapeList.filter_by_position requires minimum <= maximum.");

    const gp_Dir direction = p_axis->get_occt_axis().Direction();
    const Vector3 origin = p_axis->get_origin();

    std::vector<std::pair<double, Ref<TopoShape>>> filtered;
    for (int64_t index = 0; index < shapes.size(); ++index) {
        const Ref<TopoShape> shape = shapes[index];
        if (shape.is_null() || shape->is_null()) {
            continue;
        }
        const Vector3 center = shape_center(shape);
        const Vector3 relative = center - origin;
        const double position = static_cast<double>(relative.x) * direction.X() + static_cast<double>(relative.y) * direction.Y() + static_cast<double>(relative.z) * direction.Z();

        const bool above_min = p_min_inclusive ? position >= p_minimum : position > p_minimum;
        const bool below_max = p_max_inclusive ? position <= p_maximum : position < p_maximum;
        if (above_min && below_max) {
            filtered.emplace_back(position, shape);
        }
    }

    std::sort(filtered.begin(), filtered.end(), [](const auto &p_a, const auto &p_b) {
        return p_a.first < p_b.first;
    });

    Array ordered;
    for (const auto &entry : filtered) {
        ordered.push_back(entry.second);
    }
    return shape_list_from_flattened(ordered);
}

Ref<ShapeList> ShapeList::filter_by_axis(const Ref<Axis> &p_axis, double p_minimum, double p_maximum, bool p_min_inclusive, bool p_max_inclusive) const {
    return filter_by_position(p_axis, p_minimum, p_maximum, p_min_inclusive, p_max_inclusive);
}

Ref<ShapeList> ShapeList::filter_by_plane(const Ref<CadPlane> &p_plane, bool p_reverse, double p_tolerance) const {
    ERR_FAIL_COND_V_MSG(p_plane.is_null(), Ref<ShapeList>(), "ShapeList.filter_by_plane requires a non-null plane.");

    Ref<ShapeList> result;
    result.instantiate();
    for (int64_t index = 0; index < shapes.size(); ++index) {
        const Ref<TopoShape> shape = shapes[index];
        if (shape.is_null() || shape->is_null()) {
            continue;
        }
        const bool matches = shape_matches_plane(shape, p_plane, p_tolerance);
        if (matches != p_reverse) {
            result->append(shape);
        }
    }
    return result;
}

Ref<ShapeList> ShapeList::filter_by_length(double p_minimum, double p_maximum, bool p_min_inclusive, bool p_max_inclusive) const {
    return filter_shapes_by_metric(shapes, StringName("get_length"), p_minimum, p_maximum, p_min_inclusive, p_max_inclusive);
}

Ref<ShapeList> ShapeList::filter_by_area(double p_minimum, double p_maximum, bool p_min_inclusive, bool p_max_inclusive) const {
    return filter_shapes_by_metric(shapes, StringName("get_surface_area"), p_minimum, p_maximum, p_min_inclusive, p_max_inclusive);
}

Ref<ShapeList> ShapeList::filter_by_volume(double p_minimum, double p_maximum, bool p_min_inclusive, bool p_max_inclusive) const {
    return filter_shapes_by_metric(shapes, StringName("get_volume"), p_minimum, p_maximum, p_min_inclusive, p_max_inclusive);
}

Ref<ShapeList> ShapeList::filter_by_distance_to_point(const Vector3 &p_point, double p_minimum, double p_maximum, bool p_min_inclusive, bool p_max_inclusive) const {
    ERR_FAIL_COND_V_MSG(p_minimum > p_maximum, Ref<ShapeList>(), "ShapeList.filter_by_distance_to_point requires minimum <= maximum.");

    Ref<ShapeList> result;
    result.instantiate();
    for (int64_t index = 0; index < shapes.size(); ++index) {
        const Ref<TopoShape> shape = shapes[index];
        if (shape.is_null() || shape->is_null()) {
            continue;
        }
        const double distance = shape_center(shape).distance_to(p_point);
        const bool above_min = p_min_inclusive ? distance >= p_minimum : distance > p_minimum;
        const bool below_max = p_max_inclusive ? distance <= p_maximum : distance < p_maximum;
        if (above_min && below_max) {
            result->append(shape);
        }
    }
    return result;
}

Ref<ShapeList> ShapeList::filter_by_shape_type(const String &p_shape_type_name, bool p_reverse) const {
    ERR_FAIL_COND_V_MSG(p_shape_type_name.is_empty(), Ref<ShapeList>(), "ShapeList.filter_by_shape_type requires a non-empty type name.");

    Ref<ShapeList> result;
    result.instantiate();
    for (int64_t index = 0; index < shapes.size(); ++index) {
        const Ref<TopoShape> shape = shapes[index];
        if (shape.is_null() || shape->is_null()) {
            continue;
        }
        const bool matches = shape_type_matches(shape, p_shape_type_name);
        if (matches != p_reverse) {
            result->append(shape);
        }
    }
    return result;
}

Ref<ShapeList> ShapeList::filter_by_geom_type(const String &p_geom_type_name, bool p_reverse) const {
    ERR_FAIL_COND_V_MSG(p_geom_type_name.is_empty(), Ref<ShapeList>(), "ShapeList.filter_by_geom_type requires a non-empty type name.");

    Ref<ShapeList> result;
    result.instantiate();
    for (int64_t index = 0; index < shapes.size(); ++index) {
        const Ref<TopoShape> shape = shapes[index];
        if (shape.is_null() || shape->is_null()) {
            continue;
        }
        const bool matches = geom_type_matches(shape, p_geom_type_name);
        if (matches != p_reverse) {
            result->append(shape);
        }
    }
    return result;
}

Ref<ShapeList> ShapeList::filter_by(const Callable &p_filter_by, bool p_reverse, double p_tolerance) const {
    ERR_FAIL_COND_V_MSG(!p_filter_by.is_valid(), Ref<ShapeList>(), "ShapeList.filter_by requires a valid callable.");
    (void)p_tolerance;

    Ref<ShapeList> result;
    result.instantiate();
    for (int64_t index = 0; index < shapes.size(); ++index) {
        const Ref<TopoShape> shape = shapes[index];
        if (shape.is_null() || shape->is_null()) {
            continue;
        }
        const bool matches = callable_predicate_matches(shape, p_filter_by);
        if (matches != p_reverse) {
            result->append(shape);
        }
    }
    return result;
}

Array ShapeList::group_by_axis(const Ref<Axis> &p_axis, bool p_reverse, int64_t p_tol_digits) const {
    ERR_FAIL_COND_V_MSG(p_axis.is_null(), Array(), "ShapeList.group_by_axis requires a non-null axis.");

    const gp_Dir direction = p_axis->get_occt_axis().Direction();
    const Vector3 origin = p_axis->get_origin();
    return group_shapes_by_key(
            shapes,
            [&direction, &origin](const Ref<TopoShape> &p_shape) {
                const Vector3 center = shape_center(p_shape);
                const Vector3 relative = center - origin;
                return static_cast<double>(relative.x) * direction.X() + static_cast<double>(relative.y) * direction.Y() + static_cast<double>(relative.z) * direction.Z();
            },
            p_tol_digits,
            p_reverse);
}

Array ShapeList::group_by_length(bool p_reverse, int64_t p_tol_digits) const {
    return group_shapes_by_metric(shapes, StringName("get_length"), p_tol_digits, p_reverse);
}

Array ShapeList::group_by_area(bool p_reverse, int64_t p_tol_digits) const {
    return group_shapes_by_metric(shapes, StringName("get_surface_area"), p_tol_digits, p_reverse);
}

Array ShapeList::group_by_volume(bool p_reverse, int64_t p_tol_digits) const {
    return group_shapes_by_metric(shapes, StringName("get_volume"), p_tol_digits, p_reverse);
}

Array ShapeList::group_by_shape_type(bool p_reverse) const {
    return group_shapes_by_shape_type(shapes, p_reverse);
}

Array ShapeList::group_by_geom_type(bool p_reverse) const {
    return group_shapes_by_geom_type(shapes, p_reverse);
}

Array ShapeList::group_by(const Callable &p_group_by, bool p_reverse, int64_t p_tol_digits) const {
    return group_shapes_by_callable(shapes, p_group_by, p_tol_digits, p_reverse);
}

Ref<ShapeList> ShapeList::sort_by_axis(const Ref<Axis> &p_axis, bool p_reverse) const {
    ERR_FAIL_COND_V_MSG(p_axis.is_null(), Ref<ShapeList>(), "ShapeList.sort_by_axis requires a non-null axis.");

    const gp_Dir direction = p_axis->get_occt_axis().Direction();
    const Vector3 origin = p_axis->get_origin();

    std::vector<std::pair<double, Ref<TopoShape>>> ordered;
    ordered.reserve(shapes.size());
    for (int64_t index = 0; index < shapes.size(); ++index) {
        const Ref<TopoShape> shape = shapes[index];
        if (shape.is_null() || shape->is_null()) {
            continue;
        }
        const Vector3 center = shape_center(shape);
        const Vector3 relative = center - origin;
        const double position = static_cast<double>(relative.x) * direction.X() + static_cast<double>(relative.y) * direction.Y() + static_cast<double>(relative.z) * direction.Z();
        ordered.emplace_back(position, shape);
    }

    std::sort(ordered.begin(), ordered.end(), [p_reverse](const auto &p_a, const auto &p_b) {
        if (p_reverse) {
            return p_a.first > p_b.first;
        }
        return p_a.first < p_b.first;
    });

    Array sorted;
    for (const auto &entry : ordered) {
        sorted.push_back(entry.second);
    }
    return shape_list_from_flattened(sorted);
}

Ref<ShapeList> ShapeList::sort_by_length(bool p_reverse) const {
    return sort_shapes_by_metric(shapes, StringName("get_length"), p_reverse);
}

Ref<ShapeList> ShapeList::sort_by_area(bool p_reverse) const {
    return sort_shapes_by_metric(shapes, StringName("get_surface_area"), p_reverse);
}

Ref<ShapeList> ShapeList::sort_by_volume(bool p_reverse) const {
    return sort_shapes_by_metric(shapes, StringName("get_volume"), p_reverse);
}

Ref<ShapeList> ShapeList::sort_by_shape_type(bool p_reverse) const {
    return sort_shapes_by_shape_type(shapes, p_reverse);
}

Ref<ShapeList> ShapeList::sort_by_geom_type(bool p_reverse) const {
    return sort_shapes_by_geom_type(shapes, p_reverse);
}

Ref<ShapeList> ShapeList::sort_by(const Callable &p_sort_by, bool p_reverse) const {
    return sort_shapes_by_callable(shapes, p_sort_by, p_reverse);
}

Ref<ShapeList> ShapeList::sort_by_distance(const Ref<TopoShape> &p_other, bool p_reverse) const {
    ERR_FAIL_COND_V_MSG(p_other.is_null() || p_other->is_null(), Ref<ShapeList>(), "ShapeList.sort_by_distance requires a non-null shape.");

    const Vector3 other_center = shape_center(p_other);
    std::vector<std::pair<double, Ref<TopoShape>>> ordered;
    ordered.reserve(shapes.size());
    for (int64_t index = 0; index < shapes.size(); ++index) {
        const Ref<TopoShape> shape = shapes[index];
        if (shape.is_null() || shape->is_null()) {
            continue;
        }
        ordered.emplace_back(shape_center(shape).distance_to(other_center), shape);
    }

    std::sort(ordered.begin(), ordered.end(), [p_reverse](const auto &p_a, const auto &p_b) {
        if (p_reverse) {
            return p_a.first > p_b.first;
        }
        return p_a.first < p_b.first;
    });

    Array sorted;
    for (const auto &entry : ordered) {
        sorted.push_back(entry.second);
    }
    return shape_list_from_flattened(sorted);
}

Ref<ShapeList> ShapeList::sort_by_distance_to_point(const Vector3 &p_point, bool p_reverse) const {
    std::vector<std::pair<double, Ref<TopoShape>>> ordered;
    ordered.reserve(shapes.size());
    for (int64_t index = 0; index < shapes.size(); ++index) {
        const Ref<TopoShape> shape = shapes[index];
        if (shape.is_null() || shape->is_null()) {
            continue;
        }
        ordered.emplace_back(shape_center(shape).distance_to(p_point), shape);
    }

    std::sort(ordered.begin(), ordered.end(), [p_reverse](const auto &p_a, const auto &p_b) {
        if (p_reverse) {
            return p_a.first > p_b.first;
        }
        return p_a.first < p_b.first;
    });

    Array sorted;
    for (const auto &entry : ordered) {
        sorted.push_back(entry.second);
    }
    return shape_list_from_flattened(sorted);
}
