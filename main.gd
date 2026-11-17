extends Node
## A five-storey Soviet stairwell (podъezd) in PS1 style, using the PSX Look addon.
##
## The level is saved inside main.tscn. This script only rebuilds it when the game is run with
## "-- --bake" (which overwrites main.tscn); otherwise it just runs the lights, sounds and the
## fifth-floor event.

const HX := 1.35           # half width of the stair shaft
const LX := 2.6            # half width of the apartment landings
const LZ := -2.6           # back wall of the landings
const RUN := 2.52          # horizontal length of one flight
const Z_END := 4.0         # window wall behind the half-landings
const STOREY := 3.0
const FLOORS := 5
const STEPS := 9
const RISE := 1.5 / STEPS
const TREAD := RUN / STEPS
const GAP := 0.15          # half width of the well between the flights
const TOP := STOREY * (FLOORS - 1) + 2.8
const CELL := 0.5          # polygons are cut to about this size, as PS1 games did

const TEX := "res://assets/psx/"
const MODELS := "res://assets/models/"
const AUDIO := "res://assets/audio/"
const HUM_DB := -34.0     # loudness of the electric hum from each lamp

var psx: PSXScreen
var world: Node3D
var body: StaticBody3D
var player: CharacterBody3D
var rng := RandomNumberGenerator.new()
var mats := {}

# Mesh building state.
var _zones := {}           # layer bit -> {material name: SurfaceTool}
var _zone_names := {}
var _target: Dictionary
var _bit := 0
var _tint := Color.WHITE
var _grime := FastNoiseLite.new()

# Runtime state.
var event_sounds: Array[AudioStream] = []
var _event_t := 10.0
var _flick := {}
var _teased := false
var _scare := 0
var _scare_t := 0.0
var _steps_far: Array[AudioStream] = []
var _testing := false


func _enter_tree() -> void:
	# Echoing concrete stairwell. Must exist before any sound player is ready.
	if AudioServer.get_bus_index("Reverb") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Reverb")
		AudioServer.set_bus_send(idx, "Master")
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.8
		rv.damping = 0.3
		rv.spread = 0.8
		rv.wet = 0.4
		rv.dry = 0.9
		rv.predelay_msec = 45.0
		AudioServer.add_bus_effect(idx, rv)
	# Handling things: dry, with just the short slap of a small concrete space.
	if AudioServer.get_bus_index("Foley") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Foley")
		AudioServer.set_bus_send(idx, "Master")
		var slap := AudioEffectReverb.new()
		slap.room_size = 0.12
		slap.damping = 0.8
		slap.spread = 0.4
		slap.wet = 0.06
		slap.dry = 1.0
		slap.predelay_msec = 8.0
		AudioServer.add_bus_effect(idx, slap)
	# Other floors and flats, heard through concrete: dull and far.
	if AudioServer.get_bus_index("Muffled") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Muffled")
		AudioServer.set_bus_send(idx, "Reverb")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 900.0
		lp.db = AudioEffectFilter.FILTER_12DB
		AudioServer.add_bus_effect(idx, lp)
	# The city outside, heard through walls and closed windows: only the low end gets in.
	if AudioServer.get_bus_index("Outside") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Outside")
		AudioServer.set_bus_send(idx, "Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 420.0
		lp.resonance = 0.4
		lp.db = AudioEffectFilter.FILTER_24DB
		AudioServer.add_bus_effect(idx, lp)
		var room := AudioEffectReverb.new()
		room.room_size = 0.5
		room.damping = 0.8
		room.wet = 0.15
		room.dry = 0.9
		AudioServer.add_bus_effect(idx, room)


func _ready() -> void:
	rng.seed = 1986
	if "--regraffiti" in OS.get_cmdline_user_args():
		_regraffiti()
		return
	var bake := "--bake" in OS.get_cmdline_user_args()
	if bake or get_child_count() == 0:
		for c in get_children():
			remove_child(c)
			c.free()
		_build_all()
	_runtime_init()
	if bake:
		_bake()
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_take_shots(a.trim_prefix("--shot="))


func _unhandled_input(event: InputEvent) -> void:
	if player and not _testing:
		player.handle_input(event)


# ============================================================ layers / zones
# Every part of the building sits on its own render layer so a lamp only lights the
# rooms it could really reach (lights here cast no shadows, as on the PS1).

func _zl(k: int) -> int:   # apartment landing of floor k (0-based)
	return k

func _za(k: int) -> int:   # flight up from floor k and the half-landing above it (k = -1: entry hall)
	return 6 + k

func _zb(k: int) -> int:   # flight from that half-landing up to floor k + 1 (the entry flight shares the hall's)
	return _za(-1) if k < 0 else 11 + k

func _zone(bit: int, title: String) -> void:
	if not _zones.has(bit):
		_zones[bit] = {}
		_zone_names[bit] = title
	_target = _zones[bit]
	_bit = bit


# ============================================================ materials

func _make_materials() -> void:
	for n in ["wall", "plaster", "concrete", "tile", "metal_teal", "metal_grey", "wood", "door",
			"door_metal", "panel", "mailbox", "doormat"]:
		mats[n] = PSX.make(&"lit", load(TEX + n + ".png"))
	var cutout: Shader = load("res://shaders/psx_cutout.gdshader")
	for n in ["rail", "peel_a", "peel_b", "stain", "paper_a", "paper_b"]:
		mats[n] = _shader_mat(cutout, load(TEX + n + ".png"))
	var unlit: Shader = load("res://shaders/psx_unlit.gdshader")
	mats["window"] = _shader_mat(unlit, load(TEX + "window.png"))
	mats["black"] = _shader_mat(unlit, null, Color(0.004, 0.004, 0.006))
	mats["bulb"] = _shader_mat(unlit, null, Color(1.0, 0.78, 0.4))
	mats["bulb_sick"] = _shader_mat(unlit, null, Color(0.55, 0.75, 0.4))
	mats["figure"] = _shader_mat(load("res://shaders/psx_cutout_unlit.gdshader"), load(TEX + "figure.png"))
	for m: ShaderMaterial in mats.values():
		m.set_shader_parameter(&"affine", 0.75)


func _shader_mat(shader: Shader, tex: Texture2D, color := Color.WHITE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter(&"albedo", color)
	if tex:
		m.set_shader_parameter(&"albedo_texture", tex)
	return m


# ============================================================ mesh helpers

func _st(mat: String) -> SurfaceTool:
	if not _target.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_target[mat] = st
	return _target[mat]


## Vertex colour: baked grime, darker in patches and rotting towards the top of the building.
func _vc(p: Vector3, shade: float) -> Color:
	var g := lerpf(0.6, 1.0, _grime.get_noise_3dv(p * 1.9) * 0.5 + 0.5) * shade
	var rot := smoothstep(9.5, 12.5, p.y) * 0.75
	var c := Color(g, g, g).lerp(Color(g * 0.95, g * 0.6, g * 0.5), rot)
	return Color(c.r * _tint.r, c.g * _tint.g, c.b * _tint.b)


## A four-cornered patch cut into a grid. Front side: p00 bottom-left, p10 bottom-right,
## p01 top-left as you look at it.
func quad4(mat: String, p00: Vector3, p10: Vector3, p01: Vector3, p11: Vector3,
		uv00: Vector2, uv10: Vector2, uv01: Vector2, uv11: Vector2,
		shade := 1.0, nu := 0, nv := 0) -> void:
	if nu <= 0:
		nu = maxi(1, ceili(maxf((p10 - p00).length(), (p11 - p01).length()) / CELL - 0.01))
	if nv <= 0:
		nv = maxi(1, ceili(maxf((p01 - p00).length(), (p11 - p10).length()) / CELL - 0.01))
	var n := (p10 - p00).cross(p01 - p00)
	if n.length() < 0.0001:
		n = (p11 - p01).cross(p01 - p00)
	n = n.normalized()
	var st := _st(mat)
	for j in nv:
		for i in nu:
			var idx := [[i, j], [i, j + 1], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i + 1, j]]
			for c in idx:
				var u: float = float(c[0]) / nu
				var v: float = float(c[1]) / nv
				var p := p00.lerp(p10, u).lerp(p01.lerp(p11, u), v)
				st.set_normal(n)
				st.set_uv(uv00.lerp(uv10, u).lerp(uv01.lerp(uv11, u), v))
				st.set_color(_vc(p, shade))
				st.add_vertex(p)


## A flat rectangle. tile > 0: the texture repeats every `tile` metres, lined up in world space.
## tile <= 0: the texture is stretched over it once.
func face(mat: String, p0: Vector3, du: Vector3, dv: Vector3, tile := 1.0, shade := 1.0) -> void:
	var lu := du.length()
	var lv := dv.length()
	if tile <= 0.0:
		quad4(mat, p0, p0 + du, p0 + dv, p0 + du + dv,
				Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0), shade)
		return
	var o := Vector2(p0.dot(du / lu), -p0.dot(dv / lv)) / tile
	quad4(mat, p0, p0 + du, p0 + dv, p0 + du + dv,
			o, o + Vector2(lu / tile, 0), o + Vector2(0, -lv / tile), o + Vector2(lu / tile, -lv / tile), shade)


func box(mat: String, a: Vector3, b: Vector3, tile := 1.0, shade := 1.0, skip := "") -> void:
	var s := b - a
	if not "e" in skip:
		face(mat, Vector3(b.x, a.y, b.z), Vector3(0, 0, -s.z), Vector3(0, s.y, 0), tile, shade)
	if not "w" in skip:
		face(mat, a, Vector3(0, 0, s.z), Vector3(0, s.y, 0), tile, shade)
	if not "s" in skip:
		face(mat, Vector3(a.x, a.y, b.z), Vector3(s.x, 0, 0), Vector3(0, s.y, 0), tile, shade)
	if not "n" in skip:
		face(mat, Vector3(b.x, a.y, a.z), Vector3(-s.x, 0, 0), Vector3(0, s.y, 0), tile, shade)
	if not "u" in skip:
		face(mat, Vector3(a.x, b.y, b.z), Vector3(s.x, 0, 0), Vector3(0, 0, -s.z), tile, shade)
	if not "d" in skip:
		face(mat, a, Vector3(s.x, 0, 0), Vector3(0, 0, s.z), tile, shade * 0.8)


## An upright wall from a to b (a on the left as you face it), with independent bottom and top
## heights at each end. The texture's V follows `base`, the local floor height, so a painted
## band can run up alongside a flight of stairs.
func wall(mat: String, a: Vector3, b: Vector3, ya0: float, yb0: float, ya1: float, yb1: float,
		base_a := 0.0, base_b := 0.0, tile_v := 3.0, shade := 1.0) -> void:
	a.y = 0.0
	b.y = 0.0
	var length := (b - a).length()
	var cols := maxi(1, ceili(length / CELL - 0.01))
	var off := a.x * 0.37 + a.z * 0.61
	for c in cols:
		var t0 := float(c) / cols
		var t1 := float(c + 1) / cols
		var pa := a.lerp(b, t0)
		var pb := a.lerp(b, t1)
		var y00 := lerpf(ya0, yb0, t0)
		var y10 := lerpf(ya0, yb0, t1)
		var y01 := lerpf(ya1, yb1, t0)
		var y11 := lerpf(ya1, yb1, t1)
		var b0 := lerpf(base_a, base_b, t0)
		var b1 := lerpf(base_a, base_b, t1)
		var u0 := (length * t0 + off) / 1.5
		var u1 := (length * t1 + off) / 1.5
		quad4(mat, pa + Vector3.UP * y00, pb + Vector3.UP * y10, pa + Vector3.UP * y01, pb + Vector3.UP * y11,
				Vector2(u0, -(y00 - b0) / tile_v), Vector2(u1, -(y10 - b1) / tile_v),
				Vector2(u0, -(y01 - b0) / tile_v), Vector2(u1, -(y11 - b1) / tile_v), shade, 1, 0)


## One storey of painted wall standing on a floor line that may slope from base_a to base_b.
func band(a: Vector3, b: Vector3, base_a: float, base_b: float, h0 := 0.0, h1 := 3.0, decals := -1) -> void:
	wall("wall", a, b, base_a + h0, base_b + h0, base_a + h1, base_b + h1, base_a, base_b)
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	if decals < 0:
		decals = int(length * 0.6 + rng.randf()) if h0 <= 0.0 else 0
	var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var n := dir.cross(Vector3.UP)
	for i in decals:
		var s := rng.randf_range(0.35, 0.8)
		if length < s + 0.1:
			continue
		var t := rng.randf_range(s * 0.5 / length, 1.0 - s * 0.5 / length)
		var c := Vector3(lerpf(a.x, b.x, t), lerpf(base_a, base_b, t) + rng.randf_range(0.3, 1.2), lerpf(a.z, b.z, t))
		var p := c - dir * s * 0.5 - Vector3.UP * s * 0.5 + n * 0.012
		var flip := rng.randf() < 0.5
		quad4("peel_a" if rng.randf() < 0.5 else "peel_b", p, p + dir * s, p + Vector3.UP * s, p + dir * s + Vector3.UP * s,
				Vector2(1.0 if flip else 0.0, 1), Vector2(0.0 if flip else 1.0, 1),
				Vector2(1.0 if flip else 0.0, 0), Vector2(0.0 if flip else 1.0, 0), 1.0, 2, 2)


## A sloped or level bar with a rectangular section (handrails).
func beam(mat: String, s: Vector3, e: Vector3, hw: float, h: float) -> void:
	var p := s if s.z > e.z else e
	var q := e if s.z > e.z else s
	var x := Vector3(hw, 0, 0)
	var up := Vector3(0, h, 0)
	var l := (q - p).length()
	quad4(mat, p - x + up, p + x + up, q - x + up, q + x + up,
			Vector2(0, 0), Vector2(0.2, 0), Vector2(0, l), Vector2(0.2, l))
	quad4(mat, q - x, p - x, q - x + up, p - x + up, Vector2(0, 0.2), Vector2(l, 0.2), Vector2(0, 0), Vector2(l, 0), 0.8)
	quad4(mat, p + x, q + x, p + x + up, q + x + up, Vector2(0, 0.2), Vector2(l, 0.2), Vector2(0, 0), Vector2(l, 0), 0.8)


func _commit(d: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for mat: String in d:
		var st: SurfaceTool = d[mat]
		st.index()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[mat])
	return mesh


## Builds a separate little mesh (doors, lamps...) with the same helpers.
func _object(build: Callable, bit: int) -> MeshInstance3D:
	var saved := _target
	_target = {}
	build.call()
	var mi := MeshInstance3D.new()
	mi.mesh = _commit(_target)
	mi.layers = 1 << bit
	_target = saved
	_tint = Color.WHITE
	return mi


func _col(a: Vector3, b: Vector3, parent: Node = null) -> void:
	var shape := BoxShape3D.new()
	shape.size = b - a
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = (a + b) * 0.5
	(parent if parent else body).add_child(cs)


func _touch(title: String, a: Vector3, b: Vector3, message: String) -> void:
	var sb := StaticBody3D.new()
	sb.name = title
	sb.set_meta("message", message)
	world.get_node("Interact").add_child(sb)
	_col(a, b, sb)


func _group(title: String) -> Node3D:
	var n := Node3D.new()
	n.name = title
	world.add_child(n)
	return n


# ============================================================ building

func _build_all() -> void:
	_grime.seed = 7
	_grime.frequency = 1.0
	_make_materials()

	psx = PSXScreen.new()
	psx.name = "PSXScreen"
	psx.lines = 240
	var vp := SubViewport.new()
	vp.name = "SubViewport"
	vp.audio_listener_enable_3d = true
	psx.add_child(vp)
	add_child(psx)
	var dither := ShaderMaterial.new()
	dither.shader = load("res://shaders/psx_dither.gdshader")
	psx.material = dither

	world = Node3D.new()
	world.name = "World"
	vp.add_child(world)
	body = StaticBody3D.new()
	body.name = "Collision"
	world.add_child(body)
	for g in ["Level", "Interact", "Doors", "Lamps", "Props", "Graffiti"]:
		_group(g)

	for k in FLOORS:
		_landing(k)
	for k in range(-1, FLOORS - 1):
		_stairs(k)
	_top()
	_collision()
	_graffiti_all()

	# Turn the batches into one mesh per zone.
	var bits := _zones.keys()
	bits.sort()
	for bit: int in bits:
		var mi := MeshInstance3D.new()
		mi.name = _zone_names[bit]
		mi.mesh = _commit(_zones[bit])
		mi.layers = 1 << bit
		world.get_node("Level").add_child(mi)

	_build_environment()
	_build_player()
	_build_ui()
	var drone := AudioStreamPlayer.new()
	drone.name = "Drone"
	drone.stream = _loop(AUDIO + "drone.wav")
	drone.volume_db = -10.0
	drone.autoplay = true
	add_child(drone)


func _landing(k: int) -> void:
	_zone(_zl(k), "Floor%d" % (k + 1))
	var y := k * STOREY
	var cy := y + 2.8 if k < FLOORS - 1 else TOP
	face("tile", Vector3(-LX, y, 0), Vector3(LX * 2, 0, 0), Vector3(0, 0, LZ), 0.6)
	face("plaster", Vector3(-LX, cy, LZ), Vector3(LX * 2, 0, 0), Vector3(0, 0, -LZ), 1.5, 0.9)
	var h := cy - y
	if k == FLOORS - 1:
		# Flat 17's doorway: the flat itself is a separate scene behind this wall.
		band(Vector3(-LX, 0, LZ), Vector3(-1.95, 0, LZ), y, y, 0.0, h)
		band(Vector3(-1.95, 0, LZ), Vector3(-1.05, 0, LZ), y, y, 2.05, h)
		band(Vector3(-1.05, 0, LZ), Vector3(LX, 0, LZ), y, y, 0.0, h)
	else:
		band(Vector3(-LX, 0, LZ), Vector3(LX, 0, LZ), y, y, 0.0, h)
	band(Vector3(-LX, 0, 0), Vector3(-LX, 0, LZ), y, y, 0.0, h)
	band(Vector3(LX, 0, LZ), Vector3(LX, 0, 0), y, y, 0.0, h)
	band(Vector3(LX, 0, 0), Vector3(HX, 0, 0), y, y, 0.0, h)
	band(Vector3(-HX, 0, 0), Vector3(-LX, 0, 0), y, y, 0.0, h)

	# Electrical panel between the two back doors.
	box("metal_grey", Vector3(-0.32, y + 1.15, LZ), Vector3(0.32, y + 1.85, LZ + 0.13), 0.6, 0.8, "n")
	face("panel", Vector3(-0.32, y + 1.15, LZ + 0.135), Vector3(0.64, 0, 0), Vector3(0, 0.7, 0), 0.0)
	_touch("Panel%d" % (k + 1), Vector3(-0.32, y + 1.15, LZ), Vector3(0.32, y + 1.85, LZ + 0.14), "Щиток. Гудит.")

	# Four apartments per floor.
	var tints := [Color(0.3, 0.18, 0.12), Color(0.14, 0.13, 0.13), Color(0.32, 0.1, 0.09), Color(0.13, 0.2, 0.15),
			Color(0.22, 0.2, 0.3)]
	var msgs := ["Заперто.", "Никто не открывает.", "За дверью тихо.", "Заперто.", "Глазок закрыт изнутри.",
			"За дверью кто-то дышит.", "Заперто."]
	var spots := [[Vector3(-1.5, y, LZ), 0.0], [Vector3(1.5, y, LZ), 0.0],
			[Vector3(-LX, y, -1.3), PI * 0.5], [Vector3(LX, y, -1.3), -PI * 0.5]]
	for i in 4:
		var num := k * 4 + i + 1
		var ajar := k == FLOORS - 1 and i == 0
		var msg: String = "Там темно. Что-то работает. Телевизор?" if ajar else msgs[rng.randi() % msgs.size()]
		var tint: Color = tints[rng.randi() % tints.size()]
		if ajar:
			_flat17(spots[i][0])
		else:
			_door(spots[i][0], spots[i][1], str(num), tint, msg, ajar)
		if i < 2 and rng.randf() < 0.6 and not ajar:
			var px: float = spots[i][0].x
			face("doormat", Vector3(px - 0.3, y + 0.012, LZ + 0.6), Vector3(0.6, 0, 0), Vector3(0, 0, -0.4), 0.0)

	# Ceiling lamp. Floor 4 is dead, floor 5 is sick.
	var setup := [[2.2, false, "bulb"], [1.9, true, "bulb"], [2.0, false, "bulb"], [0.0, false, "bulb"],
			[1.1, true, "bulb_sick"]]
	var mask := 1 << _zl(k) | 1 << _zb(k - 1)
	if k < FLOORS - 1:
		mask |= 1 << _za(k)
	var color := Color(1.0, 0.72, 0.38) if k < FLOORS - 1 else Color(0.6, 0.85, 0.45)
	_lamp("Lamp%d" % (k + 1), Vector3(0, cy, -1.3), mask, setup[k][0], color, setup[k][1], setup[k][2])
	_papers(Vector3(0, y, -1.3), Vector2(2.2, 1.0), 3 + rng.randi() % 5)

	if k == FLOORS - 1:
		_fifth_floor(y)


func _stairs(k: int) -> void:
	var yf := k * STOREY           # floor below
	var yh := yf + 1.5             # this half-landing
	var title := "Entry" if k < 0 else "StairsA%d" % (k + 1)
	_zone(_za(k), title)
	if k >= 0:
		_flight(yf, 1, true)
		band(Vector3(HX, 0, 0), Vector3(HX, 0, RUN), yf, yh)
	else:
		# Solid ground under the first flight; the entry hall is half a storey down.
		band(Vector3(-GAP, 0, RUN), Vector3(HX, 0, RUN), -1.5, -1.5, 0.0, 1.5)
		face("concrete", Vector3(-GAP, 0, RUN), Vector3(HX + GAP, 0, 0), Vector3(0, 0, -RUN), 0.8, 0.7)
		wall("plaster", Vector3(HX, 0, 0), Vector3(HX, 0, RUN), 0, 0, 0, 1.5 - 0.16, 0, 0, 1.5, 0.6)
	# Half-landing: floor, walls, the ceiling over it.
	face("tile", Vector3(-HX, yh, Z_END), Vector3(HX * 2, 0, 0), Vector3(0, 0, RUN - Z_END), 0.6)
	face("concrete", Vector3(HX, yh - 0.2, RUN), Vector3(-HX * 2, 0, 0), Vector3(0, 0.2, 0), 0.8, 0.8)
	band(Vector3(HX, 0, RUN), Vector3(HX, 0, Z_END), yh, yh)
	band(Vector3(-HX, 0, Z_END), Vector3(-HX, 0, RUN), yh, yh)
	if k < FLOORS - 2:
		face("plaster", Vector3(-HX, yh + 2.8, RUN), Vector3(HX * 2, 0, 0), Vector3(0, 0, Z_END - RUN), 1.5, 0.9)
	if k >= 0:
		_window(yh)
		_radiator(yh)
		_light("Window%d" % (k + 1), Vector3(0, yh + 1.5, 3.4), 1 << _za(k) | 1 << _zb(k),
				1.3, Color(0.45, 0.6, 0.9), 5.0)
	else:
		_entrance(yh)
	_chute(yh, yh + 3.0 if k < FLOORS - 2 else TOP)
	_papers(Vector3(0, yh, (RUN + Z_END) * 0.5), Vector2(1.1, 0.6), 2 + rng.randi() % 6)

	_zone(_zb(k), "StairsB%d" % (k + 2))
	_flight(yh, -1, k >= 0)
	band(Vector3(-HX, 0, RUN), Vector3(-HX, 0, 0), yh, yh + 1.5)
	face("concrete", Vector3(-HX, yh + 1.3, 0), Vector3(HX * 2, 0, 0), Vector3(0, 0.2, 0), 0.8, 0.8)
	if k < 0:
		# Side of the solid block, facing the entry flight.
		wall("wall", Vector3(-GAP, 0, 0), Vector3(-GAP, 0, RUN), 0, -1.5, 0, 0, 0, -1.5)
	else:
		# Short rails across the well at both ends.
		_cross_rail(yh, RUN - 0.02)
		if k < FLOORS - 2:
			_cross_rail(yh + 1.5, 0.02)


func _cross_rail(y: float, z: float) -> void:
	quad4("rail", Vector3(-GAP, y, z), Vector3(GAP, y, z), Vector3(-GAP, y + 0.9, z), Vector3(GAP, y + 0.9, z),
			Vector2(0, 1), Vector2(0.62, 1), Vector2(0, 0), Vector2(0.62, 0), 1.0, 1, 1)
	box("wood", Vector3(-GAP - 0.04, y + 0.9, z - 0.03), Vector3(GAP + 0.04, y + 0.94, z + 0.03), 0.5)


## One flight of nine steps. d = 1 climbs towards +Z on the right, d = -1 back towards -Z on the left.
func _flight(y0: float, d: int, well: bool) -> void:
	var x0 := GAP if d > 0 else -HX
	var x1 := HX if d > 0 else -GAP
	var zs := 0.0 if d > 0 else RUN
	var ze := zs + d * RUN
	var w := x1 - x0
	for i in STEPS:
		var z := zs + d * i * TREAD
		var y := y0 + i * RISE
		if d > 0:
			face("concrete", Vector3(x1, y, z), Vector3(-w, 0, 0), Vector3(0, RISE, 0), 0.8, 0.7)
		else:
			face("concrete", Vector3(x0, y, z), Vector3(w, 0, 0), Vector3(0, RISE, 0), 0.8, 0.7)
		face("concrete", Vector3(x0, y + RISE, maxf(z, z + d * TREAD)), Vector3(w, 0, 0), Vector3(0, 0, -TREAD), 0.8)
	# Underside.
	var lo := y0 - 0.16
	var hi := y0 + 1.5 - 0.16
	var sl := sqrt(RUN * RUN + 1.5 * 1.5)
	if d > 0:
		quad4("plaster", Vector3(x0, lo, zs), Vector3(x1, lo, zs), Vector3(x0, hi, ze), Vector3(x1, hi, ze),
				Vector2(0, 0), Vector2(w / 1.5, 0), Vector2(0, sl / 1.5), Vector2(w / 1.5, sl / 1.5), 0.8)
	else:
		quad4("plaster", Vector3(x1, lo, zs), Vector3(x0, lo, zs), Vector3(x1, hi, ze), Vector3(x0, hi, ze),
				Vector2(0, 0), Vector2(w / 1.5, 0), Vector2(0, sl / 1.5), Vector2(w / 1.5, sl / 1.5), 0.8)
	var xin := x0 if d > 0 else x1
	if well:
		# Steel stringer on the well side, the railing and its wooden handrail.
		wall("metal_teal", Vector3(xin, 0, zs), Vector3(xin, 0, ze), lo, hi, y0 + RISE + 0.03, y0 + 1.5 + RISE + 0.03,
				0, 0, 0.8, 0.7)
		var xr := xin + d * 0.04
		var b0 := y0 + RISE * 0.5
		quad4("rail", Vector3(xr, b0, zs), Vector3(xr, b0 + 1.5, ze), Vector3(xr, b0 + 0.9, zs), Vector3(xr, b0 + 2.4, ze),
				Vector2(0, 1), Vector2(sl / 0.48, 1), Vector2(0, 0), Vector2(sl / 0.48, 0), 1.0, 6, 1)
		beam("wood", Vector3(xr, b0 + 0.9, zs), Vector3(xr, b0 + 2.4, ze), 0.03, 0.04)

	# Collision: a smooth ramp, shifted half a tread so feet sit on the steps.
	var theta := atan2(1.5, RUN)
	var shape := BoxShape3D.new()
	shape.size = Vector3(w, 0.2, sl)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var n := Vector3(0, cos(theta), -d * sin(theta))
	cs.position = Vector3((x0 + x1) * 0.5, y0 + 0.75, RUN * 0.5 - d * TREAD * 0.5) - n * 0.1
	cs.rotation.x = -d * theta
	body.add_child(cs)
	var tz := ze - d * TREAD * 0.25
	_col(Vector3(x0, y0 + 1.3, tz - TREAD * 0.25), Vector3(x1, y0 + 1.5, tz + TREAD * 0.25))


func _window(yh: float) -> void:
	var y0 := yh + 0.9
	var y1 := yh + 2.1
	band(Vector3(HX, 0, Z_END), Vector3(0.55, 0, Z_END), yh, yh)
	band(Vector3(0.55, 0, Z_END), Vector3(-0.55, 0, Z_END), yh, yh, 0.0, 0.9, 0)
	band(Vector3(0.55, 0, Z_END), Vector3(-0.55, 0, Z_END), yh, yh, 2.1, 3.0)
	band(Vector3(-0.55, 0, Z_END), Vector3(-HX, 0, Z_END), yh, yh)
	var zg := Z_END + 0.14
	face("window", Vector3(0.55, y0, zg), Vector3(-1.1, 0, 0), Vector3(0, 1.2, 0), 0.0)
	# Reveal.
	face("plaster", Vector3(-0.55, y0, zg), Vector3(1.1, 0, 0), Vector3(0, 0, -0.14), 1.5, 0.8)
	face("plaster", Vector3(-0.55, y1, Z_END), Vector3(1.1, 0, 0), Vector3(0, 0, 0.14), 1.5, 0.6)
	face("plaster", Vector3(0.55, y0, Z_END), Vector3(0, 0, 0.14), Vector3(0, 1.2, 0), 1.5, 0.7)
	face("plaster", Vector3(-0.55, y0, zg), Vector3(0, 0, -0.14), Vector3(0, 1.2, 0), 1.5, 0.7)
	# Frame and sill.
	for x in [-0.55, -0.025, 0.5]:
		box("wood", Vector3(x, y0, zg - 0.06), Vector3(x + 0.05, y1, zg - 0.01), 0.4, 1.0, "s")
	for y in [y0, y0 + 0.78, y1 - 0.05]:
		box("wood", Vector3(-0.55, y, zg - 0.06), Vector3(0.55, y + 0.05, zg - 0.01), 0.4, 1.0, "s")
	box("wood", Vector3(-0.65, y0 - 0.04, Z_END - 0.13), Vector3(0.65, y0, Z_END + 0.02), 0.4)


func _radiator(yh: float) -> void:
	for i in 8:
		var x := -0.36 + i * 0.09
		box("metal_teal", Vector3(x, yh + 0.18, Z_END - 0.15), Vector3(x + 0.07, yh + 0.74, Z_END - 0.03), 0.5, 0.9, "s")
	box("metal_teal", Vector3(0.36, yh + 0.2, Z_END - 0.1), Vector3(0.4, yh + 3.0, Z_END - 0.06), 0.5, 0.8)
	_col(Vector3(-0.38, yh, Z_END - 0.16), Vector3(0.38, yh + 0.76, Z_END))


## The garbage chute: a fat pipe in the corner with a hatch on every half-landing.
func _chute(y0: float, y1: float) -> void:
	var c := Vector3(1.08, 0, 3.72)
	for i in 8:
		var a0 := TAU * (i + 1) / 8.0
		var a1 := TAU * i / 8.0
		wall("metal_grey", c + Vector3(cos(a0), 0, sin(a0)) * 0.21, c + Vector3(cos(a1), 0, sin(a1)) * 0.21,
				y0, y0, y1, y1, 0, 0, 1.5, 0.85)
	box("metal_teal", Vector3(0.93, y0 + 0.75, 3.44), Vector3(1.23, y0 + 1.1, 3.56), 0.5)
	_touch("Chute%d" % int(y0 + 2.0), Vector3(0.85, y0, 3.44), Vector3(1.3, y0 + 2.0, 3.95), "Мусоропровод. Изнутри тянет холодом.")
	_col(Vector3(0.87, y0, 3.5), Vector3(1.3, y1, 3.95))


func _entrance(yh: float) -> void:
	band(Vector3(HX, 0, Z_END), Vector3(-HX, 0, Z_END), yh, yh)
	var z := Z_END - 0.05
	box("metal_grey", Vector3(-0.75, yh, z - 0.03), Vector3(-0.67, yh + 2.2, Z_END), 0.5, 0.7)
	box("metal_grey", Vector3(0.67, yh, z - 0.03), Vector3(0.75, yh + 2.2, Z_END), 0.5, 0.7)
	box("metal_grey", Vector3(-0.75, yh + 2.12, z - 0.03), Vector3(0.75, yh + 2.2, Z_END), 0.5, 0.7)
	quad4("door_metal", Vector3(0.67, yh, z), Vector3(0, yh, z), Vector3(0.67, yh + 2.12, z), Vector3(0, yh + 2.12, z),
			Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0))
	quad4("door_metal", Vector3(0, yh, z), Vector3(-0.67, yh, z), Vector3(0, yh + 2.12, z), Vector3(-0.67, yh + 2.12, z),
			Vector2(1, 1), Vector2(0, 1), Vector2(1, 0), Vector2(0, 0))
	_touch("EntranceDoor", Vector3(-0.75, yh, z - 0.06), Vector3(0.75, yh + 2.2, Z_END), "Дверь подъезда заперта снаружи.")

	# Mailboxes on the left wall.
	var x := -HX + 0.12
	box("metal_teal", Vector3(-HX, yh + 0.95, 2.7), Vector3(x, yh + 1.55, 3.8), 0.5, 0.8, "we")
	quad4("mailbox", Vector3(x + 0.005, yh + 0.95, 3.8), Vector3(x + 0.005, yh + 0.95, 2.7),
			Vector3(x + 0.005, yh + 1.55, 3.8), Vector3(x + 0.005, yh + 1.55, 2.7),
			Vector2(0, 2), Vector2(5, 2), Vector2(0, 0), Vector2(5, 0))
	_touch("Mailboxes", Vector3(-HX, yh + 0.95, 2.7), Vector3(x + 0.02, yh + 1.55, 3.8), "Почтовые ящики. Пусто.")

	_lamp("LampEntry", Vector3(0, yh + 2.8, 3.2), 1 << _za(-1) | 1 << _zb(-1), 1.7, Color(1.0, 0.7, 0.36), true, "bulb")
	_prop("trashbag/trashbag.gltf", Vector3(0.95, yh, 2.95), 0.4)
	_prop("trashbag/trashbag.gltf", Vector3(0.55, yh, 3.55), 2.3, 0.85)
	_prop("wine_bottles_01/wine_bottles_01.gltf", Vector3(-1.0, yh, 2.75), 0.7)
	_col(Vector3(0.35, yh, 2.65), Vector3(1.3, yh + 0.6, 3.5))


func _top() -> void:
	_zone(_zb(FLOORS - 2), "StairsB%d" % FLOORS)
	var y := (FLOORS - 1) * STOREY
	# Bare whitewash above the last painted band, up to the roof slab.
	wall("plaster", Vector3(HX, 0, 0), Vector3(HX, 0, RUN), y, y + 1.5, TOP, TOP, 0, 0, 1.5)
	wall("plaster", Vector3(HX, 0, RUN), Vector3(HX, 0, Z_END), y + 1.5, y + 1.5, TOP, TOP, 0, 0, 1.5)
	wall("plaster", Vector3(HX, 0, Z_END), Vector3(-HX, 0, Z_END), y + 1.5, y + 1.5, TOP, TOP, 0, 0, 1.5)
	wall("plaster", Vector3(-HX, 0, Z_END), Vector3(-HX, 0, RUN), y + 1.5, y + 1.5, TOP, TOP, 0, 0, 1.5)
	wall("plaster", Vector3(-HX, 0, RUN), Vector3(-HX, 0, 0), y + 1.5, TOP, TOP, TOP, 0, 0, 1.5)
	face("plaster", Vector3(-HX, TOP, 0), Vector3(HX * 2, 0, 0), Vector3(0, 0, Z_END), 1.5, 0.8)
	# Guard rail where the fifth-floor landing looks down the shaft.
	_zone(_zl(FLOORS - 1), "Floor%d" % FLOORS)
	var l := HX + GAP
	quad4("rail", Vector3(-GAP, y, 0.03), Vector3(HX, y, 0.03), Vector3(-GAP, y + 0.9, 0.03), Vector3(HX, y + 0.9, 0.03),
			Vector2(0, 1), Vector2(l / 0.48, 1), Vector2(0, 0), Vector2(l / 0.48, 0), 1.0, 3, 1)
	box("wood", Vector3(-GAP, y + 0.9, 0.0), Vector3(HX, y + 0.94, 0.06), 0.5)


func _fifth_floor(y: float) -> void:
	# Ladder to the attic hatch.
	for x in [1.9, 2.3]:
		box("metal_grey", Vector3(x, y, LZ + 0.1), Vector3(x + 0.04, TOP, LZ + 0.14), 0.5, 0.8)
	for i in 8:
		box("metal_grey", Vector3(1.9, y + 0.3 + i * 0.32, LZ + 0.1), Vector3(2.34, y + 0.33 + i * 0.32, LZ + 0.14), 0.5)
	face("door_metal", Vector3(1.7, TOP - 0.01, LZ + 0.05), Vector3(0.85, 0, 0), Vector3(0, 0, 0.85), 0.0, 0.7)
	_touch("AtticLadder", Vector3(1.85, y, LZ), Vector3(2.4, TOP, LZ + 0.2), "Люк на чердак. На нём замок.")
	_col(Vector3(1.85, y, LZ), Vector3(2.4, TOP, LZ + 0.18))
	# Something was dragged across the floor to the open door.
	for s in [[Vector3(-1.5, y + 0.014, -1.9), 1.1, 0.3], [Vector3(-1.0, y + 0.015, -1.2), 0.9, 1.1],
			[Vector3(-0.5, y + 0.016, -0.5), 0.7, 2.0]]:
		var du: Vector3 = Vector3(cos(s[2]), 0, sin(s[2])) * s[1]
		var dv: Vector3 = Vector3(sin(s[2]), 0, -cos(s[2])) * s[1]
		var p: Vector3 = s[0] - du * 0.5 - dv * 0.5
		quad4("stain", p, p + du, p + dv, p + du + dv, Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0), 1.0, 2, 2)
	var p2 := Vector3(-2.3, y + 0.2, LZ + 0.013)
	quad4("stain", p2, p2 + Vector3(0.9, 0, 0), p2 + Vector3(0, 0.9, 0), p2 + Vector3(0.9, 0.9, 0),
			Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0), 1.0, 2, 2)

	# Cold television light leaking out of the open flat.

	# And the tenant.
	var fig := _object(func() -> void:
		face("figure", Vector3(-0.4, 0, 0), Vector3(0.8, 0, 0), Vector3(0, 2.35, 0), 0.0), _zl(FLOORS - 1))
	fig.name = "Figure"
	fig.position = Vector3(1.75, y, -2.05)
	fig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(fig)


## Flat 17, the two-room flat behind the open door on the fifth floor (apartment/apartment_17.tscn,
## built by tools/build_apartment.gd). Its origin is the middle of its doorway in this wall.
func _flat17(at: Vector3) -> void:
	var flat: Node3D = (load("res://apartment/apartment_17.tscn") as PackedScene).instantiate()
	flat.name = "Flat17"
	flat.position = at
	world.add_child(flat)


func _door(pos: Vector3, rot_y: float, number: String, tint: Color, message: String, ajar: bool) -> void:
	var sb := StaticBody3D.new()
	sb.name = "Door_" + number
	sb.position = pos
	sb.rotation.y = rot_y
	sb.set_meta("message", message)
	world.get_node("Doors").add_child(sb)
	var bit := _bit
	var frame := _object(func() -> void:
		box("wood", Vector3(-0.53, 0, 0), Vector3(-0.45, 2.13, 0.07), 0.5, 0.8, "n")
		box("wood", Vector3(0.45, 0, 0), Vector3(0.53, 2.13, 0.07), 0.5, 0.8, "n")
		box("wood", Vector3(-0.45, 2.05, 0), Vector3(0.45, 2.13, 0.07), 0.5, 0.8, "n")
		if ajar:
			face("black", Vector3(-0.45, 0, 0.02), Vector3(0.9, 0, 0), Vector3(0, 2.05, 0), 0.0)
		else:
			_tint = tint * 2.1
			face("door", Vector3(-0.45, 0, 0.045), Vector3(0.9, 0, 0), Vector3(0, 2.05, 0), 0.0), bit)
	frame.name = "Mesh"
	sb.add_child(frame)
	if ajar:
		var leaf := _object(func() -> void:
			_tint = tint * 2.1
			face("door", Vector3(0, 0, 0), Vector3(0.9, 0, 0), Vector3(0, 2.05, 0), 0.0)
			face("door", Vector3(0.9, 0, -0.04), Vector3(-0.9, 0, 0), Vector3(0, 2.05, 0), 0.0), bit)
		leaf.name = "Leaf"
		leaf.position = Vector3(-0.45, 0, 0.06)
		leaf.rotation.y = -0.42
		sb.add_child(leaf)
	_col(Vector3(-0.53, 0, 0), Vector3(0.53, 2.13, 0.08), sb)
	var l := Label3D.new()
	l.name = "Number"
	l.text = number
	l.font_size = 36
	l.pixel_size = 0.0025
	l.modulate = Color(0.8, 0.72, 0.5)
	l.outline_size = 0
	l.shaded = true
	l.layers = 1 << bit
	l.position = Vector3(0, 1.78, 0.055)
	l.visible = not ajar
	sb.add_child(l)


func _light(title: String, pos: Vector3, mask: int, energy: float, color: Color, reach: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = title
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.2
	l.light_cull_mask = mask
	l.set_meta("base", energy)
	world.get_node("Lamps").add_child(l)
	return l


## A bare bulb on a wire. energy 0 = burnt out.
func _lamp(title: String, ceiling: Vector3, mask: int, energy: float, color: Color, flicker: bool, bulb: String) -> void:
	var l := _light(title, ceiling + Vector3(0, -0.42, 0), mask, energy, color, 6.5)
	l.add_to_group("lamp", true)
	var bit := _bit
	var fix := _object(func() -> void:
		box("black", Vector3(-0.006, 0.08, -0.006), Vector3(0.006, 0.42, 0.006), 1.0)
		box("metal_grey", Vector3(-0.025, 0.03, -0.025), Vector3(0.025, 0.09, 0.025), 0.3, 0.6), bit)
	fix.name = "Fixture"
	l.add_child(fix)
	var glass := _object(func() -> void:
		box(bulb if energy > 0.0 else "metal_grey", Vector3(-0.035, -0.05, -0.035), Vector3(0.035, 0.035, 0.035), 0.3), bit)
	glass.name = "Bulb"
	l.add_child(glass)
	if energy > 0.0:
		var hum := AudioStreamPlayer3D.new()
		hum.name = "Hum"
		hum.stream = _loop(AUDIO + "hum.wav")
		hum.volume_db = -20.0
		hum.unit_size = 1.5
		hum.max_distance = 9.0
		hum.autoplay = true
		l.add_child(hum)
	if flicker:
		l.add_to_group("flicker", true)


func _prop(path: String, pos: Vector3, rot_y := 0.0, size := 1.0) -> void:
	var scene: PackedScene = load(MODELS + path)
	if scene == null:
		return
	var n: Node3D = scene.instantiate()
	n.position = pos
	n.rotation.y = rot_y
	n.scale = Vector3.ONE * size
	world.get_node("Props").add_child(n)
	n.add_to_group("psx_prop", true)
	n.set_meta("layer", 1 << _bit)


func _papers(c: Vector3, spread: Vector2, count: int) -> void:
	for i in count:
		var p := c + Vector3(rng.randf_range(-spread.x, spread.x), 0.011 + i * 0.001, rng.randf_range(-spread.y, spread.y))
		var a := rng.randf() * TAU
		var du := Vector3(cos(a), 0, sin(a)) * 0.21
		var dv := Vector3(sin(a), 0, -cos(a)) * 0.29
		quad4("paper_a" if rng.randf() < 0.5 else "paper_b", p, p + du, p + dv, p + du + dv,
				Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0), 1.0, 1, 1)


func _collision() -> void:
	var lo := -2.0
	# Back wall of the landings, as thick as the flats' front walls, with flat 17's doorway.
	var y5 := (FLOORS - 1) * STOREY
	_col(Vector3(-LX - 0.3, lo, LZ - 0.2), Vector3(-1.95, TOP, LZ))
	_col(Vector3(-1.05, lo, LZ - 0.2), Vector3(LX + 0.3, TOP, LZ))
	_col(Vector3(-1.95, lo, LZ - 0.2), Vector3(-1.05, y5, LZ))
	_col(Vector3(-1.95, y5 + 2.05, LZ - 0.2), Vector3(-1.05, TOP, LZ))
	_col(Vector3(-LX - 0.3, lo, LZ), Vector3(-LX, TOP, 0.3))
	_col(Vector3(LX, lo, LZ), Vector3(LX + 0.3, TOP, 0.3))
	_col(Vector3(HX, lo, 0), Vector3(LX + 0.3, TOP, 0.3))
	_col(Vector3(-LX - 0.3, lo, 0), Vector3(-HX, TOP, 0.3))
	_col(Vector3(HX, lo, 0), Vector3(HX + 0.3, TOP, Z_END))
	_col(Vector3(-HX - 0.3, lo, 0), Vector3(-HX, TOP, Z_END))
	_col(Vector3(-HX - 0.3, lo, Z_END), Vector3(HX + 0.3, TOP, Z_END + 0.3))
	_col(Vector3(-LX, TOP, LZ), Vector3(LX, TOP + 0.3, Z_END))
	for k in FLOORS:
		_col(Vector3(-LX, k * STOREY - (0.2 if k > 0 else 2.0), LZ), Vector3(LX, k * STOREY, 0))
	for k in range(-1, FLOORS - 1):
		var yh := k * STOREY + 1.5
		_col(Vector3(-HX, yh - (0.2 if k >= 0 else 0.5), RUN), Vector3(HX, yh, Z_END))
	_col(Vector3(-GAP, -1.5, 0), Vector3(HX, 0, RUN))
	# Invisible barrier in the well, and the guard on the top landing.
	_col(Vector3(-0.04, 0, 0), Vector3(0.04, TOP, RUN))
	_col(Vector3(-GAP, (FLOORS - 1) * STOREY, 0.0), Vector3(HX, (FLOORS - 1) * STOREY + 1.0, 0.06))


# ============================================================ graffiti
# Each piece is a spray-paint texture painted by tools/make_graffiti.py and projected onto the
# wall with a Decal, so it takes the wall's relief, lighting and the flashlight like the paint
# around it. Placement comes from assets/graffiti/graffiti.json, written by the same tool.

const GRAFFITI := "res://assets/graffiti/"


func _wall_xform(w: String, along: float, y: float) -> Array:
	# Returns the point on the wall surface and the wall's outward normal.
	match w:
		"B": return [Vector3(along, y, LZ), Vector3(0, 0, 1)]          # back wall of a landing
		"F": return [Vector3(along, y, 0.0), Vector3(0, 0, -1)]        # beside the stairs opening
		"R": return [Vector3(HX, y, along), Vector3(-1, 0, 0)]         # shaft wall, right flight
		"L": return [Vector3(-HX, y, along), Vector3(1, 0, 0)]         # shaft wall, left flight
		"K": return [Vector3(along, y, RUN), Vector3(0, 0, 1)]         # block facing the entry hall
		_: return [Vector3(along, y, Z_END), Vector3(0, 0, -1)]        # window wall


func _graffiti_all() -> void:
	var list: Array = JSON.parse_string(FileAccess.get_file_as_string(GRAFFITI + "graffiti.json"))
	for g: Dictionary in list:
		var zone: Array = g["zone"]
		var k := int(zone[1])
		var bit := _zl(k) if zone[0] == "l" else (_za(k) if zone[0] == "a" else _zb(k))
		var x := _wall_xform(g["wall"], g["along"], g["y"])
		var n: Vector3 = x[1]
		# Right as seen by someone facing the wall; the decal paints its XZ plane along -Y.
		var right := (-n).cross(Vector3.UP)
		var d := Decal.new()
		d.name = String(g["name"])
		d.texture_albedo = load(GRAFFITI + g["name"] + ".png")
		d.size = Vector3(g["w"], 0.3, g["h"])
		d.basis = Basis(right, n, right.cross(n))
		d.position = x[0] + right * float(g["cx"]) + Vector3.UP * float(g["cy"])
		d.cull_mask = 1 << bit
		d.normal_fade = 0.5
		d.upper_fade = 0.05
		d.lower_fade = 0.05
		d.distance_fade_enabled = false
		world.get_node("Graffiti").add_child(d)


## Replaces only the graffiti in main.tscn and saves it, leaving everything else as it is.
func _regraffiti() -> void:
	world = $PSXScreen/SubViewport/World
	player = world.get_node("Player")
	var holder := world.get_node("Graffiti")
	for c in holder.get_children():
		holder.remove_child(c)
		c.free()
	_graffiti_all()
	_bake()


# ============================================================ world, player, UI

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.5, 0.48)
	env.ambient_light_energy = 0.07
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# The PS1's draw-distance haze, here pure darkness.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.0, 0.004, 0.004)
	env.fog_density = 1.0
	env.fog_depth_begin = 1.5
	env.fog_depth_end = 15.0
	env.fog_depth_curve = 1.4
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	world.add_child(we)


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.set_script(load("res://player.gd"))
	player.position = Vector3(0.0, -1.45, 3.35)
	world.add_child(player)


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 2
	add_child(ui)
	var dot := ColorRect.new()
	dot.name = "Crosshair"
	dot.color = Color(1, 1, 1, 0.3)
	dot.size = Vector2(3, 3)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(dot)
	var hint := Label.new()
	hint.name = "Hint"
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_bottom = -40
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.78))
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 6)
	ui.add_child(hint)


# ============================================================ runtime

func _loop(path: String) -> AudioStream:
	var st: AudioStreamWAV = load(path)
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = int(st.get_length() * st.mix_rate)
	return st


func _set_layers(n: Node, layers: int) -> void:
	if n is VisualInstance3D:
		n.layers = layers
	for c in n.get_children():
		_set_layers(c, layers)


func _runtime_init() -> void:
	psx = $PSXScreen
	world = $PSXScreen/SubViewport/World
	player = world.get_node("Player")
	player.hint = $UI/Hint
	player._show_hint("WASD — идти   Shift — бег   F — фонарик   E — осмотреть")
	player._hint_time = 6.0
	_loop(AUDIO + "drone.wav")
	_loop(AUDIO + "hum.wav")
	$Drone.volume_db = -17.0
	for l in get_tree().get_nodes_in_group("lamp"):
		if l.has_node("Hum"):
			l.get_node("Hum").volume_db = HUM_DB
	if not has_node("City"):
		var city := AudioStreamPlayer.new()
		city.name = "City"
		var night: AudioStreamMP3 = load(AUDIO + "city_night.mp3")
		night.loop = true
		city.stream = night
		city.bus = "Outside"
		city.volume_db = 0.0
		add_child(city)
		city.play()
	# Recordings only. Knocks are the most common.
	for n in ["knock_1.mp3", "knock_2.mp3", "knock_3.mp3", "door_slam_metal.mp3", "door_creak_long.mp3",
			"knock_1.mp3", "knock_3.mp3"]:
		event_sounds.append(load(AUDIO + n))
	for i in 6:
		_steps_far.append(load(AUDIO + "foley/footstep%02d.ogg" % i))
	# Imported models get PSX Look materials and their zone's render layer.
	for p in get_tree().get_nodes_in_group("psx_prop"):
		PSX.convert(p)
		_set_layers(p, p.get_meta("layer"))


## Someone walking somewhere else in the building: a few real footsteps, moving as they go.
func _walk_far(start: Vector3, dir: Vector3, count: int, db: float) -> void:
	for i in count:
		_play_at(_steps_far[(i + rng.randi() % 3) % _steps_far.size()], start + dir * (0.6 * i), db,
				rng.randf_range(0.82, 0.95))
		await get_tree().create_timer(rng.randf_range(0.55, 0.68)).timeout


func _play_at(stream: AudioStream, pos: Vector3, db: float, pitch := 1.0, bus := "Muffled") -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = bus
	p.position = pos
	p.unit_size = 5.0
	p.max_distance = 45.0
	p.volume_db = db
	p.pitch_scale = pitch
	world.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _process(delta: float) -> void:
	if world == null or player == null:
		return
	var blackout := _scare == 1
	# Failing bulbs.
	for l: OmniLight3D in get_tree().get_nodes_in_group("flicker"):
		var s: Array = _flick.get(l, [0.0, true])
		s[0] -= delta
		if s[0] <= 0.0:
			s[1] = not s[1] if rng.randf() < 0.6 else true
			s[0] = rng.randf_range(0.03, 0.16) if not s[1] else rng.randf_range(0.05, 1.8)
		_flick[l] = s
		var base: float = l.get_meta("base")
		var on: bool = s[1] and not blackout and base > 0.0
		l.light_energy = base * rng.randf_range(0.85, 1.0) if on else 0.0
		l.get_node("Bulb").visible = on
		if l.has_node("Hum"):
			l.get_node("Hum").volume_db = HUM_DB + 3.0 if on else -60.0
	for l: OmniLight3D in get_tree().get_nodes_in_group("tv"):
		var base: float = l.get_meta("base")
		l.light_energy = base * (0.45 + 0.55 * rng.randf()) if rng.randf() < 0.9 else 0.1

	var fig: Node3D = world.get_node_or_null("Figure")
	if fig and fig.visible:
		var d := player.global_position - fig.global_position
		fig.rotation.y = atan2(d.x, d.z)

	# Halfway up: someone walks across the floor above.
	if not _teased and player.position.y > 7.3:
		_teased = true
		_walk_far(Vector3(-1.2, 12.2, -1.8), Vector3(1, 0, 0.2).normalized(), 6, 4.0)

	# The fifth floor.
	if _scare == 0 and player.position.y > 11.7 and player.position.z < -0.15:
		_scare = 1
		_scare_t = 0.0
		# The attic hatch above slams.
		_play_at(load(AUDIO + "door_slam_metal.mp3"), Vector3(2.1, TOP - 0.2, LZ + 0.4), 0.0, 0.85, "Foley")
		for l: OmniLight3D in get_tree().get_nodes_in_group("lamp"):
			l.set_meta("base", 0.0)
			l.light_energy = 0.0
			l.get_node("Bulb").visible = false
			if l.has_node("Hum"):
				l.get_node("Hum").volume_db = -60.0
		player.flashlight.visible = false
	elif _scare == 1:
		_scare_t += delta
		if _scare_t > 1.4:
			_scare = 2
			if fig:
				fig.visible = false
			player.flashlight.visible = true
			$Drone.pitch_scale = 0.8
			$Drone.volume_db = -9.0
			player._show_hint("Свет погас во всём подъезде.")
			# The open flat's door moves on its own.
			_play_at(load(AUDIO + "door_creak_long.mp3"), Vector3(-1.5, 13.0, LZ + 0.3), -6.0, 0.9, "Foley")

	# Something, somewhere in the building.
	_event_t -= delta
	if _event_t <= 0.0 and not event_sounds.is_empty():
		_event_t = rng.randf_range(14.0, 36.0)
		var floor_y := (rng.randi() % FLOORS) * STOREY + 1.5
		if absf(floor_y - player.position.y) < 2.0:
			floor_y += STOREY * (1.0 if floor_y < 7.0 else -1.0)
		var where := Vector3(rng.randf_range(-1.0, 1.0), floor_y, rng.randf_range(-2.0, 3.5))
		if rng.randf() < 0.25:
			_walk_far(where, Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(),
					rng.randi_range(3, 7), rng.randf_range(-4.0, 1.0))
		else:
			_play_at(event_sounds[rng.randi() % event_sounds.size()], where,
					rng.randf_range(-9.0, -3.0), rng.randf_range(0.85, 1.1))


# ============================================================ saving the scene

func _own(node: Node) -> void:
	for c in node.get_children():
		c.owner = self
		if c.name.begins_with("@"):
			c.name = c.get_class()
		# Keep imported models as instances and let the player build itself.
		if c.scene_file_path == "" and c != player:
			_own(c)


func _bake() -> void:
	_own(self)
	var ps := PackedScene.new()
	var err := ps.pack(self)
	if err == OK:
		var target := "res://main.tscn"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--bake-to="):
				target = a.trim_prefix("--bake-to=")
		err = ResourceSaver.save(ps, target)
	print("BAKE result: ", err)
	get_tree().quit()


# ============================================================ automated test

func _flat_pos(local: Vector3) -> Vector3:
	return world.get_node("Flat17").position + local + Vector3(0, 0.05, 0)


func _pose(local: Vector3, yaw: float, pitch: float) -> void:
	player.set_physics_process(false)
	player.position = _flat_pos(local)
	player.rotation.y = yaw
	player.camera.rotation.x = pitch
	for f in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _shot(dir: String, title: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.resize(640, 360, Image.INTERPOLATE_NEAREST)
	img.save_png("%s/flat_%s.png" % [dir, title])


func _press(path: String, label: String) -> void:
	var n := world.get_node("Flat17/" + path)
	Foley.history.clear()
	var t: float = n.interact(player, n.global_position)
	await get_tree().create_timer(maxf(t, 0.3) + 0.4).timeout
	print("FLAT ", label, ": ", ", ".join(Foley.history), "  hint=", player.hint.text)


func _test_flat(dir: String) -> void:
	_scare = 3
	var flat := world.get_node("Flat17")
	# Walk in: open the front door, then go down the hall into the living room.
	await _press("Hallway/EntranceDoor/Hinge", "entrance door")
	await _press("Hallway/LivingRoomDoor/Hinge", "living room door")
	player.set_physics_process(true)
	player.position = _flat_pos(Vector3(0.0, 0, 1.0))
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	player.auto_forward = true
	await get_tree().create_timer(1.6).timeout
	print("WALK flat hall ", player.position - flat.position)
	player.position = _flat_pos(Vector3(-0.6, 0, -1.8))
	await get_tree().create_timer(1.6).timeout
	player.auto_forward = false
	print("WALK flat living ", player.position - flat.position, " floor=", player.is_on_floor())
	# Interactions.
	await _press("LivingRoom/Switch", "living room switch")
	await _press("LivingRoom/WallUnit/TV", "tv off")
	await _press("LivingRoom/WallUnit/TV", "tv on")
	await _press("LivingRoom/WallUnit/WardrobeDoorL", "wall unit door")
	await _press("LivingRoom/WallUnit/DrawerTop", "drawer")
	await _press("LivingRoom/Sofa", "sofa")
	await _press("Kitchen/Fridge/Door", "fridge")
	await _press("Kitchen/Stove/Oven", "oven")
	await _press("Kitchen/Counter/Drawer", "kitchen drawer")
	await _press("Kitchen/Table/Newspaper", "newspaper")
	await _press("Bedroom/Nightstand/DeskLamp", "desk lamp")
	await _press("Bedroom/Wardrobe/DoorL", "wardrobe")
	await _press("Hallway/ShoeCabinet/Keys", "keys")
	await _press("Hallway/ElectricPanel/Door", "electric panel")
	await _press("Hallway/BathroomDoor/Hinge", "bathroom door")
	await _press("Hallway/BathroomDoor/Hinge", "bathroom door close")
	await _press("Bedroom/Wardrobe/DoorL", "wardrobe close")
	await _press("Hallway/BedroomDoor/Hinge", "bedroom door")
	print("FLAT inventory: ", player.inventory)
	# Can you actually walk into every room?
	await _press("Hallway/KitchenDoor/Hinge", "kitchen door")
	await _press("Hallway/BathroomDoor/Hinge", "bathroom door again")
	await _press("Hallway/ToiletDoor/Hinge", "toilet door")
	await _press("Hallway/ElectricPanel/Door", "electric panel close")
	for w in [["kitchen", Vector3(-0.3, 0, -1.8), PI / 2], ["bedroom", Vector3(0.775, 0, -1.9), 0.0],
			["bathroom", Vector3(0.55, 0, -1.92), -PI / 2], ["toilet", Vector3(0.55, 0, -0.66), -PI / 2]]:
		player.set_physics_process(true)
		player.position = _flat_pos(w[1])
		player.rotation.y = w[2]
		player.velocity = Vector3.ZERO
		player.auto_forward = true
		await get_tree().create_timer(1.3).timeout
		player.auto_forward = false
		print("WALK flat into ", w[0], ": ", (player.position - flat.position).snapped(Vector3(0.01, 0.01, 0.01)))
	print("FPS in the flat: ", Engine.get_frames_per_second())
	# Lights on everywhere for the pictures.
	for g in ["lamp_hall", "lamp_kitchen", "lamp_living", "lamp_bedroom", "lamp_bath", "lamp_toilet"]:
		for l in get_tree().get_nodes_in_group(g):
			l.set_on(true)
	player.flashlight.visible = false
	var views := [
		["hall", Vector3(0.0, 0, -0.35), 0.0, -0.05],
		["hall_back", Vector3(0.3, 0, -2.3), PI, -0.1],
		["kitchen", Vector3(-1.45, 0, -1.8), PI / 2, -0.15],
		["kitchen_counters", Vector3(-2.4, 0, -1.95), PI, -0.2],
		["living", Vector3(-0.6, 0, -3.0), 0.35, -0.1],
		["living_unit", Vector3(-2.5, 0, -4.6), -PI / 2 + 0.2, -0.05],
		["living_window", Vector3(-1.6, 0, -4.2), 0.0, -0.05],
		["bedroom", Vector3(1.0, 0, -3.1), -0.5, -0.2],
		["bedroom_bed", Vector3(1.3, 0, -4.2), -PI / 2 + 0.4, -0.25],
		["bedroom_wardrobe", Vector3(2.0, 0, -4.4), PI / 2 + 0.3, -0.1],
		["bathroom", Vector3(1.4, 0, -2.2), -PI / 2 + 0.3, -0.35],
		["toilet", Vector3(1.4, 0, -0.66), -PI / 2, -0.3],
	]
	for v in views:
		await _pose(v[1], v[2], v[3])
		_shot(dir, v[0])
	# And one as the player first sees it: lamps off, flashlight on.
	for g in ["lamp_hall", "lamp_kitchen", "lamp_living", "lamp_bedroom", "lamp_bath", "lamp_toilet"]:
		for l in get_tree().get_nodes_in_group(g):
			l.set_on(false)
	player.flashlight.visible = true
	await _pose(Vector3(-0.6, 0, -3.0), 0.35, -0.1)
	_shot(dir, "living_dark")
	await _pose(Vector3(1.3, 0, -4.2), -PI / 2 + 0.4, -0.25)
	_shot(dir, "bedroom_dark")
	await _pose(Vector3(0.0, 0, 1.2), 0.0, 0.0)
	_shot(dir, "from_landing")
	player.set_physics_process(true)


func _take_shots(dir: String) -> void:
	_testing = true
	await get_tree().create_timer(1.0).timeout
	player.auto_forward = true
	var legs := [[Vector3(-0.75, -1.45, 3.0), 0.0, "entry flight"], [Vector3(0.75, 0.05, -0.5), PI, "up A1"],
			[Vector3(-0.75, 1.55, 3.0), 0.0, "up B1"], [Vector3(-0.75, 3.05, -0.5), PI, "down B1"],
			[Vector3(0.75, 1.55, 3.0), 0.0, "down A1"]]
	for leg in legs:
		player.position = leg[0]
		player.rotation.y = leg[1]
		player.velocity = Vector3.ZERO
		for t in 4:
			await get_tree().create_timer(0.5).timeout
		print("WALK ", leg[2], " ", player.position, " floor=", player.is_on_floor())
	player.auto_forward = false
	var views := [
		[Vector3(0.0, -1.45, 3.5), 0.0, 0.1],           # entry hall
		[Vector3(0.3, -1.45, 2.9), PI, 0.0],            # entrance door
		[Vector3(0.0, 0.05, -2.0), PI, 0.05],           # floor 1 landing towards the stairs
		[Vector3(0.0, 0.05, -0.4), 0.0, 0.0],           # floor 1 doors and panel
		[Vector3(0.75, 1.0, 1.6), PI, 0.3],             # climbing flight A
		[Vector3(-0.3, 1.55, 2.9), PI, 0.1],            # window, radiator, chute
		[Vector3(-0.75, 1.55, 3.3), 0.0, 0.25],         # looking up flight B
		[Vector3(0.0, 3.05, -1.8), PI, 0.0],            # floor 2
		[Vector3(0.0, 9.05, -0.6), 0.0, 0.1],           # floor 4 (dark)
		[Vector3(-0.75, 11.3, 0.9), 0.0, 0.1],          # arriving at floor 5
		[Vector3(0.6, 12.05, -0.25), 0.0, 0.0],         # floor 5: figure and open door
		[Vector3(0.0, 12.05, -1.0), 0.0, 0.35],         # graffiti: ВЫХОДА НЕТ, close
		[Vector3(-1.9, 6.05, -1.05), PI, 0.3],          # graffiti: НЕ ХОДИ НАВЕРХ
		[Vector3(0.45, -1.45, 3.0), -PI * 0.5, 0.25],   # graffiti: ЦОЙ ЖИВ
		[Vector3(-0.75, 8.2, 1.3), -PI * 0.5, 0.0],     # graffiti: оно на пятом этаже, across the well
		[Vector3(-0.3, 0.05, -1.4), 0.0, 0.25],         # graffiti: Лёха лох above the panel
	]
	for i in views.size():
		player.set_physics_process(false)
		player.position = views[i][0]
		player.rotation.y = views[i][1]
		player.camera.rotation.x = views[i][2]
		_scare = 3  # keep the event from firing while posing
		for f in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(640, 360, Image.INTERPOLATE_NEAREST)
		img.save_png("%s/shot_%d.png" % [dir, i])
	await _test_flat(dir)
	# Interactions: aim at each kind of object, press E, record which recordings played.
	var targets := [
		["apartment door", Vector3(-1.5, 0.05, -1.5), 0.0, -0.15],
		["electrical panel", Vector3(0.0, 0.05, -1.6), 0.0, 0.0],
		["mailboxes", Vector3(-0.55, -1.45, 3.25), PI * 0.5, -0.35],
		["entrance door", Vector3(0.0, -1.45, 3.2), PI, 0.0],
		["garbage chute", Vector3(0.75, 1.55, 3.0), -2.6, 0.0],
		["attic padlock", Vector3(2.1, 12.05, -1.7), 0.0, 0.0],
	]
	for t in targets:
		player.position = t[1]
		player.rotation.y = t[2]
		player.camera.rotation.x = t[3]
		player.played.clear()
		_scare = 3
		await get_tree().physics_frame
		await get_tree().physics_frame
		player._busy_until = 0
		player._interact()
		await get_tree().create_timer(1.3).timeout
		print("SOUND ", t[0], ": ", ", ".join(player.played))
	player.played.clear()
	var f := InputEventKey.new()
	f.physical_keycode = KEY_F
	f.pressed = true
	player.handle_input(f)
	print("SOUND flashlight: ", ", ".join(player.played))
	# Now let the fifth-floor event run for real.
	_scare = 0
	player.set_physics_process(true)
	player.position = Vector3(0.0, 12.05, -0.6)
	await get_tree().create_timer(0.6).timeout
	print("SCARE state after trigger: ", _scare)
	await RenderingServer.frame_post_draw
	var dark := get_viewport().get_texture().get_image()
	dark.resize(640, 360, Image.INTERPOLATE_NEAREST)
	dark.save_png("%s/shot_blackout.png" % dir)
	await get_tree().create_timer(1.5).timeout
	print("SCARE state at end: ", _scare, " figure visible=", world.get_node("Figure").visible)
	get_tree().quit()
