extends BoxContainer

@export var tests_scene: PackedScene
@export var ball_game_scene: PackedScene

func _ready():
	var env_test_runner := OS.get_environment("GODOT_TEST_RUNNER") == "true"
	var is_headless_mode := DisplayServer.get_name() == "headless"
	var should_auto_test := env_test_runner or is_headless_mode
	if OS.get_environment("GDEXT_AUTO_TESTS") == "true" or should_auto_test:
		_on_tests_button_pressed()
	elif OS.get_environment("GDEXT_AUTO_BALL_GAME") == "true":
		_on_ball_game_button_pressed()

func _on_tests_button_pressed() -> void:
	if tests_scene != null:
		get_tree().change_scene_to_packed.call_deferred(tests_scene)
	else:
		push_error("Tests scene not set")

func _on_ball_game_button_pressed() -> void:
	if ball_game_scene != null:
		get_tree().change_scene_to_packed.call_deferred(ball_game_scene)
	else:
		push_error("Ball game scene not set")
