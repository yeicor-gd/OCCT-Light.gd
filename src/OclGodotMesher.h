// ---------------------------------------------------------------------------
// Hand-written meshing helper for occtl_graph_t handle classes.
// Provides Godot-friendly batch meshing (ArrayMesh, MultiMesh,
// PhysicsBody3D collision shapes) on top of auto-generated OclGraphHandle.
// ---------------------------------------------------------------------------

#ifndef OCLGODOTMESHER_H
#define OCLGODOTMESHER_H

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <cstdint>
#include "occtl/occtl_curves.h"
#include "occtl/occtl_topo.h"

#include "OclMeshOptions.h"
#include "autowrapper/OclGraphHandle.h"

using namespace godot;

class OclGodotMesher : public godot::RefCounted {
    GDCLASS(OclGodotMesher, godot::RefCounted)
protected:
    static void _bind_methods();
public:
    // --- Meshing methods ---

    /// Triangulate faces into an ArrayMesh, or create collision shapes on a PhysicsBody3D.
    /// @param graph      The graph handle (must be valid).
    /// @param existing   Optional ArrayMesh, MultiMesh, or PhysicsBody3D to reuse.
    ///                   - ArrayMesh: surfaces cleared, user customizations preserved.
    ///                   - PhysicsBody3D: one ConcavePolygonShape3D child per face
    ///                     with metadata key "feature_id" mapping to the face node ID.
    ///                   - Null/nil: a fresh ArrayMesh is created.
    /// @param options    Meshing options (deflection, angle, ...).
    ///                   When null, OCL_MESH_OPTIONS_INIT defaults are used.
    /// @param face_ids   Nil for all faces, or a PackedInt64Array of face node IDs.
    /// @param include_normals     Compute angle-thresholded smooth normals.
    /// @param include_uvs         Include UV coordinates if available.
    /// @param include_tangents    Compute tangent vectors (requires normals + UVs).
    /// @param include_feature_ids Encode face node IDs as vertex colors.
    static Ref<ArrayMesh> mesh_faces(
        const Ref<OclGraphHandle>& graph,
        const Variant& existing = Variant(),
        const Ref<OclMeshOptions>& options = Ref<OclMeshOptions>(),
        const Variant& face_ids = Variant(),
        bool include_normals = false,
        bool include_uvs = false,
        bool include_tangents = false,
        bool include_feature_ids = false
    );

    /// Build edge tube instances as a MultiMesh, or create collision shapes on a PhysicsBody3D.
    /// A low-resolution cylinder mesh is instanced along each edge polyline
    /// segment using MultiMesh transforms.
    /// @param graph      The graph handle (must be valid).
    /// @param existing   Optional MultiMesh or PhysicsBody3D to reuse.
    ///                   - MultiMesh: mesh+transforms replaced, user customizations preserved.
    ///                   - PhysicsBody3D: one CylinderShape3D child per segment
    ///                     with metadata key "feature_id" mapping to the edge node ID.
    ///                   - Null/nil: a fresh MultiMesh is created.
    /// @param options    Meshing options (controls cylinder resolution via angle).
    /// @param edge_ids   Nil for all edges, or a PackedInt64Array of edge node IDs.
    /// @param radius     Tube radius.  <= 0 uses opts.deflection * 10.
    static Ref<MultiMesh> mesh_edges(
        const Ref<OclGraphHandle>& graph,
        const Variant& existing = Variant(),
        const Ref<OclMeshOptions>& options = Ref<OclMeshOptions>(),
        const Variant& edge_ids = Variant(),
        double radius = 0.01
    );

    /// Build vertex sphere instances as a MultiMesh, or create collision shapes on a PhysicsBody3D.
    /// A low-resolution sphere mesh is instanced at each vertex position.
    /// @param graph      The graph handle (must be valid).
    /// @param existing   Optional MultiMesh or PhysicsBody3D to reuse.
    ///                   - MultiMesh: mesh+transforms replaced, user customizations preserved.
    ///                   - PhysicsBody3D: one SphereShape3D child per vertex
    ///                     with metadata key "feature_id" mapping to the vertex node ID.
    ///                   - Null/nil: a fresh MultiMesh is created.
    /// @param options    Meshing options (controls sphere resolution via angle).
    /// @param vertex_ids Nil for all vertices, or a PackedInt64Array of vertex IDs.
    /// @param radius     Sphere radius.  <= 0 uses opts.deflection * 10.
    static Ref<MultiMesh> mesh_vertices(
        const Ref<OclGraphHandle>& graph,
        const Variant& existing = Variant(),
        const Ref<OclMeshOptions>& options = Ref<OclMeshOptions>(),
        const Variant& vertex_ids = Variant(),
        double radius = 0.02
    );
};

#endif // OCLGODOTMESHER_H
