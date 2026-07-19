extends Node
## Music/SFX bus control, kept alive across scene changes. No real music or
## voice/SE assets exist yet (v1 M0-M2 scope); the three UI SFX categories
## are placeholder tones synthesized at runtime (see _synthesize_tone below)
## rather than left silent, so the game has *some* audio feedback in the
## meantime. register_sfx() stays the one call site to swap any of these for
## a real authored sound later — nothing else in the game needs to change.

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

## Filled with synthesized placeholder tones in _ready() (see
## _synthesize_tone). register_sfx() (or editing this dictionary directly
## once real files are imported) is the *only* place that needs to change
## for every already-wired button in the game to switch to real audio, with
## no changes needed anywhere else.
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

	# Placeholder tones -- see _synthesize_tone's own doc comment. Cheap
	# enough (a few hundred samples each) to just build every time the
	# autoload boots rather than caching anything to disk.
	register_sfx(SFX_CONFIRM, _synthesize_tone([
		{"freq": 660.0, "duration": 0.05},
		{"freq": 990.0, "duration": 0.07},
	]))
	register_sfx(SFX_CANCEL, _synthesize_tone([
		{"freq": 392.0, "duration": 0.09},
	]))
	register_sfx(SFX_WARNING, _synthesize_tone([
		{"freq": 220.0, "duration": 0.08},
		{"freq": 196.0, "duration": 0.08},
		{"freq": 220.0, "duration": 0.08},
		{"freq": 196.0, "duration": 0.08},
	]))

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

const SYNTH_MIX_RATE := 44100
const SYNTH_AMPLITUDE := 0.35

## Builds a placeholder UI tone entirely in code (a plain sine wave per
## segment, played back to back) -- no audio file, import step, or external
## tool involved, so this works the same on a machine that has never had a
## real .wav dropped into the project. `segments`: Array of
## {"freq": float, "duration": float} played in sequence, e.g. two short
## rising notes for a "confirm" blip. Each segment gets its own short linear
## attack/release (independent of the others) so back-to-back segments don't
## click at their boundary, and the very first/last sample of the whole
## stream still starts and ends at zero.
func _synthesize_tone(segments: Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	for segment: Dictionary in segments:
		var freq: float = segment.freq
		var duration: float = segment.duration
		var sample_count := int(duration * SYNTH_MIX_RATE)
		var attack := mini(sample_count / 4, int(0.005 * SYNTH_MIX_RATE))
		var release := mini(sample_count / 4, int(0.02 * SYNTH_MIX_RATE))
		var offset := bytes.size()
		bytes.resize(offset + sample_count * 2)
		for i in range(sample_count):
			var envelope := 1.0
			if i < attack:
				envelope = float(i) / maxf(1.0, float(attack))
			elif i >= sample_count - release:
				envelope = float(sample_count - i) / maxf(1.0, float(release))
			var t := float(i) / SYNTH_MIX_RATE
			var value := sin(TAU * freq * t) * envelope * SYNTH_AMPLITUDE
			bytes.encode_s16(offset + i * 2, int(clampf(value, -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SYNTH_MIX_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
