@tool
class_name PersistenceManager
extends RefCounted

## Utility for saving/loading mesh data to/from disk via ResourceSaver.
##
## Designed for the upcoming feature that moves large mesh data out of the
## .tscn file and into the `generated/` folder as standalone .tres/.res
## resources.
##
## Usage sketch (future, in OclMeshBuilder):
##   var path = PersistenceManager.mesh_resource_path("segment_%03d" % i)
##   PersistenceManager.save_mesh(mesh, path)
##   var loaded: ArrayMesh = PersistenceManager.load_mesh(path)
##
## TODO: Integrate with OclMeshBuilder's _append_graph_faces so that after
##       meshing each segment, the ArrayMesh is saved to disk and the scene
##       node simply references the resource instead of embedding it inline.

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------

## Base directory for generated resource files.
const GENERATED_DIR := "res://demo/demo/generated"

## Build a full .res path for a named mesh resource.
static func mesh_resource_path(name: String) -> String:
	return GENERATED_DIR.path_join("%s.res" % name)


# -----------------------------------------------------------------------------
# Save / Load
# -----------------------------------------------------------------------------

## Save an ArrayMesh to disk as a .res file.
## Returns OK on success, or an error code.
static func save_mesh(mesh: ArrayMesh, resource_path: String) -> Error:
	# Ensure the directory exists.
	var dir := resource_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)

	var err := ResourceSaver.save(mesh, resource_path)
	if err != OK:
		push_error("PersistenceManager: Failed to save mesh to ", resource_path, " (error ", err, ")")
	return err


## Load an ArrayMesh from a .res file saved with save_mesh().
## Returns null on failure.
static func load_mesh(resource_path: String) -> ArrayMesh:
	if not ResourceLoader.exists(resource_path):
		push_error("PersistenceManager: Resource does not exist: ", resource_path)
		return null

	var res := ResourceLoader.load(resource_path, "ArrayMesh")
	if res == null:
		push_error("PersistenceManager: Failed to load mesh from ", resource_path)
		return null
	return res as ArrayMesh


# -----------------------------------------------------------------------------
# Bulk operations (skeleton)
# -----------------------------------------------------------------------------

## Save all meshes produced by an OclMeshBuilder's Faces node as individual
## resources and return an array of paths.
##
## TODO: Call this from OclMeshBuilder.regenerate() when persistence mode is
## enabled, then set the Faces.mesh to the first loaded resource and add child
## MeshInstance3D nodes referencing the rest.
static func save_all_face_surfaces(faces_mesh: ArrayMesh, base_name: String) -> PackedStringArray:
	var paths := PackedStringArray()
	for i in faces_mesh.get_surface_count():
		var arrays := faces_mesh.surface_get_arrays(i)
		var single := ArrayMesh.new()
		single.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		# Copy material if present.
		var mat := faces_mesh.surface_get_material(i)
		if mat:
			single.surface_set_material(0, mat)

		var path := mesh_resource_path("%s_surface_%03d" % [base_name, i])
		var err := save_mesh(single, path)
		if err == OK:
			paths.append(path)
		single = null  # free intermediate
	return paths
