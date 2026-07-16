@tool
extends PathFollow3D
class_name MazePathFollow

## Follows the maze path with a configurable-speed camera.

@export var play_in_editor := false
@export var speed := 0.1  # m/s

@onready var _path := $".." as Path3D

func _ready():
	progress = 0.0
	if not Engine.is_editor_hint():
		visible = true

func _process(delta: float) -> void:
	if play_in_editor or not Engine.is_editor_hint():
		progress += delta * speed
		if _path and _path.curve:
			transform.basis = CurveUtils.transform_at_baked(_path.curve, progress).basis
