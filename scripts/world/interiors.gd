## 3D interiors (cutaway rooms): the inn, every workshop and the storehouse.
## One interior exists at a time, built far from the valley at ORIGIN and rebuilt when
## the model changes. Interactions go into world._interact_in.
extends Node3D

const ORIGIN := Vector3(300, 0, 0)
const WALL_H := 3.4

var w: Node3D                 # the world (helpers: _place, _mat; lists; main)
var kind := ""                # "" outside | "inn" | "storehouse" | workshop id
var exit_to := Vector3.ZERO

func enter(id: String, exit_pos: Vector3) -> void:
	kind = id
	exit_to = exit_pos
	build()
	w.player.global_position = ORIGIN + Vector3(0, 0, _size().y / 2.0 - 3.5)
	w.player.body.rotation.y = 0.0
	var rig: Node3D = w.main.rig
	rig.yaw = 0.0
	rig.pitch = deg_to_rad(-55.0)
	rig.dist = 14.0
	rig.anchor = ORIGIN + Vector3(0, 0, -1.5)
	rig.anchor_weight = 0.45
	rig.global_position = rig.anchor

func leave() -> void:
	kind = ""
	for c in get_children(): c.queue_free()
	w._interact_in.clear()
	w.player.global_position = exit_to
	var rig: Node3D = w.main.rig
	rig.pitch = deg_to_rad(-26.0)
	rig.dist = 9.5
	rig.anchor_weight = 0.0
	rig.global_position = exit_to

func _size() -> Vector2:
	return {"inn": Vector2(12, 16), "storehouse": Vector2(10, 12)}.get(kind, Vector2(9, 11))

func build() -> void:
	for c in get_children(): c.queue_free()
	w._interact_in.clear()
	if kind == "": return
	_room(_size())
	match kind:
		"inn": _inn()
		"storehouse": _storehouse()
		_: _workshop(kind)
	_add("Go outside", ORIGIN + Vector3(0, 0, _size().y / 2.0 - 0.3), 1.8, func(): w.main.leave_interior(), "farm")

# ------------------------------------------------------------------ shell

func _room(size: Vector2) -> void:
	var o := ORIGIN
	var meadow := MeshInstance3D.new()      # the garden around the cutaway "dollhouse"
	var pm := PlaneMesh.new()
	pm.size = Vector2(70, 70)
	meadow.mesh = pm
	meadow.position = o + Vector3(0, -0.21, 0)
	meadow.material_override = w._mat(Color("#6FA846"))
	add_child(meadow)
	_solid(_box(Vector3(size.x, 0.2, size.y), o + Vector3(0, -0.1, 0), Color("#B98552")))
	for k in int(size.y / 1.1):   # floorboards
		_box(Vector3(size.x, 0.02, 0.05), o + Vector3(0, 0.01, -size.y / 2 + 0.55 + k * 1.1), Color("#9C6B3E"))
	var wall := Color("#EAD3A8")
	_solid(_box(Vector3(size.x, WALL_H, 0.3), o + Vector3(0, WALL_H / 2, -size.y / 2), wall))
	_solid(_box(Vector3(0.3, WALL_H, size.y), o + Vector3(-size.x / 2, WALL_H / 2, 0), wall))
	_solid(_box(Vector3(0.3, WALL_H, size.y), o + Vector3(size.x / 2, WALL_H / 2, 0), wall))
	var seg := (size.x - 2.4) / 2.0      # low front wall with a doorway in the middle
	for sx in [-1, 1]:
		_solid(_box(Vector3(seg, 0.7, 0.3), o + Vector3(sx * (1.2 + seg / 2), 0.35, size.y / 2), Color("#C49A6C")))
	_box(Vector3(size.x + 0.4, 0.25, 0.4), o + Vector3(0, WALL_H, -size.y / 2), Color("#8A5A3B"))   # beams
	_box(Vector3(size.x, 1.0, 0.05), o + Vector3(0, 0.5, -size.y / 2 + 0.17), Color("#B07A4A"))      # wainscot
	for sx in [-1, 1]:
		_box(Vector3(0.05, 1.0, size.y), o + Vector3(sx * (size.x / 2 - 0.17), 0.5, 0), Color("#B07A4A"))
	_put("furniture/pictureframe_large_A.gltf", 1.0, Vector3(size.x / 2 - 0.3, 2.0, -size.y / 4), -90)
	_put("furniture/pictureframe_medium.gltf", 1.0, Vector3(-size.x / 2 + 0.3, 2.1, size.y / 5), 90)
	for x in [-size.x / 3, size.x / 3]:   # windows on the back wall
		var pane := _box(Vector3(2.0, 1.3, 0.05), o + Vector3(x, 2.0, -size.y / 2 + 0.17), Color("#BFE6F7"))
		var m: StandardMaterial3D = pane.material_override
		m.emission_enabled = true
		m.emission = Color("#9ED8F2") if not w.day.is_night() else Color("#1E2B52")
		_box(Vector3(2.2, 0.12, 0.1), o + Vector3(x, 1.3, -size.y / 2 + 0.2), Color("#8A5A3B"))
	for p in [Vector3(-size.x / 4, 3.0, 0), Vector3(size.x / 4, 3.0, 0)]:
		var l := OmniLight3D.new()
		l.light_color = Color("#FFD6A0")
		l.light_energy = 1.4
		l.omni_range = 12.0
		l.shadow_enabled = false
		l.position = o + p
		add_child(l)

func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = w._mat(color)
	add_child(mi)
	return mi

func _solid(mi: MeshInstance3D) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = (mi.mesh as BoxMesh).size
	cs.shape = shape
	body.add_child(cs)
	body.position = mi.position
	body.collision_layer = 2          # walls block the player but not the camera ray (layer 1)
	add_child(body)

func _put(path: String, scale: float, local: Vector3, yaw := 0.0, solid := false) -> Node3D:
	return w._place(path, scale, ORIGIN + local, yaw, solid, self)

func _sign(text: String, local: Vector3, size := 40, color := Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.006
	l.outline_size = 10
	l.modulate = color
	l.outline_modulate = UI.INK
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = ORIGIN + local
	add_child(l)
	return l

func _icon(item: String, local: Vector3, px := 0.006) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = UI.item_tex(item)
	s.pixel_size = px
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.position = ORIGIN + local
	add_child(s)
	return s

func _add(label, local_or_world: Vector3, radius: float, act: Callable, icon: String) -> void:
	w._interact_in.append({"label": label, "pos": local_or_world, "radius": radius, "act": act, "icon": icon})

# ------------------------------------------------------------------ the inn

const DINING := [Vector3(2.1, 0, -2.2), Vector3(2.1, 0, 1.4), Vector3(-1.4, 0, 1.4), Vector3(2.1, 0, 5.0), Vector3(-1.4, 0, 5.0), Vector3(-1.4, 0, -2.2)]

func _inn() -> void:
	var m: GameModel = Game.model
	var now := Game.now()
	var tier := m.rep_tier()
	var tiers: Array = GameData.economy()["inn"]["reputation_tiers"]
	var next_rep := int(tiers[mini(int(tier["index"]) + 1, tiers.size() - 1)]["reputation"])
	_sign("%s\n★ %d / %d" % [tier["name"], int(m.s["reputation"]), next_rep], Vector3(0, 3.0, -8.2), 44, UI.WHEAT)
	# kitchen along the back wall, Basil at the stove
	_put("restaurant/stove_multi.gltf", 0.75, Vector3(-4.6, 0, -7.4), 0, true)
	_put("restaurant/kitchencounter_straight_A.gltf", 0.75, Vector3(-3.1, 0, -7.4), 0, true)
	_put("restaurant/kitchencounter_sink.gltf", 0.75, Vector3(-1.6, 0, -7.4), 0, true)
	_put("restaurant/fridge_A_decorated.gltf", 0.75, Vector3(-0.1, 0, -7.4), 0, true)
	_put("restaurant/extractorhood.gltf", 0.75, Vector3(-4.6, 2.2, -7.7))
	_put("restaurant/pot_A.gltf", 0.6, Vector3(-4.7, 0.95, -7.3))
	var chef := Character3D.make("Barbarian", Color.WHITE)
	chef.position = ORIGIN + Vector3(-3.1, 0, -6.2)
	chef.scale = Vector3.ONE * 0.8
	add_child(chef)
	chef.play("Idle")
	var q: Array = m.s["buildings"]["kitchen"]["queue"] if m.owns_building("kitchen") else []
	var ready := q.filter(func(j): return float(j["end"]) <= now)
	for k in mini(ready.size(), 4):   # finished plates waiting on the counter
		_put("restaurant/food_dinner.gltf", 0.35, Vector3(-3.7 + k * 0.5, 1.0, -7.1))
	var cooking := q.size() - ready.size()
	if cooking > 0:
		_sign(tr("Cooking %s · %s") % [GameData.item_name(q[ready.size()]["recipe"]), UI.fmt_time(float(q[ready.size()]["end"]) - now)], Vector3(-3.1, 2.6, -6.2), 30)
	_add(func(): return tr("Collect %d meals") % ready.size() if not ready.is_empty() else tr("Cook with Basil"),
		ORIGIN + Vector3(-3.1, 0, -5.2), 2.2, func():
			if not ready.is_empty() and Game.model.collect_building("kitchen", Game.now()) == "":
				Sfx.play("collect")
				w.main.player.do_action("PickUp", ORIGIN + Vector3(-3.1, 0, -7))
			else:
				Screens.workshop(w.main, "kitchen"), "inn")
	# dining tables with seated guests
	var guests: Array = m.inn()["guests"]
	for t in int(tier["tables"]):
		var at: Vector3 = DINING[t]
		_put("restaurant/table_round_A.gltf", 0.5, at, 0, true)
		_put("restaurant/chair_A.gltf", 0.95, at + Vector3(0, 0, 1.15), 180)
		_put("restaurant/chair_A.gltf", 0.95, at + Vector3(0, 0, -1.15))
		_put("restaurant/plate.gltf", 0.4, at + Vector3(0, 0.52, 0))
		if t >= guests.size(): continue
		var g: Dictionary = guests[t]
		var gid: String = g["char"]
		var who := Character3D.make(Character3D.MODELS[abs(gid.hash()) % Character3D.MODELS.size()], Color.from_hsv(float(abs(gid.hash()) % 360) / 360.0, 0.35, 1.0))
		who.scale = Vector3.ONE * 0.72
		who.position = ORIGIN + at + Vector3(0, 0.05, 1.0)
		add_child(who)
		who.play("Sit_Chair_Idle")
		var line := ", ".join(g["order"].keys().map(func(k): return "%s ×%d" % [GameData.item_name(k), int(g["order"][k])]))
		_sign(line, at + Vector3(0, 2.5, 1.0), 22, UI.CREAM)
		for k in g["order"].size():
			_icon(g["order"].keys()[k], at + Vector3(-0.4 + k * 0.8, 3.1, 1.0), 0.004)
		var ti: int = t
		var first: String = GameData.characters()[gid]["name"].split(" ")[0]
		_add(func(): return (tr("Serve %s · %d coins") % [first, m.order_value(g["order"])]) if m.has_items(g["order"]) else tr("%s is waiting for %s") % [first, line],
			ORIGIN + at + Vector3(0, 0, 1.9), 1.6, func(): w.main.serve_inside(ti), "inn")
	# guest rooms along the left wall
	var cfgs: Array = GameData.economy()["inn"]["guest_rooms"]
	var rooms: Array = m.inn()["rooms"]
	for i in cfgs.size():
		var at := Vector3(-4.9, 0, -1.4 + i * 3.0)
		var c: Dictionary = cfgs[i]
		var ri: int = i
		if i < rooms.size() and rooms[i]["furnished"]:
			_put("furniture/bed_single_B.gltf", 0.75, at, 90, true)
			_put("furniture/pillow_A.gltf", 0.8, at + Vector3(-0.7, 0.75, 0), 90)
			var income := m.room_income(i, now)
			_add(func(): return tr("Collect %d coins from room %d") % [m.room_income(ri, Game.now()), ri + 1] if m.room_income(ri, Game.now()) > 0 else tr("Room %d · %d coins/hour") % [ri + 1, int(c["coins_per_hour"])],
				ORIGIN + at + Vector3(1.4, 0, 0), 1.5, func(): w.main.act_result(Game.model.collect_room(ri, Game.now()), "coins"), "coin")
			if income > 0: _sign("+%d" % income, at + Vector3(0, 1.8, 0), 34, UI.WHEAT)
		elif i < rooms.size():
			_put("furniture/rug_rectangle_A.gltf", 0.6, at, 90)
			var need := ", ".join(c["requires"].keys().map(func(k): return "%d %s" % [int(c["requires"][k]), GameData.item_name(k)]))
			_sign(tr("Empty room: needs %s") % need, at + Vector3(0, 1.6, 0), 26)
			_add(tr("Furnish room %d") % (i + 1), ORIGIN + at + Vector3(1.4, 0, 0), 1.5, func(): w.main.act_result(Game.model.furnish_room(ri, Game.now()), "build"), "shop")
		elif m.is_unlocked(c["unlock_level"]) and i == rooms.size():
			_sign(tr("Guest room for sale\n%d coins") % int(c["cost"]), at + Vector3(0, 1.6, 0), 28, UI.WHEAT)
			_add(tr("Build guest room · %d") % int(c["cost"]), ORIGIN + at + Vector3(1.4, 0, 0), 1.5, func(): w.main.act_result(Game.model.build_room(Game.now()), "build"), "shop")
	# furniture the player bought
	var spots := {"furn_rug": ["furniture/rug_oval_A.gltf", 1.0, Vector3(0.4, 0.01, 3.2), 0], "furn_plant": ["furniture/cactus_medium_A.gltf", 1.0, Vector3(5.2, 0, -7.3), 0],
		"furn_bookshelf": ["furniture/shelf_B_large_decorated.gltf", 1.0, Vector3(3.0, 0, -7.7), 0], "furn_fireplace": ["restaurant/stove_multi.gltf", 0.9, Vector3(5.3, 0, -4.5), -90],
		"furn_piano": ["furniture/cabinet_medium_decorated.gltf", 1.0, Vector3(5.3, 0, 3.0), -90], "furn_chandelier": ["furniture/lamp_standing.gltf", 1.0, Vector3(1.4, 0, -6.6), 0]}
	for f in spots:
		if f in m.s["owned"]:
			var sp: Array = spots[f]
			_put(sp[0], sp[1], sp[2], sp[3], true)
	_add(tr("Buy inn furniture"), ORIGIN + Vector3(4.4, 0, -6.6), 1.8, func(): Screens.shop(w.main, "style"), "shop")

# ------------------------------------------------------------------ workshops

## Station props per workshop (all from the CC0 packs) + its signature product.
const STATIONS := {
	"mill": [["village/sack.gltf", 5.0], ["village/crate_open.gltf", 4.5]], "bakery": [["restaurant/stove_multi.gltf", 0.8], ["restaurant/crate_buns.gltf", 0.5]],
	"jam_kitchen": [["restaurant/kitchencounter_straight_A.gltf", 0.8], ["restaurant/jar_A_large.gltf", 0.7]], "dairy": [["restaurant/kitchencounter_sink.gltf", 0.8], ["restaurant/crate_cheese.gltf", 0.5]],
	"craft_table": [["furniture/table_medium.gltf", 0.9], ["furniture/pillow_A.gltf", 1.2]], "soap_maker": [["restaurant/kitchencounter_straight_B.gltf", 0.8], ["restaurant/jar_C_small.gltf", 1.0]],
	"loom": [["furniture/table_medium_long.gltf", 0.9], ["furniture/rug_rectangle_A.gltf", 0.5]],
}

func _workshop(id: String) -> void:
	var m: GameModel = Game.model
	var now := Game.now()
	var b: Dictionary = GameData.buildings()[id]
	var props: Array = STATIONS.get(id, STATIONS["craft_table"])
	_put(props[0][0], props[0][1], Vector3(-1.2, 0, -4.6), 0, true)
	_put(props[1][0], props[1][1], Vector3(1.4, 0, -4.6), 0, true)
	var signature: String = GameData.recipes()[GameData.recipes_for(id)[0]]["outputs"].keys()[0]
	_icon(signature, Vector3(0, 2.6, -5.3), 0.012)
	_sign("%s · %s %d" % [b["name"], tr("Lv"), m.building_level(id) + 1], Vector3(0, 3.35, -5.3), 40, UI.WHEAT)
	var q: Array = m.s["buildings"][id]["queue"]
	var ready := q.filter(func(j): return float(j["end"]) <= now)
	if q.size() > ready.size():
		var j: Dictionary = q[ready.size()]
		_sign(tr("Making %s · %s") % [GameData.item_name(GameData.recipes()[j["recipe"]]["outputs"].keys()[0]), UI.fmt_time(float(j["end"]) - now)], Vector3(0, 1.9, -3.0), 30)
	_add(tr("Work at the %s") % b["name"], ORIGIN + Vector3(0, 0, -2.4), 2.0, func(): Screens.workshop(w.main, id), "shop")
	# finished goods wait in crates on the right
	_put("furniture/shelf_A_big.gltf", 1.0, Vector3(3.9, 0, -1.0), -90, true)
	for k in ready.size():
		var out: String = GameData.recipes()[ready[k]["recipe"]]["outputs"].keys()[0]
		_put("restaurant/crate.gltf", 0.35, Vector3(3.3, 0, -2.5 + k * 0.9))
		_icon(out, Vector3(3.3, 1.0, -2.5 + k * 0.9), 0.0035)
	if not ready.is_empty():
		_add(tr("Collect %d goods") % ready.size(), ORIGIN + Vector3(2.2, 0, -1.5), 2.2, func():
			var err := Game.model.collect_building(id, Game.now())
			w.main.act_result(err, "collect")
			if err == "": w.main.player.do_action("PickUp", ORIGIN + Vector3(3.3, 0, -1.5)), "barn")
	var levels: Array = b["levels"]
	var nxt := m.building_level(id) + 1
	if nxt < levels.size():
		_sign(tr("Upgrade: %d slots · %d coins") % [int(levels[nxt]["slots"]), int(levels[nxt]["cost"])], Vector3(-2.4, 1.8, -2.0), 22)
		_add(tr("Upgrade · %d coins") % int(levels[nxt]["cost"]), ORIGIN + Vector3(-3.0, 0, -1.0), 1.6, func(): w.main.act_result(Game.model.upgrade_building(id), "build"), "coin")

# ------------------------------------------------------------------ storehouse

func _storehouse() -> void:
	var m: GameModel = Game.model
	_sign(tr("Silo %d / %d   ·   Barn %d / %d") % [m.storage_used("silo"), m.storage_cap("silo"), m.storage_used("barn"), m.storage_cap("barn")], Vector3(0, 3.0, -6.2), 40, UI.WHEAT)
	var ids: Array = m.s["inv"].keys()
	ids.sort_custom(func(a, b): return GameData.storage_kind(a) < GameData.storage_kind(b) or GameData.storage_kind(a) == GameData.storage_kind(b) and a < b)
	for k in ids.size():
		var id: String = ids[k]
		var at := Vector3(-3.6 + (k % 5) * 1.8, 0, -4.6 + (k / 5) * 1.9)
		var stack := clampi(int(ceil(m.count(id) / 10.0)), 1, 3)
		for s in stack:
			_put("restaurant/crate.gltf", 0.38, at + Vector3(0, s * 0.72, 0))
		_icon(id, at + Vector3(0, stack * 0.72 + 0.55, 0), 0.0035)
		_sign("×%d" % m.count(id), at + Vector3(0, stack * 0.72 + 1.15, 0), 26)
	if ids.is_empty():
		_sign(tr("Empty: harvest something!"), Vector3(0, 1.5, -2), 36)
	_add(tr("Upgrade storage"), ORIGIN + Vector3(-3.5, 0, 4.0), 1.8, func(): Screens.shop(w.main, "farm"), "barn")
	_add(tr("Open inventory"), ORIGIN + Vector3(3.5, 0, 4.0), 1.8, func(): Screens.barn(w.main), "barn")
