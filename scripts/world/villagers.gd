## Village life outside: villagers stroll the square (more by day, fewer at night) and
## travellers walk the lane to and from the inn; new inn guests arrive the same way.
## Pure presentation: the model never knows about any of them.
extends Node3D

const LANE_END := Vector3(-0.7, 0, 44)      # off-screen end of the lane between the fields
const LANE_TOP := Vector3(-0.7, 0, -1.0)    # where the lane meets the square
const INN_DOOR := Vector3(0, 0, -10.2)
## Strolling spots around the square (clear of the fountain, tables and NPCs).
const SPOTS := [Vector3(-4.5, 0, -2.2), Vector3(4.2, 0, -8.6), Vector3(-6.5, 0, -6), Vector3(5, 0, -2.4), Vector3(-4, 0, -8.8),
	Vector3(7, 0, -5.2), Vector3(2.6, 0, -1.2), Vector3(-2.4, 0, -1.6), Vector3(-1.8, 0, 1.6), Vector3(1.6, 0, 2.2), Vector3(10, 0, -3), Vector3(-10, 0, -3.5)]

var w: Node3D
var _strollers: Array[Character3D] = []
var _travel_clock := 4.0
var _rng := RandomNumberGenerator.new()

## How many villagers stroll at a given hour: busy days, a quiet evening, two night owls.
static func wanted(hour: float) -> int:
	if hour >= 7.0 and hour < 19.0: return 7
	if hour >= 19.0 and hour < 22.0: return 4
	return 2

## Around the fountain, never through it: a detour point when the straight line crosses it.
static func route(from: Vector3, to: Vector3) -> Array:
	var c := Vector3(0, 0, -5.5)
	var mid := (from + to) / 2.0
	var seg := to - from
	var t := clampf((c - from).dot(seg) / maxf(seg.length_squared(), 0.001), 0.0, 1.0)
	if (from + seg * t - c).length() > 2.8: return [to]
	var side := Vector3(-seg.z, 0, seg.x).normalized()
	if side.dot(mid - c) < 0.0: side = -side
	return [c + side * 3.4, to]

func _ready() -> void:
	_rng.seed = 11
	Game.event.connect(func(name: String, d: Dictionary):
		if name == "guest" and str(d.get("char", "")) != "" and w.interiors.kind == "": arrive())
	for i in wanted(w.day.current_hour()):
		_add_stroller(SPOTS[i % SPOTS.size()])

func _process(dt: float) -> void:
	var want := wanted(w.day.hour)
	if _strollers.size() < want: _add_stroller(LANE_TOP)
	elif _strollers.size() > want:   # someone heads home down the lane
		var c: Character3D = _strollers.pop_back()
		c.walk(route(c.global_position, LANE_TOP) + [LANE_END], c.queue_free)
	for c in _strollers:
		if not c.walking() and not c.busy() and _rng.randf() < dt * 0.25:
			if _rng.randf() < 0.2: c.play(["Interact", "Cheer", "PickUp"][_rng.randi() % 3])
			else: c.walk(route(c.global_position, SPOTS[_rng.randi() % SPOTS.size()]))
	_travel_clock -= dt
	if _travel_clock <= 0.0:   # a traveller comes to the inn, or leaves it, every 20-40 s by day
		_travel_clock = _rng.randf_range(20.0, 40.0) * (1.0 if want > 2 else 3.0)
		if _rng.randf() < 0.5: arrive()
		else: depart()

func _villager(at: Vector3) -> Character3D:
	var c := Character3D.make_look(Character3D.random_look(_rng.randi(), true))
	c.scale = Vector3.ONE * 0.72
	add_child(c)
	c.global_position = at
	c.rotation.y = _rng.randf() * TAU
	return c

func _add_stroller(at: Vector3) -> void:
	var c := _villager(at)
	c.speed = 1.2
	_strollers.append(c)

## A guest walks up the lane, across the square and in through the inn door.
func arrive() -> void:
	var c := _villager(LANE_END)
	c.walk([LANE_TOP] + route(LANE_TOP, INN_DOOR), c.queue_free)

## A fed guest steps out of the inn and walks away down the lane.
func depart() -> void:
	var c := _villager(INN_DOOR)
	c.walk(route(INN_DOOR, LANE_TOP) + [LANE_END], c.queue_free)
