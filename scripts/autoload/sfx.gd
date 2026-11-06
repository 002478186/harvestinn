## Sound effects + music with separate mute toggles (saved in user://settings.cfg).
## Missing audio files are skipped silently, so logic never depends on audio.
extends Node

const SETTINGS := "user://settings.cfg"
var sfx_on := true
var music_on := true
var _players: Array[AudioStreamPlayer] = []
var _music := AudioStreamPlayer.new()
var _cache := {}

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		sfx_on = cfg.get_value("audio", "sfx", true)
		music_on = cfg.get_value("audio", "music", true)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	add_child(_music)
	_music.volume_db = -10.0
	_music.finished.connect(_music.play)
	play_music()

func _stream(name: String) -> AudioStream:
	if not _cache.has(name):
		var path := "res://assets/audio/%s.wav" % name
		_cache[name] = load(path) if ResourceLoader.exists(path) else null
	return _cache[name]

func play(name: String, pitch_jitter := 0.08) -> void:
	if not sfx_on: return
	var st := _stream(name)
	if st == null: return
	for p in _players:
		if not p.playing:
			p.stream = st
			p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
			p.play()
			return

func play_music() -> void:
	_music.stream = _stream("music_farm")
	if music_on and _music.stream:
		_music.play()
	else:
		_music.stop()

func set_audio(sfx: bool, music: bool) -> void:
	sfx_on = sfx
	music_on = music
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "sfx", sfx)
	cfg.set_value("audio", "music", music)
	cfg.save(SETTINGS)
	play_music()
