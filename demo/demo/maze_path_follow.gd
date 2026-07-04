@tool
extends PathFollow3D

@export var play_in_editor := false
@export var speed := 0.1 # m/s

func _ready():
	progress = 0

func _process(delta: float) -> void:
	if play_in_editor or not Engine.is_editor_hint():
		progress += delta * speed
