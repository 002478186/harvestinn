extends TestCase

func test_mixer_buses_and_seamless_loops() -> bool:
	for bus in ["Music", "Ambience", "SFX", "UI"]:
		truthy(AudioServer.get_bus_index(bus) >= 0, bus + " bus exists")
	var sfx: Node = tree.root.get_node("Sfx")
	var st: AudioStreamWAV = sfx.loop_stream("music_night")
	eq(st.loop_mode, AudioStreamWAV.LOOP_FORWARD, "music loops without a restart gap")
	for name in ["music_day", "birds", "water", "chatter", "crickets", "sell", "feed", "serve", "pop", "achieve", "cluck", "moo", "baa", "bleat"]:
		truthy(sfx._stream(name) != null, name + " exists")
	return true

func test_ducking_and_night_are_idempotent() -> bool:
	var sfx: Node = tree.root.get_node("Sfx")
	sfx.duck(true)
	sfx.duck(true)
	truthy(sfx._ducked, "ducked")
	sfx.duck(false)
	sfx.set_night(true)
	truthy(sfx._night_on, "night music on")
	sfx.set_night(false)
	return true
