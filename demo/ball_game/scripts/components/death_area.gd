@tool
extends Area3D
class_name DeathArea

@export var spawner: Spawner
@export var death_overlay: UIOverlay
@onready var mesh := $Mesh
var mesh_noise: FastNoiseLite

## Automatically syncs the CSG sphere radius with the parent MazeGenerator's
## outer radius.

func _ready():
	mesh_noise = (((mesh.material_override as StandardMaterial3D).albedo_texture as NoiseTexture2D).noise as FastNoiseLite)
	var parent := get_parent_node_3d()
	if parent is MazeGenerator:
		parent.regeneration_finished.connect(_sync_from_parent)
	if not Engine.is_editor_hint():
		_sync_from_parent()
		visible = true

func _process(_delta: float):
	if mesh_noise != null:
		var t := Time.get_ticks_usec() / 10000000.0
		mesh_noise.offset = Vector3(10.867 * sin(t), 35.124 * cos(t), 43.234 * sin(953.43 - t))

func _sync_from_parent():
	mesh.radius = $"..".maze_inner_radius
	$Shape.shape.radius = $"..".maze_inner_radius

func _on_body_entered(body: Node3D) -> void:
	if body.get_parent_node_3d() == spawner.current_player:
		spawner.current_player.set_game_active(false)
		death_overlay.show_game_over()
	elif body.name == "Faces":
		#push_warning("Bad maze: faces collide with death area!")
		pass
	else:
		print("Ignoring unknown body entered death area: ", body.name)
