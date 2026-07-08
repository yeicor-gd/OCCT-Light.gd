@tool
extends Node
class_name TrackExporter

## Editor-attachable tool for exporting the generated track mesh to STL / OBJ.
##
## Attach this to any node in the scene (e.g. under a "Tools" container). Set the
## NodePath references to point at the mesh output nodes created by OclMeshBuilder,
## then click one of the export buttons in the inspector.
##
## Future: support batch export of all formats at once, configurable scale/transform,
## and integration with PersistenceManager for ResourceSaver–based workflows.

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

@export_group("Targets")

## Path to the Faces MeshInstance3D (track surface mesh).
@export_node_path("MeshInstance3D") var faces_node: NodePath

## Path to the OclManager (falls back to finding it from parent chain).
@export_node_path("Node3D") var ocl_manager_node: NodePath

@export_group("Output")

## Output file path for STL export (relative to project).
@export_file("*.stl") var stl_output_path := "res://demo/demo/generated/track_export.stl"

## Output file path for OBJ export (relative to project).
@export_file("*.obj") var obj_output_path := "res://demo/demo/generated/track_export.obj"

## Solid/object name embedded in the exported file.
@export var solid_name := "maze_track"

@export_group("Actions")

@export_tool_button("Export as STL") var export_stl_ = _export_stl
@export_tool_button("Export as OBJ") var export_obj_ = _export_obj
@export_tool_button("Export Both") var export_all_ = _export_all

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

func _resolve_faces() -> MeshInstance3D:
	if faces_node and not faces_node.is_empty():
		return get_node_or_null(faces_node) as MeshInstance3D
	var ocl := get_node_or_null(ocl_manager_node) if ocl_manager_node and not ocl_manager_node.is_empty() else null
	if not ocl:
		var p := get_parent()
		while p:
			if p is OclMeshBuilder:
				ocl = p
				break
			p = p.get_parent()
	if ocl and ocl.has_node("Faces"):
		return ocl.get_node("Faces") as MeshInstance3D
	return null

func _log(msg: String):
	print("[TrackExporter] ", msg)

# -----------------------------------------------------------------------------
# Export actions
# -----------------------------------------------------------------------------

func _export_stl():
	var mi := _resolve_faces()
	if not mi or not mi.mesh:
		push_error("TrackExporter: Faces mesh not found. Generate the track first.")
		return

	var mesh := mi.mesh as ArrayMesh
	if not mesh or mesh.get_surface_count() == 0:
		push_error("TrackExporter: Faces mesh is empty.")
		return

	var err := MeshExportUtils.write_mesh_stl(stl_output_path, mesh, solid_name)
	if err != OK:
		push_error("TrackExporter: STL export failed with error ", err)
		return

	_log("STL exported to ", stl_output_path)

	if Engine.is_editor_hint():
		_refresh_filesystem()


func _export_obj():
	var mi := _resolve_faces()
	if not mi or not mi.mesh:
		push_error("TrackExporter: Faces mesh not found. Generate the track first.")
		return

	var mesh := mi.mesh as ArrayMesh
	if not mesh or mesh.get_surface_count() == 0:
		push_error("TrackExporter: Faces mesh is empty.")
		return

	var err := MeshExportUtils.write_mesh_obj(obj_output_path, mesh, solid_name)
	if err != OK:
		push_error("TrackExporter: OBJ export failed with error ", err)
		return

	_log("OBJ exported to ", obj_output_path)

	if Engine.is_editor_hint():
		_refresh_filesystem()


func _export_all():
	_export_stl()
	_export_obj()


func _refresh_filesystem():
	var fs := EditorInterface.get_resource_filesystem()
	if fs:
		fs.scan()
