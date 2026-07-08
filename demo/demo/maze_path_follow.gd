@tool
extends PathFollow3D

@export var play_in_editor := false
@export var speed := 0.1 # m/s

@onready var curve := $"..".curve as Curve3D
@onready var cam := $"Camera3D"

func _ready():
	progress = 0

func _process(delta: float) -> void:
	if play_in_editor or not Engine.is_editor_hint():
		progress += delta * speed
		if progress+0.001 < curve.get_baked_length():
			var next_point := curve.sample_baked(progress+0.001, cubic_interp)
			look_at(next_point, position.normalized())
