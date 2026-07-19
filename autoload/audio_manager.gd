extends Node
## Music/SFX bus control, kept alive across scene changes. No audio assets
## yet (v1 M0-M2 scope) — stubbed so scenes have a stable API to call into.

var music_player: AudioStreamPlayer

## SFX categories the UI hooks into -- matching the "司令デッキ化計画" design
## proposal's own scope ("決定/キャンセル/警告音", not a distinct sound per
## button): 決定 for committing an action (queue production, propose a
## treaty, start research, confirm a dialogue choice), キャンセル for
## closing/backing out of a panel, 警告 for a destructive/adversarial action
## (breaking a treaty, discarding). Every call site across the game's panels
## calls play_sfx() with one of these unconditionally, regardless of whether
## a real audio file is registered yet -- see play_sfx()'s own doc comment
## for why that's the deliberate design, not dead code.
const SFX_CONFIRM := &"confirm"
const SFX_CANCEL := &"cancel"
const SFX_WARNING := &"warning"

## No audio assets exist in this project yet. Every entry starts null;
## register_sfx() (or editing this dictionary directly once real files are
## imported) is the *only* place that needs to change for every already-
## wired button in the game to start playing sound, with no changes needed
## anywhere else.
var sfx_streams: Dictionary = {
	SFX_CONFIRM: null,
	SFX_CANCEL: null,
	SFX_WARNING: null,
}

## A small round-robin pool, not one shared player, so two SFX triggered in
## quick succession (e.g. a rapid double-click) don't cut each other off.
const SFX_POOL_SIZE := 4
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx_player := 0

func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Master"
	add_child(music_player)
	for i in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_sfx_players.append(player)

func play_music(stream: AudioStream) -> void:
	if stream == null:
		return
	music_player.stream = stream
	music_player.play()

func stop_music() -> void:
	music_player.stop()

## Registers (or replaces) the stream played for one SFX category. The one
## call site that needs to change once real audio files exist -- every
## button already wired to e.g. play_sfx(SFX_CONFIRM) picks it up
## automatically, with no other code touched.
func register_sfx(id: StringName, stream: AudioStream) -> void:
	sfx_streams[id] = stream

## Silently does nothing if `id` has no stream registered (always true
## right now, since sfx_streams starts empty and nothing has called
## register_sfx() yet -- see this file's own doc comment on why every UI
## call site fires this unconditionally anyway rather than checking first).
func play_sfx(id: StringName) -> void:
	var stream: AudioStream = sfx_streams.get(id)
	if stream == null:
		return
	var player := _sfx_players[_next_sfx_player]
	_next_sfx_player = (_next_sfx_player + 1) % _sfx_players.size()
	player.stream = stream
	player.play()
