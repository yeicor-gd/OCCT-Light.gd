## Manages game audio: background music from an OGG file and procedural SFX tones.
extends Node
class_name AudioManager

# Tone frequencies for each sound event
const FREQ_JUMP := 440.0
const FREQ_LAND := 220.0
const FREQ_DEATH_START := 330.0
const FREQ_WIN_START := 523.0
const BG_AUDIO := preload("res://ball_game/audio/background.ogg")

@export var master_volume_db: float = 0.0
@export var music_volume_db: float = 4.0
@export var sfx_volume_db: float = -4.0

var _bg_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer
var _muted := false

func _ready() -> void:
	_setup_audio_buses()
	_setup_background()
	_setup_sfx()

func _setup_audio_buses() -> void:
	_apply_bus_volume()


func is_muted() -> bool:
	return _muted


func set_muted(value: bool) -> void:
	_muted = value
	_apply_bus_volume()


func toggle_mute() -> void:
	set_muted(not _muted)


func _apply_bus_volume() -> void:
	var idx := AudioServer.get_bus_index("Master")
	if _muted:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, master_volume_db)

func _setup_background() -> void:
	_bg_player = AudioStreamPlayer.new()
	_bg_player.name = "BGMusic"
	add_child(_bg_player)
	_bg_player.stream = BG_AUDIO
	_bg_player.volume_db = music_volume_db
	_bg_player.autoplay = false

func _setup_sfx() -> void:
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "SFX"
	add_child(_sfx_player)
	_sfx_player.volume_db = sfx_volume_db

func play_background() -> void:
	if _bg_player and not _bg_player.playing:
		_bg_player.play()

func stop_background() -> void:
	if _bg_player:
		_bg_player.stop()

## Play a short beep tone for a given event.
func play_sfx(event: String) -> void:
	var freq := 440.0
	var duration := 0.15
	var wave_type := "sine"
	match event:
		"jump":
			freq = FREQ_JUMP; duration = 0.1
		"land":
			freq = FREQ_LAND; duration = 0.08; wave_type = "square"
		"death":
			freq = FREQ_DEATH_START; duration = 0.6; wave_type = "descend"
		"win":
			freq = FREQ_WIN_START; duration = 0.8; wave_type = "ascend"
		"collect":
			freq = 660.0; duration = 0.12
	_play_tone(freq, duration, wave_type)

func _play_tone(freq: float, duration: float, wave_type: String) -> void:
	var sample_rate := 22050
	var frames := int(sample_rate * duration)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	for i in range(frames):
		var t := float(i) / float(sample_rate)
		var env := 1.0 - float(i) / float(frames)  # linear decay
		var f := freq
		if wave_type == "descend":
			f = freq * (1.0 - float(i) / float(frames) * 0.5)
		elif wave_type == "ascend":
			f = freq * (1.0 + float(i) / float(frames) * 0.5)
		var sample := sin(TAU * f * t) * env
		if wave_type == "square":
			sample = sign(sample) * env * 0.5
		samples[i] = sample * 0.4

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	# Convert float to 8-bit PCM
	var pcm := PackedByteArray()
	pcm.resize(frames)
	for i in range(frames):
		pcm[i] = int(clampf(samples[i] * 127.0 + 128.0, 0, 255))
	wav.data = pcm
	_sfx_player.stream = wav
	_sfx_player.play()
