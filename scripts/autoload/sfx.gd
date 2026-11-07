## Audio mixer: Master <- Music, Ambience, SFX, UI buses. Day and night music crossfade,
## a wind bed loops on Ambience, music and ambience duck while a sheet/popup is open.
## Mute toggles (and haptics) are saved in user://settings.cfg.
## Missing audio files are skipped silently, so logic never depends on audio.
extends Node

const SETTINGS := "user://settings.cfg"
const UI_SOUNDS := ["click", "pop", "error"]
const MUSIC_DB := -5.0       # music files sit ~-14 dB RMS: -5 keeps them under the action sounds
const DUCK_DB := -8.0
var sfx_on := true
var music_on := true
var haptics_on := true
var _players: Array[AudioStreamPlayer] = []
var _day := AudioStreamPlayer.new()
var _night := AudioStreamPlayer.new()
var _ambience := AudioStreamPlayer.new()
var _cache := {}
var _night_on := false
var _ducked := false

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		sfx_on = cfg.get_value("audio", "sfx", true)
		music_on = cfg.get_value("audio", "music", true)
		haptics_on = cfg.get_value("audio", "haptics", true)
	for bus in ["Music", "Ambience", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), 0.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("UI"), -6.0)
	var lim := AudioEffectLimiter.new()   # safety net: stacked coins + music never clip
	lim.ceiling_db = -1.0
	AudioServer.add_bus_effect(0, lim)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for p in [_day, _night, _ambience]:
		add_child(p)
	_day.bus = "Music"
	_night.bus = "Music"
	_ambience.bus = "Ambience"
	_ambience.volume_db = -16.0   # the wind bed: felt, not heard
	play_music()

## A looping copy of a WAV (seamless, no gap from restarting on `finished`).
func loop_stream(name: String) -> AudioStream:
	var st := _stream(name)
	if st is AudioStreamWAV:
		st = st.duplicate()
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.get_length() * st.mix_rate)
	return st

## Night music fades in at dusk and the day tune fades out (and back at dawn), over 4 s.
func set_night(night: bool) -> void:
	if night == _night_on: return
	_night_on = night
	var tw := create_tween().set_parallel()
	tw.tween_property(_day, "volume_db", -60.0 if night else 0.0, 4.0)
	tw.tween_property(_night, "volume_db", 0.0 if night else -60.0, 4.0)

## Popups and sheets: music and ambience step back so the UI and dialogue read clearly.
func duck(on: bool) -> void:
	if on == _ducked: return
	_ducked = on
	for bus in ["Music", "Ambience"]:
		var idx := AudioServer.get_bus_index(bus)
		var base := MUSIC_DB if bus == "Music" else 0.0
		create_tween().tween_method(func(db: float): AudioServer.set_bus_volume_db(idx, db),
			AudioServer.get_bus_volume_db(idx), base + (DUCK_DB if on else 0.0), 0.3)

func _stream(name: String) -> AudioStream:
	if not _cache.has(name):
		_cache[name] = null
		for ext in ["wav", "ogg"]:
			var path := "res://assets/audio/%s.%s" % [name, ext]
			if ResourceLoader.exists(path):
				_cache[name] = load(path)
				break
	return _cache[name]

func play(name: String, pitch_jitter := 0.08) -> void:
	if not sfx_on: return
	var st := _stream(name)
	if st == null: return
	for p in _players:
		if not p.playing:
			p.stream = st
			p.bus = "UI" if name in UI_SOUNDS else "SFX"
			p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
			p.play()
			return

## Haptic tap by importance: "light" (buttons, planting), "medium" (harvest, coins), "heavy" (level up, building).
func buzz(tier := "light") -> void:
	if not haptics_on or not OS.has_feature("mobile"): return
	Input.vibrate_handheld({"light": 12, "medium": 25, "heavy": 60}.get(tier, 12), {"light": 0.35, "medium": 0.6, "heavy": 1.0}.get(tier, 0.35))

func set_haptics(on: bool) -> void:
	haptics_on = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "haptics", on)
	cfg.save(SETTINGS)

func play_music() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), MUSIC_DB + (DUCK_DB if _ducked else 0.0))
	if _day.stream == null:
		_day.stream = loop_stream("music_day")
		_night.stream = loop_stream("music_night")
		_ambience.stream = loop_stream("ambience")
		_day.volume_db = -60.0 if _night_on else 0.0
		_night.volume_db = 0.0 if _night_on else -60.0
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Ambience"), not music_on)
	for p in [_day, _night, _ambience]:
		if music_on and p.stream:
			if not p.playing: p.play()
		else: p.stop()

func set_audio(sfx: bool, music: bool) -> void:
	sfx_on = sfx
	music_on = music
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "sfx", sfx)
	cfg.set_value("audio", "music", music)
	cfg.save(SETTINGS)
	play_music()
