@tool
extends Node3D
class_name MazeObstacles

## Standalone obstacle generation node.
## Generates positive obstacles (boxes or scripted shapes) along all path pairs,
## independent of the tube mesh generation.

@export_group("Obstacles")

## Frequency of positive obstacles along the track (obstacles per segment unit).
@export_range(0.0, 0.5, 0.01) var obstacle_positive_frequency: float = 0.1
## Seed offset for obstacle randomisation.
@export var obstacle_seed_offset: int = 0
## Debug mode: always adds boxes instead of obstacle shapes, for visualising placement.
@export var obstacle_debug_mode: bool = false
## Debug: max rotation multiplier [0-1] applied to obstacle placement (0 = axis-aligned, 1 = full).
@export_range(0.0, 1.0, 0.01) var obstacle_debug_max_rotation: float = 1.0
## Debug: max offset multiplier [0-1] applied to obstacle placement.
@export var obstacle_debug_max_offset: Vector2 = Vector2(1.0, 1.0)
## Debug: min offset multiplier [0-1] applied to force minimum displacement.
@export var obstacle_debug_min_offset: Vector2 = Vector2(0.0, 0.0)

@export_group("Appearance")
## Optional material override for obstacle faces (uses faces material from Meshes if null).
@export var obstacle_material: Material
## Optional material override for obstacle edges (uses edges material from Meshes if null).
@export var obstacle_edges_material: Material
## Optional material override for obstacle vertices (uses vertices material from Meshes if null).
@export var obstacle_vertices_material: Material
## Display edge radius (< 0 = fixed, 0 = disabled).
@export var obstacle_edge_radius: float = -0.01
## Display vertex radius (< 0 = fixed, 0 = disabled).
@export var obstacle_vertex_radius: float = -0.02
## Number of longitudinal rings for edge cylinders (0 = use Mesher value).
@export_range(0, 16, 1) var obstacle_edge_rings: int = 0
## Number of latitudinal rings for vertex spheres (0 = use Mesher value).
@export_range(0, 16, 1) var obstacle_vertex_rings: int = 0

@export_group("Physics")
## Generate collision shapes from obstacle face triangles.
@export var physics_show_faces: bool = true

@export_group("Persistence")

## Base path for saving generated obstacle resources. Empty = memory-only.
@export var resource_save_path := "res://ball_game/generated/maze_obstacles"

@export_tool_button("Regenerate Obstacles") var regen_ = func(): _build_obstacles()

# State — resolved from sibling Meshes (OclMeshBuilder) at build time.
var _wall_height_cdf: Curve
var _wall_height_noise: FastNoiseLite

func _ready():
	pass

func _ensure_wall_height_cdf(source: Curve):
	if source == null:
		source = Curve.new()
		source.add_point(Vector2(0.0, 0.0))
		source.add_point(Vector2(0.5, 0.8))
		source.add_point(Vector2(1.0, 1.5))
	_wall_height_cdf = source

func _sample_wall_height(noise_input: float) -> float:
	if not is_finite(noise_input):
		return 0.8
	var n := _wall_height_noise.get_noise_1d(noise_input)
	if not is_finite(n):
		return 0.8
	var t := clampf(n * 0.5 + 0.5, 0.0, 1.0)
	var h := _wall_height_cdf.sample(t)
	if not is_finite(h):
		return 0.8
	return h

func _build_obstacles():
	var start_time := Time.get_ticks_usec()

	# Idempotent: remove all existing children immediately (not queue_free).
	for child in get_children():
		remove_child(child)
		child.free()

	var gen := _find_generator()
	assert(gen != null, "MazeObstacles: MazeGenerator parent not found")
	var paths := gen.get_node_or_null("Paths")
	assert(paths != null, "MazeObstacles: MazeGenerator/Paths node not found")
	var main_path := paths.get_node_or_null("MainPath") as Path3D
	assert(main_path != null, "MazeObstacles: Paths/MainPath node not found")
	var main_aux := paths.get_node_or_null("MainPathBinormal") as Path3D
	assert(main_aux != null, "MazeObstacles: Paths/MainPathBinormal node not found")

	# Read shared config from the canonical source — OclMeshBuilder (Meshes).
	var meshes := gen.get_node_or_null("Meshes") as OclMeshBuilder
	assert(meshes != null, "MazeObstacles: MazeGenerator/Meshes node not found")
	var wall_thickness: float = meshes.wall_thickness
	var wall_height_noise_freq: float = meshes.wall_height_noise_freq
	var display_options: OclMeshOptions = meshes.display_options
	var display_faces_material: Material = meshes.display_faces_material
	var display_edges_material: Material = meshes.display_edges_material
	var display_vertices_material: Material = meshes.display_vertices_material
	var eff_edge_rings: int = obstacle_edge_rings if obstacle_edge_rings > 0 else meshes.edge_rings
	var eff_vertex_rings: int = obstacle_vertex_rings if obstacle_vertex_rings > 0 else meshes.vertex_rings

	# Intermediate container — all generated children go here so that
	# _persist_resources can save them as a single .scn (keeping subresources
	# out of the local .tscn).
	var container := Node3D.new()
	container.name = "Generated"
	add_child(container)
	if Engine.is_editor_hint():
		container.owner = get_tree().edited_scene_root if is_inside_tree() else null

	if obstacle_positive_frequency <= 0.0:
		print("[MazeObstacles] Frequency is 0, skipping.")
		return

	var obstacle_scripts := _discover_obstacle_scripts()
	if obstacle_scripts.is_empty():
		print("[MazeObstacles] No obstacle scripts found.")
		return

	var profile_cfg := ProfileBuilder.Config.new(
		gen.ball_radius,
		gen.ball_to_path_min_ratio,
		wall_thickness,
	)

	_ensure_wall_height_cdf(meshes.wall_height_cdf)
	_wall_height_noise = FastNoiseLite.new()
	_wall_height_noise.seed = gen.seed_value + obstacle_seed_offset
	_wall_height_noise.frequency = wall_height_noise_freq
	_wall_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	# Collect path pairs.
	var path_pairs := _collect_path_pairs(paths)
	var total_obstacles := 0

	for pair in path_pairs:
		var path_curve: Curve3D = pair["path"].curve
		var aux_curve: Curve3D = pair["aux"].curve
		var pair_name: String = pair["name"]
		var seg_count := path_curve.point_count - 1
		if seg_count <= 0:
			continue

		# Precompute per-segment wall heights.
		var pair_baked_len := path_curve.get_baked_length()
		var segment_wall_heights := PackedFloat32Array()
		segment_wall_heights.resize(path_curve.point_count)
		for si in range(path_curve.point_count):
			var t := float(si) / float(maxi(path_curve.point_count - 1, 1))
			segment_wall_heights[si] = _sample_wall_height(t * pair_baked_len)

		var num_obstacles := maxi(1, int(seg_count * obstacle_positive_frequency))
		var br: float = profile_cfg.ball_radius
		var bd: float = 2.0 * br
		var ratio := profile_cfg.ball_to_path_min_ratio
		var inner_hw: float = bd / ratio.x * 0.5
		var inner_h: float = bd / ratio.y
		var clearance: float = inner_hw - br
		var max_floor_h: float = br * 0.4
		var max_wall_d: float = clearance

		var rng := RandomNumberGenerator.new()
		rng.seed = gen.seed_value + obstacle_seed_offset + pair_name.length() * 7919

		for obs_i in range(num_obstacles):
			var t_val := (obs_i + 0.5) / num_obstacles
			var seg_idx := int(t_val * seg_count)
			seg_idx = clampi(seg_idx, 0, path_curve.point_count - 2)
			var xf := CurveUtils.transform_at_index(path_curve, seg_idx, aux_curve)

			var wall_h: float = clampf(segment_wall_heights[seg_idx], 0.0, 1.0)
			var wh_clamped: float = minf(wall_h, 1.0) * inner_h

			var surface: int = [Surface.FLOOR, Surface.LEFT_WALL, Surface.RIGHT_WALL][rng.randi() % 3]

			var local_pos := Vector3.ZERO
			var aabb_size := Vector3.ZERO
			var local_normal := Vector3(0, 1, 0)
			var angle: float = rng.randf() * TAU * obstacle_debug_max_rotation
			var cos_a: float = cos(angle)
			var sin_a: float = sin(angle)

			match surface:
				Surface.FLOOR:
					var h: float = rng.randf_range(0.2, 0.5) * max_floor_h
					var sx: float = rng.randf_range(0.3, 0.8) * br
					var sz: float = rng.randf_range(0.3, 0.8) * br
					aabb_size = Vector3(sx, h, sz)
					var lateral_x: float = sx * abs(cos_a) + sz * abs(sin_a)
					var min_ox: float = minf(0.0, minf(sx * cos_a, minf(sz * sin_a, sx * cos_a + sz * sin_a)))
					var cx_max: float = inner_hw - lateral_x * 0.5
					var x_frac: float = clampf(rng.randf_range(obstacle_debug_min_offset.x, obstacle_debug_max_offset.x), 0.0, 1.0)
					var cx: float = x_frac * cx_max * (1.0 if rng.randi() % 2 == 0 else -1.0)
					var y_pos: float = -br
					local_pos = Vector3(cx - min_ox - lateral_x * 0.5, y_pos, 0.0)
				Surface.LEFT_WALL, Surface.RIGHT_WALL:
					var h: float = rng.randf_range(0.3, 0.8) * minf(wh_clamped, br * 0.6)
					var protrusion: float = rng.randf_range(0.5, 1.0) * max_wall_d
					var length: float = rng.randf_range(0.6, 1.0) * br
					aabb_size = Vector3(protrusion, h, length)
					var eff_x: float = protrusion * abs(cos_a) + length * abs(sin_a)
					if eff_x > clearance:
						var s: float = clearance / eff_x
						protrusion *= s
						length *= s
						aabb_size = Vector3(protrusion, h, length)
						eff_x = clearance
					var min_ox: float = minf(0.0, minf(protrusion * cos_a, minf(length * sin_a, protrusion * cos_a + length * sin_a)))
					var cx: float
					if surface == Surface.LEFT_WALL:
						cx = -(inner_hw + br) * 0.5
					else:
						cx = (inner_hw + br) * 0.5
					var y_range: float = wh_clamped - h
					var y_frac: float = clampf(rng.randf_range(obstacle_debug_min_offset.y, obstacle_debug_max_offset.y), 0.0, 1.0) if y_range > 0 else 0.5
					var y_pos: float = -br + y_frac * y_range
					local_pos = Vector3(cx - min_ox - eff_x * 0.5, y_pos, 0.0)

			var rot_basis := Basis(local_normal.normalized(), angle)
			var obs_xf := xf.translated_local(local_pos)
			obs_xf.basis = xf.basis * rot_basis
			var obs_aabb := AABB(Vector3.ZERO, aabb_size)

			# Build obstacle into its own graph.
			var graph = GraphUtils.create_graph()
			var obs_bits: PackedInt64Array
			var status: OclCore.status
			if obstacle_debug_mode:
				var box_info := OclPrimBoxInfo.new()
				box_info.placement = OcctConversionUtils.transform3d_to_occt_placement(obs_xf)
				box_info.dx = aabb_size.x
				box_info.dy = aabb_size.y
				box_info.dz = aabb_size.z
				var box_id := OclNodeId.new()
				status = OclPrimSolid.box(graph, box_info, box_id) as OclCore.status
				if status != OclCore.OK:
					OclTopo.graph_free(graph)
					continue
				obs_bits = PackedInt64Array([box_id.get_bits()])
			else:
				obs_bits = obstacle_scripts[rng.randi() % obstacle_scripts.size()].build(graph, obs_aabb, obs_xf)

			if obs_bits.is_empty():
				OclTopo.graph_free(graph)
				continue

			# Tessellate the obstacle graph.
			var am := ArrayMesh.new()
			status = OclMeshToGodot.mesh_faces(graph, am, display_options, null, true, false, false) as OclCore.status

			# Extract edge transforms.
			var e_mm := MultiMesh.new()
			var has_edges := obstacle_edge_radius != 0.0 and OclMeshToGodot.mesh_edges(graph, e_mm, display_options, null, obstacle_edge_radius) == OclCore.OK

			# Extract vertex transforms.
			var v_mm := MultiMesh.new()
			var has_verts := obstacle_vertex_radius != 0.0 and OclMeshToGodot.mesh_vertices(graph, v_mm, display_options, null, obstacle_vertex_radius) == OclCore.OK

			# Extract face triangles for physics.
			var face_tris := PackedVector3Array()
			if physics_show_faces:
				face_tris = OclMeshToGodot.extract_face_triangles(graph, display_options, null)

			OclTopo.graph_free(graph)
			if status != OclCore.OK:
				continue

			# --- Face mesh ---
			var obs_mat: Material = obstacle_material if obstacle_material else display_faces_material
			if obs_mat:
				am.surface_set_material(0, obs_mat)

			var obs_node_name := "%s_Obs%d" % [pair_name if pair_name else "Main", total_obstacles]
			var has_physics := face_tris.size() >= 3
			var obs_root: Node3D
			if has_physics:
				obs_root = StaticBody3D.new()
			else:
				obs_root = Node3D.new()
			obs_root.name = obs_node_name
			container.add_child(obs_root)
			if Engine.is_editor_hint():
				obs_root.owner = get_tree().edited_scene_root if is_inside_tree() else null

			var mi := MeshInstance3D.new()
			mi.name = "FacesMesh"
			mi.mesh = am
			obs_root.add_child(mi)
			if Engine.is_editor_hint():
				mi.owner = get_tree().edited_scene_root if is_inside_tree() else null

			# --- Face collision ---
			if face_tris.size() >= 3:
				var shape := ConcavePolygonShape3D.new()
				shape.set_faces(face_tris)
				var cs := CollisionShape3D.new()
				cs.name = "CollisionFaces"
				cs.shape = shape
				obs_root.add_child(cs)
				if Engine.is_editor_hint():
					cs.owner = get_tree().edited_scene_root if is_inside_tree() else null

			# --- Edge display ---
			if has_edges:
				var slices := OclMeshBuilder._slices_from_angle(display_options.angle)
				var cyl := CylinderMesh.new()
				cyl.height = 1.0
				cyl.radial_segments = slices
				cyl.rings = eff_edge_rings
				cyl.radial_segments = eff_edge_rings
				cyl.cap_top = false
				cyl.cap_bottom = false
				var e_mat: Material = obstacle_edges_material if obstacle_edges_material else display_edges_material
				if e_mat:
					cyl.surface_set_material(0, e_mat)
				e_mm.mesh = cyl
				var e_mmi := MultiMeshInstance3D.new()
				e_mmi.name = "EdgesMesh"
				e_mmi.multimesh = e_mm
				obs_root.add_child(e_mmi)
				if Engine.is_editor_hint():
					e_mmi.owner = get_tree().edited_scene_root if is_inside_tree() else null

			# --- Vertex display ---
			if has_verts:
				var sph := SphereMesh.new()
				sph.radius = 1.0
				sph.radial_segments = eff_vertex_rings
				sph.rings = eff_vertex_rings
				var v_mat: Material = obstacle_vertices_material if obstacle_vertices_material else display_vertices_material
				if v_mat:
					sph.surface_set_material(0, v_mat)
				v_mm.mesh = sph
				var v_mmi := MultiMeshInstance3D.new()
				v_mmi.name = "VerticesMesh"
				v_mmi.multimesh = v_mm
				obs_root.add_child(v_mmi)
				if Engine.is_editor_hint():
					v_mmi.owner = get_tree().edited_scene_root if is_inside_tree() else null

			total_obstacles += 1

	print("[MazeObstacles] Built %d obstacles in %.2f ms" % [total_obstacles, (Time.get_ticks_usec() - start_time) / 1000.0])

	if Engine.is_editor_hint():
		_persist_resources()


# Surface type for obstacle placement.
enum Surface { FLOOR, LEFT_WALL, RIGHT_WALL }


func _collect_path_pairs(paths: Node3D) -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	var path: Path3D = paths.get_node_or_null("MainPath") as Path3D
	var aux_path: Path3D = paths.get_node_or_null("MainPathBinormal") as Path3D
	if path and aux_path:
		pairs.append({ "name": "", "path": path, "aux": aux_path })

	for child in paths.get_children():
		if not child is Path3D:
			continue
		var cn := str(child.name)
		if cn.begins_with("Shortcut") and not cn.ends_with("Binormal"):
			var sc_aux_name := cn + "Binormal"
			var sc_aux := paths.get_node_or_null(sc_aux_name) as Path3D
			if sc_aux:
				pairs.append({ "name": cn + "_", "path": child, "aux": sc_aux })
	return pairs


func _discover_obstacle_scripts() -> Array[Script]:
	var scripts: Array[Script] = []
	var dir := DirAccess.open("res://ball_game/scripts/components/obstacles")
	if dir != null:
		dir.list_dir_begin()
		while true:
			var fname := dir.get_next()
			if fname == "":
				break
			if dir.current_is_dir():
				continue
			if not fname.begins_with("obstacle_") or not fname.ends_with(".gd"):
				continue
			if fname == "obstacle_base.gd" or fname == "obstacle_index.gd":
				continue
			var path := "res://ball_game/scripts/components/obstacles/" + fname
			var script := load(path)
			if script is Script and script.has_method("build"):
				scripts.append(script)
		dir.list_dir_end()
		return scripts
	var entries := ObstacleIndex.get_all()
	for e in entries:
		scripts.append(e["script"])
	return scripts


func _find_generator() -> MazeGenerator:
	var p = get_parent()
	while p:
		if p is MazeGenerator:
			return p
		p = p.get_parent()
	push_error("MazeObstacles: MazeGenerator ancestor not found in parent chain")
	return null


# -----------------------------------------------------------------------------
# Resource persistence
# -----------------------------------------------------------------------------

func _persist_resources() -> void:
	if resource_save_path.is_empty():
		return

	var base := resource_save_path.trim_suffix("/")
	var dir_abs := ProjectSettings.globalize_path(base)
	DirAccess.make_dir_recursive_absolute(dir_abs)

	var container := get_node_or_null("Generated") as Node3D
	if container == null:
		return

	var path := base + "/Generated.scn"
	_save_branch(container, path)

	# Hot-swap: replace the in-memory container with the persisted instance.
	var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var instance := packed.instantiate()
	instance.name = "Generated"

	var idx := container.get_index()
	remove_child(container)
	add_child(instance)
	move_child(instance, idx)
	instance.owner = get_tree().edited_scene_root if is_inside_tree() else null


func _save_branch(branch: Node, path: String) -> Error:
	for child in branch.get_children():
		_set_owner_recursive(child, branch)
	var packed := PackedScene.new()
	var err := packed.pack(branch)
	if err != OK:
		return err
	return ResourceSaver.save(packed, path)


func _set_owner_recursive(node: Node, mowner: Node) -> void:
	node.owner = mowner
	for child in node.get_children():
		_set_owner_recursive(child, mowner)
