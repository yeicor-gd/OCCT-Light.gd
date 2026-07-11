#ifndef OCLMESHTOGODOT_H
#define OCLMESHTOGODOT_H

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/physics_body3d.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <cstdint>

#include "autowrapper/OclMeshOptions.h"
#include "autowrapper/OclGraphHandle.h"

using namespace godot;

class OclMeshToGodot : public godot::Resource {
    GDCLASS(OclMeshToGodot, godot::Resource)
protected:
    static void _bind_methods();
public:
    static int mesh_faces(
        const Ref<OclGraphHandle>& graph,
        const Ref<ArrayMesh>& existing,
        const Ref<OclMeshOptions>& options = Ref<OclMeshOptions>(),
        const Variant& face_ids = Variant(),
        bool include_uvs = false,
        bool include_tangents = false,
        bool include_feature_ids = false
    );

    static int mesh_edges(
        const Ref<OclGraphHandle>& graph,
        const Ref<MultiMesh>& existing,
        const Ref<OclMeshOptions>& options = Ref<OclMeshOptions>(),
        const Variant& edge_ids = Variant(),
        double radius = 0.01
    );

    static int mesh_vertices(
        const Ref<OclGraphHandle>& graph,
        const Ref<MultiMesh>& existing,
        const Ref<OclMeshOptions>& options = Ref<OclMeshOptions>(),
        const Variant& vertex_ids = Variant(),
        double radius = 0.02
    );

    static int mesh_faces_collision(
        const Ref<OclGraphHandle>& graph,
        PhysicsBody3D* body,
        const Ref<OclMeshOptions>& options = Ref<OclMeshOptions>(),
        const Variant& face_ids = Variant()
    );

    static int mesh_edges_collision(
        const Ref<OclGraphHandle>& graph,
        PhysicsBody3D* body,
        const Ref<OclMeshOptions>& options = Ref<OclMeshOptions>(),
        const Variant& edge_ids = Variant(),
        double radius = 0.01
    );

    static int mesh_vertices_collision(
        const Ref<OclGraphHandle>& graph,
        PhysicsBody3D* body,
        const Ref<OclMeshOptions>& options = Ref<OclMeshOptions>(),
        const Variant& vertex_ids = Variant(),
        double radius = 0.02
    );

    // --- New methods for the improved OclManager ---

    /// Merge multiple sets of surface arrays into one single surface array.
    /// Each element in |surfaces| must be a Godot Mesh::ARRAY_MAX-sized Array
    /// (as returned by ArrayMesh::surface_get_arrays).  All data is concatenated
    /// into one set of arrays with indices remapped appropriately.
    static Array merge_surface_arrays(const Array& surfaces);

    /// Extract face triangle vertices as a single flat PackedVector3Array
    /// (3 vertices per triangle, Godot winding, ready for ConcavePolygonShape3D).
    static PackedVector3Array extract_face_triangles(
        const Ref<OclGraphHandle>& graph,
        const Ref<OclMeshOptions>& options = Ref<OclMeshOptions>(),
        const Variant& face_ids = Variant()
    );
};

#endif // OCLMESHTOGODOT_H
