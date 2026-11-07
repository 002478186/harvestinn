## Day/night cycle: moves the sun, recolours sky/ambient/fog, and lights lamps, windows,
## stars and fireflies after dusk. Pure presentation: game timers stay real-time.
extends Node

signal hour_changed(hour: int)

var sun: DirectionalLight3D
var env: Environment
var sky: ProceduralSkyMaterial
var lamps: Array[Dictionary] = []     # {mat: StandardMaterial3D, light: OmniLight3D}
var night_fx: Array[Node3D] = []      # stars, fireflies: visible at night only
var hour := 9.0
var forced := -1.0                    # dev: -- --hour=21
var indoor := false                   # inside a room: the lamps light it, not the sun
var _last_hour := -1

## Colour keys through the day: hour -> [sky top, horizon, sun colour, sun energy, ambient energy]
const KEYS := [
	[0.0,  "#060C22", "#18224A", "#8FA8FF", 0.3, 0.16],
	[5.0,  "#1B2350", "#E0906A", "#FFB07A", 0.35, 0.3],
	[7.0,  "#6FB8EE", "#F7D6A8", "#FFE2B8", 1.1, 0.5],
	[12.0, "#5DB7F0", "#CDEBF7", "#FFF1D6", 1.45, 0.55],
	[17.0, "#5AA9E6", "#F4D0A0", "#FFD9A6", 1.2, 0.5],
	[19.0, "#3A3F78", "#F08A5C", "#FF9A5C", 0.55, 0.38],
	[21.0, "#0A1232", "#232A58", "#9FB2FF", 0.3, 0.18],
	[24.0, "#060C22", "#18224A", "#8FA8FF", 0.3, 0.16],
]

func _cfg() -> Dictionary:
	return GameData.economy()["day_night"]

func current_hour() -> float:
	if forced >= 0.0: return forced
	var mins := float(_cfg()["day_minutes"])
	if mins <= 0.0:
		var t := Time.get_time_dict_from_system()
		return t["hour"] + t["minute"] / 60.0
	return fmod(float(_cfg()["start_hour"]) + Game.now() / (mins * 60.0) * 24.0, 24.0)

func is_night() -> bool:
	return hour >= float(_cfg()["lamps_on"]) or hour < float(_cfg()["lamps_off"])

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hour="): forced = float(a.substr(7))

func _process(_dt: float) -> void:
	if sun == null: return
	hour = current_hour()
	var a: Array = KEYS[0]
	var b: Array = KEYS[1]
	for i in KEYS.size() - 1:
		if hour >= KEYS[i][0] and hour <= KEYS[i + 1][0]:
			a = KEYS[i]
			b = KEYS[i + 1]
	var t: float = (hour - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0]))
	sky.sky_top_color = Color(a[1]).lerp(Color(b[1]), t)
	sky.sky_horizon_color = Color(a[2]).lerp(Color(b[2]), t)
	sky.ground_horizon_color = sky.sky_horizon_color
	sun.light_color = Color(a[3]).lerp(Color(b[3]), t)
	sun.light_energy = lerpf(a[4], b[4], t)
	env.ambient_light_energy = lerpf(a[5], b[5], t)
	env.fog_light_color = sky.sky_horizon_color
	if indoor:
		sun.light_energy *= 0.3
		env.ambient_light_energy *= 0.6
	# sun arc: rises east (hour 6), highest at noon, sets west (18); a cool moon light at night
	var day_t := (hour - 6.0) / 12.0
	var elev: float = sin(clampf(day_t, 0.0, 1.0) * PI) * 62.0 + 8.0 if day_t > 0.0 and day_t < 1.0 else 35.0
	sun.rotation_degrees = Vector3(-elev, -90.0 + day_t * 180.0 if day_t > 0.0 and day_t < 1.0 else 150.0, 0)
	var night := is_night()
	for l in lamps:
		if l.has("mat"): l["mat"].emission_energy_multiplier = 2.5 if night else 0.2
		l["light"].visible = night and not indoor
	for n in night_fx: n.visible = night
	if int(hour) != _last_hour:
		_last_hour = int(hour)
		hour_changed.emit(_last_hour)

## "8:15 pm" style clock for the HUD.
func clock_text() -> String:
	var h := int(hour)
	var m := int((hour - h) * 60.0) / 15 * 15
	return "%d:%02d %s" % [12 if h % 12 == 0 else h % 12, m, "am" if h < 12 else "pm"]
