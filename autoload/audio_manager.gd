extends Node
## Music/SFX bus control, kept alive across scene changes. No audio assets
## yet (v1 M0-M2 scope) — stubbed so scenes have a stable API to call into.

var music_player: AudioStreamPlayer

func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Master"
	add_child(music_player)

func play_music(stream: AudioStream) -> void:
	if stream == null:
		return
	music_player.stream = stream
	music_player.play()

func stop_music() -> void:
	music_player.stop()
