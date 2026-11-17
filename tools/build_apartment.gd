extends SceneTree
## Builds flat 17: a two-room khrushchevka on the fifth floor, PS1 style.
##
## Writes reusable furniture/fitting scenes to apartment/props, one scene per room to
## apartment/rooms, and apartment/apartment_17.tscn that puts the rooms together. Every
## surface uses the PSX Look material; textures come from tools/make_apartment_textures.py.
##
## Run:  godot --headless --path . --script tools/build_apartment.gd
## (after  python tools/make_apartment_textures.py  and an --import pass)
##
## Coordinates (flat-local, metres): x to the right as you walk in, y up, -z away from the
## landing. The flat's door is at x = 0 in the landing wall (z = 0); the hall starts at z = -0.2.

const TEX := "res://apartment/textures/"
const MATS := "res://apartment/materials/"
const PROPS := "res://apartment/props/"
const ROOMS := "res://apartment/rooms/"
const SCRIPTS := "res://apartment/scripts/"
const H := 2.5

# Render layer bits (the stairwell uses 0-9 and 11-14; 4 is the fifth-floor landing).
const L_LANDING := 4
const L_HALL := 10
const L_KITCHEN := 15
const L_LIVING := 16
const L_BED := 17
const L_BATH := 18
const L_TOILET := 19

var M := {}
var P := {}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MATS))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROPS))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOMS))
	_materials()
	var p := _props()
	_rooms(p)
	print("apartment done")
	quit()


# ================================================================ materials

func _material(title: String, kind: String, tex: String, color := Color.WHITE, uv := Vector2.ONE) -> void:
	var m: ShaderMaterial
	if kind == "lit":
		m = PSX.make(&"lit", load(tex) if tex != "" else null, color)
	else:
		m = ShaderMaterial.new()
		m.shader = load("res://shaders/psx_%s.gdshader" % kind)
		m.set_shader_parameter(&"albedo", color)
		if tex != "":
			m.set_shader_parameter(&"albedo_texture", load(tex))
	m.set_shader_parameter(&"affine", 0.55)
	m.set_shader_parameter(&"uv_scale", uv)
	var path := MATS + title + ".tres"
	ResourceSaver.save(m, path)
	M[title] = load(path)


func _materials() -> void:
	for t in ["wallpaper_living", "wallpaper_bed", "wallpaper_hall", "paint_kitchen", "paint_bath",
			"tile_kitchen", "tile_bath", "tile_floor", "ceiling", "plaster_grey", "parquet", "linoleum",
			"carpet_floor", "carpet_wall", "wood_dark", "wood_mid", "wood_light", "fabric_sofa",
			"fabric_chair", "bedspread", "pillow", "oilcloth", "coat", "coat_brown", "enamel",
			"enamel_bath", "chrome", "aluminium", "leather", "plastic_cream", "pipe_paint", "gas_pipe",
			"rubber", "lampshade", "soil", "glass_dark", "iron_paint", "books", "crt_off", "mirror",
			"door_paint", "newspaper", "photo"]:
		_material(t, "lit", TEX + t + ".png")
	_material("brass", "lit", TEX + "chrome.png", Color(0.95, 0.75, 0.42))
	_material("plastic_dark", "lit", TEX + "rubber.png", Color(2.4, 2.4, 2.3))
	_material("frame_paint", "lit", TEX + "plastic_cream.png", Color(1.05, 1.05, 1.0))
	_material("frosted", "lit", TEX + "glass_dark.png", Color(3.2, 3.3, 3.2))
	_material("door_quilted", "lit", "res://assets/psx/door.png", Color(0.62, 0.38, 0.26))
	_material("door_metal", "lit", "res://assets/psx/door_metal.png")
	_material("bulb_off", "lit", TEX + "glass_dark.png", Color(2.2, 2.0, 1.7))
	for t in ["tulle", "drape", "towel", "leaf"]:
		_material(t, "cutout", TEX + t + ".png")
	_material("shade_glass", "cutout", TEX + "plastic_cream.png", Color(1.25, 1.22, 1.12))
	_material("shade_lamp", "cutout", TEX + "lampshade.png")
	_material("window", "unlit", "res://assets/psx/window.png")
	_material("bulb_on", "unlit", TEX + "bulb_on.png", Color(1.0, 0.9, 0.7))
	_material("bulb_sick", "unlit", TEX + "bulb_on.png", Color(0.75, 0.85, 0.6))
	_material("black", "unlit", "", Color(0.01, 0.01, 0.012))
	_material("crt_snow", "unlit", TEX + "crt_snow.png", Color(0.9, 0.95, 1.0), Vector2(1.0, 0.25))


# ================================================================ mesh building

class MB:
	var surf := {}
	var xf := Transform3D.IDENTITY
	var cols: Array = []
	var tint := Color.WHITE
	var ao: Callable
	var cell := 0.45
	var _stack: Array[Transform3D] = []

	func push(t: Transform3D) -> void:
		_stack.append(xf)
		xf = xf * t

	func pop() -> void:
		xf = _stack.pop_back()

	func _st(m: String) -> SurfaceTool:
		if not surf.has(m):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			surf[m] = st
		return surf[m]

	func _colour(p: Vector3, shade: float) -> Color:
		var g := shade
		if ao.is_valid():
			g *= float(ao.call(p))
		return Color(tint.r * g, tint.g * g, tint.b * g)

	## A four-cornered patch, cut into cells. p00 bottom-left, p10 bottom-right, p01 top-left as
	## seen from its front. With outward set, the winding is fixed to face that way.
	func quad(m: String, p00: Vector3, p10: Vector3, p01: Vector3, p11: Vector3,
			uv00 := Vector2(0, 1), uv10 := Vector2(1, 1), uv01 := Vector2(0, 0), uv11 := Vector2(1, 0),
			shade := 1.0, nu := 0, nv := 0, outward := Vector3.ZERO) -> void:
		var a := xf * p00
		var b := xf * p10
		var c := xf * p01
		var d := xf * p11
		var ua := uv00
		var ub := uv10
		var uc := uv01
		var ud := uv11
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			n = (d - c).cross(c - a)
		if outward != Vector3.ZERO and n.dot(xf.basis * outward) < 0.0:
			var t := b
			b = c
			c = t
			var tu := ub
			ub = uc
			uc = tu
			var tn := nu
			nu = nv
			nv = tn
			n = -n
		n = n.normalized()
		if nu <= 0:
			nu = maxi(1, ceili(maxf((b - a).length(), (d - c).length()) / cell - 0.01))
		if nv <= 0:
			nv = maxi(1, ceili(maxf((c - a).length(), (d - b).length()) / cell - 0.01))
		var st := _st(m)
		for j in nv:
			for i in nu:
				for k in [[i, j], [i, j + 1], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i + 1, j]]:
					var u: float = float(k[0]) / nu
					var v: float = float(k[1]) / nv
					var p := a.lerp(b, u).lerp(c.lerp(d, u), v)
					st.set_normal(n)
					st.set_uv(ua.lerp(ub, u).lerp(uc.lerp(ud, u), v))
					st.set_color(_colour(p, shade))
					st.add_vertex(p)

	func tri(m: String, p0: Vector3, p1: Vector3, p2: Vector3, outward: Vector3,
			uv0 := Vector2(0, 1), uv1 := Vector2(1, 1), uv2 := Vector2(0.5, 0), shade := 1.0) -> void:
		var a := xf * p0
		var b := xf * p1
		var c := xf * p2
		var n := (c - a).cross(b - a)
		var ua := uv0
		var ub := uv1
		var uc := uv2
		if n.dot(xf.basis * outward) < 0.0:
			var t := b
			b = c
			c = t
			var tu := ub
			ub = uc
			uc = tu
			n = -n
		n = n.normalized()
		var st := _st(m)
		for q in [[a, ua], [b, ub], [c, uc]]:
			st.set_normal(n)
			st.set_uv(q[1])
			st.set_color(_colour(q[0], shade))
			st.add_vertex(q[0])

	## A flat rectangle. tile > 0 repeats the texture every `tile` metres; otherwise stretched.
	func face(m: String, p0: Vector3, du: Vector3, dv: Vector3, tile := 0.0, shade := 1.0) -> void:
		var lu := du.length()
		var lv := dv.length()
		if tile <= 0.0:
			quad(m, p0, p0 + du, p0 + dv, p0 + du + dv, Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0), shade)
			return
		var o := Vector2(p0.dot(du / lu), -p0.dot(dv / lv)) / tile
		quad(m, p0, p0 + du, p0 + dv, p0 + du + dv, o, o + Vector2(lu / tile, 0), o + Vector2(0, -lv / tile),
				o + Vector2(lu / tile, -lv / tile), shade)

	static func lo(a: Vector3, b: Vector3) -> Vector3:
		return Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))

	static func hi(a: Vector3, b: Vector3) -> Vector3:
		return Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))

	## Axis-aligned box from any two corners. skip: faces to leave out (e w s n u d = +x -x +z -z +y -y).
	func box(m: String, p: Vector3, q: Vector3, tile := 0.0, shade := 1.0, skip := "") -> void:
		var a := lo(p, q)
		var b := hi(p, q)
		var s := b - a
		if not "e" in skip:
			face(m, Vector3(b.x, a.y, b.z), Vector3(0, 0, -s.z), Vector3(0, s.y, 0), tile, shade)
		if not "w" in skip:
			face(m, a, Vector3(0, 0, s.z), Vector3(0, s.y, 0), tile, shade)
		if not "s" in skip:
			face(m, Vector3(a.x, a.y, b.z), Vector3(s.x, 0, 0), Vector3(0, s.y, 0), tile, shade)
		if not "n" in skip:
			face(m, Vector3(b.x, a.y, a.z), Vector3(-s.x, 0, 0), Vector3(0, s.y, 0), tile, shade)
		if not "u" in skip:
			face(m, Vector3(a.x, b.y, b.z), Vector3(s.x, 0, 0), Vector3(0, 0, -s.z), tile, shade)
		if not "d" in skip:
			face(m, a, Vector3(s.x, 0, 0), Vector3(0, 0, s.z), tile, shade * 0.75)

	## The inside of a box (faces looking inwards): drawers, basins, cabinet interiors.
	func ibox(m: String, p: Vector3, q: Vector3, tile := 0.0, shade := 0.8, skip := "") -> void:
		var a := lo(p, q)
		var b := hi(p, q)
		var c := (a + b) * 0.5
		var faces := {
			"e": [Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z)],
			"w": [Vector3(a.x, a.y, b.z), Vector3(a.x, a.y, a.z), Vector3(a.x, b.y, b.z), Vector3(a.x, b.y, a.z)],
			"s": [Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)],
			"n": [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z)],
			"u": [Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, b.z), Vector3(b.x, b.y, b.z)],
			"d": [Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z)],
		}
		for k: String in faces:
			if k in skip:
				continue
			var f: Array = faces[k]
			var mid: Vector3 = (f[0] + f[3]) * 0.5
			quad(m, f[0], f[1], f[2], f[3], Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0),
					shade, 0, 0, c - mid)

	## A box with its edges cut off: cushions, mattresses, rounded cases.
	func cbox(m: String, p: Vector3, q: Vector3, ch: float, tile := 0.0, shade := 1.0) -> void:
		var a := lo(p, q)
		var b := hi(p, q)
		var ce := (a + b) * 0.5
		var h := (b - a) * 0.5
		ch = minf(ch, minf(h.x, minf(h.y, h.z)) * 0.9)
		var hi_ := h - Vector3(ch, ch, ch)
		var e := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
		for ax in 3:
			for sgn in [-1.0, 1.0]:
				var n: Vector3 = e[ax] * sgn
				var ua: int = (ax + 1) % 3
				var va: int = (ax + 2) % 3
				var base: Vector3 = ce + n * h[ax]
				var eu: Vector3 = e[ua] * hi_[ua]
				var ev: Vector3 = e[va] * hi_[va]
				var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0)]
				if tile > 0.0:
					var su: float = hi_[ua] * 2.0 / tile
					var sv: float = hi_[va] * 2.0 / tile
					uvs = [Vector2(0, sv), Vector2(su, sv), Vector2(0, 0), Vector2(su, 0)]
				quad(m, base - eu - ev, base + eu - ev, base - eu + ev, base + eu + ev,
						uvs[0], uvs[1], uvs[2], uvs[3], shade, 0, 0, n)
		for l in 3:
			var i: int = (l + 1) % 3
			var j: int = (l + 2) % 3
			for si in [-1.0, 1.0]:
				for sj in [-1.0, 1.0]:
					var el: Vector3 = e[l] * hi_[l]
					var pa: Vector3 = ce + e[i] * si * h[i] + e[j] * sj * hi_[j]
					var pb: Vector3 = ce + e[i] * si * hi_[i] + e[j] * sj * h[j]
					quad(m, pa - el, pa + el, pb - el, pb + el, Vector2(0, 1), Vector2(1, 1), Vector2(0, 0.9),
							Vector2(1, 0.9), shade, 0, 1, e[i] * si + e[j] * sj)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					tri(m, ce + Vector3(sx * h.x, sy * hi_.y, sz * hi_.z), ce + Vector3(sx * hi_.x, sy * h.y, sz * hi_.z),
							ce + Vector3(sx * hi_.x, sy * hi_.y, sz * h.z), Vector3(sx, sy, sz), Vector2(0, 1),
							Vector2(1, 1), Vector2(0.5, 0.9), shade)

	## Cylinder or cone along `axis` (its length is the height). flip: faces look inwards.
	func cyl(m: String, base: Vector3, axis: Vector3, r0: float, r1: float, sides := 8, caps := true,
			shade := 1.0, flip := false) -> void:
		var ax := axis.normalized()
		var ref := Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT
		var u := ax.cross(ref).normalized()
		var w := ax.cross(u)
		var top := base + axis
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var d0 := u * cos(a0) + w * sin(a0)
			var d1 := u * cos(a1) + w * sin(a1)
			var out := (d0 + d1) * (-1.0 if flip else 1.0)
			quad(m, base + d0 * r0, base + d1 * r0, top + d0 * r1, top + d1 * r1,
					Vector2(float(i) / sides, 1), Vector2(float(i + 1) / sides, 1),
					Vector2(float(i) / sides, 0), Vector2(float(i + 1) / sides, 0), shade, 1, 1, out)
			if caps and r0 > 0.0:
				tri(m, base, base + d0 * r0, base + d1 * r0, -ax, Vector2(0.5, 0.5), Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5),
						Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5), shade * 0.8)
			if caps and r1 > 0.0:
				tri(m, top, top + d0 * r1, top + d1 * r1, ax, Vector2(0.5, 0.5), Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5),
						Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5), shade)

	## A box that narrows: wb x db at the bottom, wt x dt at the top, h tall (shift moves the top).
	func tbox(m: String, base: Vector3, wb: float, db: float, wt: float, dt: float, h: float,
			shade := 1.0, shift := Vector3.ZERO, skip := "") -> void:
		var top := base + Vector3(0, h, 0) + shift
		var b := [base + Vector3(-wb, 0, -db) * 0.5, base + Vector3(wb, 0, -db) * 0.5,
				base + Vector3(wb, 0, db) * 0.5, base + Vector3(-wb, 0, db) * 0.5]
		var t := [top + Vector3(-wt, 0, -dt) * 0.5, top + Vector3(wt, 0, -dt) * 0.5,
				top + Vector3(wt, 0, dt) * 0.5, top + Vector3(-wt, 0, dt) * 0.5]
		var c := (base + top) * 0.5
		var keys := ["n", "e", "s", "w"]
		for i in 4:
			if keys[i] in skip:
				continue
			var j := (i + 1) % 4
			var mid: Vector3 = (b[i] + b[j] + t[i] + t[j]) * 0.25
			quad(m, b[i], b[j], t[i], t[j], Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0), shade, 0, 0, mid - c)
		if not "u" in skip:
			quad(m, t[3], t[2], t[0], t[1], Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0), shade, 0, 0, Vector3.UP)
		if not "d" in skip:
			quad(m, b[0], b[1], b[3], b[2], Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0), shade * 0.75, 0, 0, Vector3.DOWN)

	## A flat ellipse, fan-triangulated, in the plane of axes eu/ev, facing eu x ev.
	func disc(m: String, c: Vector3, eu: Vector3, ev: Vector3, sides := 12, shade := 1.0) -> void:
		var n := eu.cross(ev)
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			tri(m, c, c + eu * cos(a0) + ev * sin(a0), c + eu * cos(a1) + ev * sin(a1), n, Vector2(0.5, 0.5),
					Vector2(0.5 + cos(a0) * 0.5, 0.5 - sin(a0) * 0.5), Vector2(0.5 + cos(a1) * 0.5, 0.5 - sin(a1) * 0.5), shade)

	## An elliptical ring between two sizes (frames, toilet seat).
	func ring(m: String, c: Vector3, eu: Vector3, ev: Vector3, inner: float, sides := 12, shade := 1.0) -> void:
		var n := eu.cross(ev)
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var o0 := eu * cos(a0) + ev * sin(a0)
			var o1 := eu * cos(a1) + ev * sin(a1)
			quad(m, c + o0 * inner, c + o1 * inner, c + o0, c + o1, Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0),
					shade, 1, 1, n)

	## Hanging fabric with folds: x0..x1 at depth z, from y0 up to y1.
	func folds(m: String, x0: float, x1: float, y0: float, y1: float, z: float, count: int, depth: float, tile: float) -> void:
		var n := count * 2
		for i in n:
			var xa := lerpf(x0, x1, float(i) / n)
			var xb := lerpf(x0, x1, float(i + 1) / n)
			var za := z + (depth if i % 2 == 1 else 0.0)
			var zb := z + (depth if i % 2 == 0 else 0.0)
			quad(m, Vector3(xa, y0, za), Vector3(xb, y0, zb), Vector3(xa, y1, za), Vector3(xb, y1, zb),
					Vector2(xa / tile, y0 / -tile + 10), Vector2(xb / tile, y0 / -tile + 10),
					Vector2(xa / tile, y1 / -tile + 10), Vector2(xb / tile, y1 / -tile + 10), 1.0 if i % 2 == 0 else 0.8)

	## Collision box (transformed by the current transform, as an axis-aligned box).
	func col(p: Vector3, q: Vector3) -> void:
		var a := lo(p, q)
		var b := hi(p, q)
		var mn := Vector3(INF, INF, INF)
		var mx := Vector3(-INF, -INF, -INF)
		for i in 8:
			var c := xf * Vector3(b.x if i & 1 else a.x, b.y if i & 2 else a.y, b.z if i & 4 else a.z)
			mn = lo(mn, c)
			mx = hi(mx, c)
		cols.append([mn, mx])

	func commit(mats: Dictionary) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for m: String in surf:
			var st: SurfaceTool = surf[m]
			st.index()
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mats[m])
		return mesh


# ================================================================ scene helpers

func _mesh(mb: MB, title := "Mesh") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = title
	mi.mesh = mb.commit(M)
	return mi


func _body(cols: Array, title := "Body", moving := false) -> CollisionObject3D:
	var b: CollisionObject3D
	if moving:
		var ab := AnimatableBody3D.new()
		ab.sync_to_physics = false
		b = ab
	else:
		b = StaticBody3D.new()
	b.name = title
	for i in cols.size():
		var pair: Array = cols[i]
		var shape := BoxShape3D.new()
		var size: Vector3 = (pair[1] - pair[0])
		shape.size = Vector3(maxf(size.x, 0.01), maxf(size.y, 0.01), maxf(size.z, 0.01))
		var cs := CollisionShape3D.new()
		cs.name = "Shape%d" % i
		cs.shape = shape
		cs.position = (pair[0] + pair[1]) * 0.5
		b.add_child(cs)
	return b


func _own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		if c.scene_file_path == "":
			_own(c, owner)


func _save(root: Node, path: String) -> void:
	_own(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		err = ResourceSaver.save(ps, path)
	if err != OK:
		push_error("could not save %s (%d)" % [path, err])
	root.free()
	print("  ", path)


## A reusable piece: build(mb, root) adds geometry to mb and interactive children to root.
func _prop(title: String, build: Callable, script := "", props := {}) -> String:
	var root := Node3D.new()
	root.name = title.to_pascal_case()
	if script != "":
		root.set_script(load(SCRIPTS + script + ".gd"))
		for k in props:
			root.set(k, props[k])
	var mb := MB.new()
	build.call(mb, root)
	if not mb.surf.is_empty():
		var mi := _mesh(mb)
		root.add_child(mi)
		root.move_child(mi, 0)
	if not mb.cols.is_empty():
		root.add_child(_body(mb.cols))
	var path := PROPS + title + ".tscn"
	_save(root, path)
	return path


func _inst(parent: Node, path: String, pos: Vector3, rot_y := 0.0, title := "", props := {}) -> Node3D:
	var n: Node3D = (load(path) as PackedScene).instantiate()
	n.position = pos
	n.rotation.y = rot_y
	if title != "":
		n.name = title
	for k in props:
		n.set(k, props[k])
	parent.add_child(n)
	return n


func _hinged(parent: Node3D, title: String, pivot: Vector3, build: Callable, kind: String, angle: float,
		desc := "", axis := "y", ajar := 0.0, time := 0.0) -> Node3D:
	var h := Node3D.new()
	h.name = title
	h.position = pivot
	h.set_script(load(SCRIPTS + "hinged.gd"))
	h.set("kind", kind)
	h.set("open_angle", angle)
	h.set("description", desc)
	h.set("axis", axis)
	h.set("ajar_angle", ajar)
	if time > 0.0:
		h.set("open_time", time)
	parent.add_child(h)
	var mb := MB.new()
	build.call(mb)
	var leaf := _body(mb.cols, "Leaf", true)
	h.add_child(leaf)
	leaf.add_child(_mesh(mb))
	return h


func _drawer(parent: Node3D, title: String, pos: Vector3, build: Callable, contents: String, desc: String, slide: float) -> void:
	var d := Node3D.new()
	d.name = title
	d.position = pos
	d.set_script(load(SCRIPTS + "drawer.gd"))
	d.set("contents", contents)
	d.set("description", desc)
	d.set("slide", slide)
	parent.add_child(d)
	var mb := MB.new()
	build.call(mb)
	var body := _body(mb.cols, "Box", true)
	d.add_child(body)
	body.add_child(_mesh(mb))


## Something small you can look at, and maybe take.
func _item(parent: Node3D, title: String, pos: Vector3, rot_y: float, build: Callable, name_ru: String,
		desc: String, take: bool, material: String) -> void:
	var n := Node3D.new()
	n.name = title
	n.position = pos
	n.rotation.y = rot_y
	n.set_script(load(SCRIPTS + "item.gd"))
	n.set("title", name_ru)
	n.set("description", desc)
	n.set("take", take)
	n.set("material", material)
	parent.add_child(n)
	var mb := MB.new()
	build.call(mb)
	if not mb.surf.is_empty():
		n.add_child(_mesh(mb))
	n.add_child(_body(mb.cols))


func _light(parent: Node3D, title: String, pos: Vector3, energy: float, color: Color, reach: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = title
	l.position = pos
	l.light_energy = energy
	l.light_color = color
	l.omni_range = reach
	l.omni_attenuation = 1.3
	l.shadow_enabled = false
	parent.add_child(l)
	return l


func _decal(parent: Node3D, tex: String, pos: Vector3, n: Vector3, w: float, h: float, spin := 0.0, title := "") -> void:
	var d := Decal.new()
	d.name = title if title != "" else tex.to_pascal_case()
	d.texture_albedo = load(TEX + tex + ".png")
	d.size = Vector3(w, 0.16, h)
	var right := (-n).cross(Vector3.UP).normalized() if absf(n.y) < 0.9 else Vector3.RIGHT
	var b := Basis(right, n, right.cross(n))
	d.basis = Basis(n, spin) * b
	d.position = pos
	d.normal_fade = 0.5
	d.upper_fade = 0.1
	d.lower_fade = 0.1
	parent.add_child(d)


func _hitbox(mb: MB, size: Vector3, offset := Vector3.ZERO) -> void:
	mb.col(offset - size * 0.5, offset + size * 0.5)


# ================================================================ small parts used by props

## A coat on a hanger; top is the hook point.
func _coat(mb: MB, top: Vector3, mat: String, rot := 0.0, length := 0.95) -> void:
	mb.push(Transform3D(Basis(Vector3.UP, rot), top))
	mb.cyl("chrome", Vector3(0, -0.05, 0), Vector3(0, 0.05, 0), 0.004, 0.004, 4)
	mb.tbox(mat, Vector3(0, -0.05 - length, 0), 0.38, 0.12, 0.32, 0.1, length - 0.02)
	mb.tbox(mat, Vector3(0, -0.09, 0), 0.32, 0.1, 0.14, 0.08, 0.05)                # shoulders
	for s in [-1.0, 1.0]:
		mb.tbox(mat, Vector3(0.16 * s, -0.68, 0.01), 0.06, 0.08, 0.08, 0.09, 0.58, 0.85, Vector3(0.012 * s, 0, 0))
	mb.cbox(mat, Vector3(-0.09, -0.12, -0.06), Vector3(0.09, -0.04, 0.05), 0.02)   # collar
	mb.pop()


## A door or cabinet leaf on its hinge: from x = 0 to sx * w, y 0..h, z -t..0.
func _leaf(mb: MB, w: float, h: float, t: float, sx: float, front: String, back: String, edge: String,
		glass := false, lever := true, knob_y := 1.0) -> void:
	var x1 := sx * w
	var a := Vector3(0, 0.005, 0)
	var b := Vector3(x1, 0.005, 0)
	mb.quad(front, a, b, a + Vector3(0, h - 0.01, 0), b + Vector3(0, h - 0.01, 0), Vector2(0, 1), Vector2(1, 1),
			Vector2(0, 0), Vector2(1, 0), 1.0, 0, 0, Vector3.BACK)
	mb.quad(back, a + Vector3(0, 0, -t), b + Vector3(0, 0, -t), a + Vector3(0, h - 0.01, -t), b + Vector3(0, h - 0.01, -t),
			Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0), 1.0, 0, 0, Vector3.FORWARD)
	mb.box(edge, Vector3(0, 0.005, -t), Vector3(x1, h - 0.005, 0), 0.0, 0.8, "sn")
	if glass:
		for z in [0.002, -t - 0.002]:
			var zz: float = z
			mb.quad("frosted", Vector3(sx * w * 0.17, h * 0.5, zz), Vector3(sx * w * 0.83, h * 0.5, zz),
					Vector3(sx * w * 0.17, h * 0.9, zz), Vector3(sx * w * 0.83, h * 0.9, zz), Vector2(0, 1), Vector2(1, 1),
					Vector2(0, 0), Vector2(1, 0), 1.0, 0, 0, Vector3(0, 0, 1.0 if zz > 0 else -1.0))
	var hx := sx * (w - 0.065)
	if lever:
		for side in [1.0, -1.0]:
			var z0: float = 0.0 if side > 0 else -t
			mb.cyl("chrome", Vector3(hx, knob_y, z0), Vector3(0, 0, 0.012 * side), 0.025, 0.025, 8)
			mb.cyl("chrome", Vector3(hx, knob_y, z0 + 0.012 * side), Vector3(0, 0, 0.035 * side), 0.009, 0.009, 6)
			mb.box("chrome", Vector3(hx, knob_y - 0.01, z0 + 0.04 * side), Vector3(hx - sx * 0.12, knob_y + 0.01, z0 + 0.055 * side))
	else:
		mb.box("chrome", Vector3(hx - 0.006, h * 0.45, 0.0), Vector3(hx + 0.006, h * 0.45 + 0.11, 0.022))
	mb.col(Vector3(0, 0, -t), Vector3(x1, h, 0))


func _drawer_box(mb: MB, w: float, h: float, d: float, mat: String, front_z: float, inner := "wood_light") -> void:
	mb.box(mat, Vector3(-w * 0.5, 0.005, front_z - 0.02), Vector3(w * 0.5, h - 0.005, front_z), 0.0)
	mb.ibox(inner, Vector3(-w * 0.5 + 0.015, 0.02, front_z - d), Vector3(w * 0.5 - 0.015, h - 0.03, front_z - 0.02), 0.0, 0.7, "u")
	mb.box("chrome", Vector3(-0.06, h * 0.55, front_z), Vector3(0.06, h * 0.55 + 0.018, front_z + 0.02))
	mb.col(Vector3(-w * 0.5, 0.0, front_z - 0.03), Vector3(w * 0.5, h, front_z))


# ================================================================ props

func _props() -> Dictionary:
	var p := {}
	print("props:")
	p.tv = _prop("crt_tv", _p_tv, "tv", {"screen_off": M.crt_off, "screen_on": M.crt_snow})
	p.desk_lamp = _prop("desk_lamp", _p_desk_lamp, "lamp", {"on_material": M.bulb_on, "off_material": M.bulb_off,
			"pull_switch": true, "energy": 0.7})
	p.sofa = _prop("sofa", _p_sofa, "item", {"title": "Диван", "description": "Диван-книжка. Обивка протёрта до ниток, в щели между подушками — пуговица и шпилька.", "material": "fabric"})
	p.armchair = _prop("armchair", _p_armchair, "item", {"title": "Кресло", "description": "Кресло. На подлокотнике тёмное пятно — сюда годами ставили чашку.", "material": "fabric"})
	p.wall_unit = _prop("wall_unit", _p_wall_unit.bind(p.tv))
	p.coffee_table = _prop("coffee_table", _p_coffee_table)
	p.carpet_floor = _prop("carpet_floor", _p_carpet_floor)
	p.carpet_wall = _prop("carpet_wall", _p_carpet_wall.bind(2.1, 1.45), "item", {"title": "Ковёр", "description": "Ковёр на стене. Узор выцвел там, где на него падало солнце.", "material": "fabric"})
	p.carpet_wall_bed = _prop("carpet_wall_bed", _p_carpet_wall.bind(1.7, 1.2), "item", {"title": "Ковёр", "description": "Ковёр над кроватью. Под ним на обоях — карандашные отметки роста: «Серёжа, 5 лет», «6 лет», «7 лет». Дальше нет.", "material": "fabric"})
	p.chandelier = _prop("chandelier", _p_chandelier, "lamp", {"on_material": M.bulb_on, "off_material": M.bulb_off, "energy": 1.25})
	p.window_150 = _prop("window_150", _p_window.bind(1.5, 1.25, 0.25))
	p.window_120 = _prop("window_120", _p_window.bind(1.2, 1.25, 0.25))
	p.window_90 = _prop("window_90", _p_window.bind(0.9, 1.25, 0.25))
	p.curtains_150 = _prop("curtains_150", _p_curtains.bind(1.5, 2.2, true))
	p.curtains_120 = _prop("curtains_120", _p_curtains.bind(1.2, 2.2, true))
	p.curtains_90 = _prop("curtains_90", _p_curtains.bind(0.9, 1.35, false))
	p.radiator_10 = _prop("radiator_10", _p_radiator.bind(10), "item", {"title": "Батарея", "description": "Чугунная батарея. Холодная. Краска слоями — белая, зелёная, снова белая.", "material": "metal"})
	p.radiator_8 = _prop("radiator_8", _p_radiator.bind(8), "item", {"title": "Батарея", "description": "Батарея. Холодная.", "material": "metal"})
	p.radiator_6 = _prop("radiator_6", _p_radiator.bind(6), "item", {"title": "Батарея", "description": "Батарея под окном. Холодная.", "material": "metal"})
	p.plant = _prop("plant", _p_plant, "item", {"title": "Цветок", "description": "Засохшая герань. Земля в горшке растрескалась.", "material": "ceramic"})
	p.bed = _prop("bed", _p_bed, "item", {"title": "Кровать", "description": "Покрывало заправлено ровно. Матрас под ним продавлен с одной стороны.", "material": "fabric"})
	p.wardrobe = _prop("wardrobe", _p_wardrobe)
	p.nightstand = _prop("nightstand", _p_nightstand.bind(p.desk_lamp))
	p.mirror_oval = _prop("mirror_oval", _p_mirror_oval, "item", {"title": "Зеркало", "description": "В зеркале — луч фонарика и темнота за спиной.", "material": "glass"})
	p.stool = _prop("stool", _p_stool.bind(false), "item", {"title": "Табурет", "description": "Табурет. Одна ножка короче, он качается.", "material": "wood"})
	p.stool_clothes = _prop("stool_clothes", _p_stool.bind(true), "item", {"title": "Одежда", "description": "Сложенная рубашка. Пуговицы застёгнуты до самого верха.", "material": "fabric"})
	p.slippers = _prop("slippers", _p_slippers, "item", {"title": "Тапочки", "description": "Тапочки стоят носками к кровати, как будто в них только что легли спать.", "material": "fabric"})
	p.pendant = _prop("pendant", _p_pendant, "lamp", {"on_material": M.bulb_on, "off_material": M.bulb_off, "energy": 1.0})
	p.stove = _prop("stove", _p_stove, "item", {"title": "Плита", "description": "Газовая плита «Брест». Краны закрыты, ручки залипли от жира.", "material": "metal"})
	p.sink_cab = _prop("sink_cabinet", _p_sink_cab, "item", {"title": "Мойка", "description": "Мойка. Кран сухой — воду перекрыли давно.", "material": "metal"})
	p.counter_cab = _prop("counter_cabinet", _p_counter_cab)
	p.wall_cab = _prop("wall_cabinet", _p_wall_cab)
	p.fridge = _prop("fridge", _p_fridge)
	p.kitchen_table = _prop("kitchen_table", _p_kitchen_table)
	p.dish_rack = _prop("dish_rack", _p_dish_rack, "item", {"title": "Сушилка", "description": "Сушилка для посуды. Две тарелки и кружка с отбитой ручкой.", "material": "ceramic"})
	p.vent = _prop("vent", _p_vent, "item", {"title": "Вентиляция", "description": "Вентиляционная решётка. Из шахты тянет холодом, где-то далеко капает вода.", "material": "metal"})
	p.kitchen_lamp = _prop("kitchen_lamp", _p_kitchen_lamp, "lamp", {"on_material": M.bulb_on, "off_material": M.bulb_off, "energy": 1.0})
	p.coat_rack = _prop("coat_rack", _p_coat_rack, "item", {"title": "Вешалка", "description": "Пальто, плащ и детская куртка. Под ними сапоги и маленькие сандалии.", "material": "fabric"})
	p.mirror_rect = _prop("mirror_rect", _p_mirror_rect, "item", {"title": "Зеркало", "description": "Зеркало в прихожей. По краям серебро отошло чёрными пятнами.", "material": "glass"})
	p.tumba = _prop("shoe_cabinet", _p_tumba)
	p.el_panel = _prop("electric_panel", _p_el_panel)
	p.switch = _prop("light_switch", _p_switch, "light_switch")
	p.bulb = _prop("bare_bulb", _p_bulb, "lamp", {"on_material": M.bulb_on, "off_material": M.bulb_off, "energy": 0.9})
	p.wall_lamp = _prop("wall_lamp", _p_wall_lamp, "lamp", {"on_material": M.bulb_on, "off_material": M.bulb_off, "energy": 0.8})
	p.doormat = _prop("doormat", _p_doormat)
	p.bathtub = _prop("bathtub", _p_bathtub, "item", {"title": "Ванна", "description": "Чугунная ванна. На дне рыжие разводы, к сливу прилип длинный волос.", "material": "ceramic"})
	p.mixer = _prop("bath_mixer", _p_mixer, "item", {"title": "Смеситель", "description": "Вентили не поворачиваются. В трубах сухо.", "material": "metal"})
	p.basin = _prop("wash_basin", _p_basin, "item", {"title": "Раковина", "description": "Раковина. Трещина от края до слива, по ней ржавая дорожка.", "material": "ceramic"})
	p.bath_mirror = _prop("bath_mirror", _p_bath_mirror, "item", {"title": "Полочка", "description": "Две зубные щётки в стакане. Щетина слиплась.", "material": "glass"})
	p.towel_rail = _prop("towel_rail", _p_towel_rail, "item", {"title": "Полотенце", "description": "Полотенце на сушилке. Высохло колом.", "material": "fabric"})
	p.bucket = _prop("bucket", _p_bucket, "item", {"title": "Ведро", "description": "Эмалированное ведро. На дне — засохшая тряпка.", "material": "metal"})
	p.toilet = _prop("toilet", _p_toilet, "item", {"title": "Унитаз", "description": "Унитаз. Воды нет, на фаянсе бурый налёт.", "material": "ceramic"})
	p.tank = _prop("toilet_tank", _p_tank, "item", {"title": "Бачок", "description": "Чугунный бачок под потолком. Цепочка обмотана проволокой.", "material": "metal"})
	p.paper_nail = _prop("paper_nail", _p_paper_nail, "item", {"title": "Газета", "description": "Нарезанная газета на гвозде.", "material": "paper"})
	for d in [["door_entrance", 0.9, 2.05, 0.2, -1.0, "door_metal", "door_quilted", false, "metal_door", 30.0, "17"],
			["door_80_glass_l", 0.8, 2.0, 0.12, 1.0, "door_paint", "door_paint", true, "wood_door", 0.0, ""],
			["door_66_l", 0.66, 2.0, 0.12, 1.0, "door_paint", "door_paint", false, "wood_door", 0.0, ""],
			["door_66_r", 0.66, 2.0, 0.12, -1.0, "door_paint", "door_paint", false, "wood_door", 0.0, ""]]:
		p[d[0]] = _door_scene(d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], d[9], d[10])
	return p


func _door_scene(title: String, w: float, h: float, t: float, sx: float, front: String, back: String, glass: bool,
		kind: String, ajar: float, number: String) -> String:
	var root := Node3D.new()
	root.name = title.to_pascal_case()
	var mb := MB.new()
	var fm := "wood_dark" if kind == "metal_door" else "door_paint"
	# Lining across the wall thickness, and the architraves on both faces.
	mb.box(fm, Vector3(-w * 0.5 - 0.03, 0, -t * 0.5), Vector3(-w * 0.5, h + 0.03, t * 0.5), 0.0, 0.8)
	mb.box(fm, Vector3(w * 0.5, 0, -t * 0.5), Vector3(w * 0.5 + 0.03, h + 0.03, t * 0.5), 0.0, 0.8)
	mb.box(fm, Vector3(-w * 0.5, h, -t * 0.5), Vector3(w * 0.5, h + 0.03, t * 0.5), 0.0, 0.7)
	for side in [1.0, -1.0]:
		var z0: float = t * 0.5 * side
		var z1: float = z0 + 0.016 * side
		mb.box(fm, Vector3(-w * 0.5 - 0.09, 0, z0), Vector3(-w * 0.5 - 0.01, h + 0.09, z1))
		mb.box(fm, Vector3(w * 0.5 + 0.01, 0, z0), Vector3(w * 0.5 + 0.09, h + 0.09, z1))
		mb.box(fm, Vector3(-w * 0.5 - 0.09, h + 0.01, z0), Vector3(w * 0.5 + 0.09, h + 0.09, z1))
	mb.box("wood_dark", Vector3(-w * 0.5, 0, -t * 0.5), Vector3(w * 0.5, 0.012, t * 0.5), 0.0, 0.7)   # threshold
	mb.col(Vector3(-w * 0.5 - 0.09, 0, -t * 0.5), Vector3(-w * 0.5, h + 0.09, t * 0.5))
	mb.col(Vector3(w * 0.5, 0, -t * 0.5), Vector3(w * 0.5 + 0.09, h + 0.09, t * 0.5))
	root.add_child(_mesh(mb, "Frame"))
	root.add_child(_body(mb.cols, "FrameBody"))
	var lt := 0.055 if kind == "metal_door" else 0.04
	var pivot := Vector3(-sx * w * 0.5, 0, t * 0.5)
	var hinge := _hinged(root, "Hinge", pivot, _door_leaf.bind(w - 0.01, h - 0.01, lt, sx, front, back, glass, number, kind),
			kind, -95.0 * sx if kind != "metal_door" else -100.0 * sx, "", "y", -ajar * sx if ajar > 0.0 else 0.0,
			1.3 if kind == "metal_door" else 0.9)
	hinge.set("locked", false)
	var path := PROPS + title + ".tscn"
	_save(root, path)
	return path


func _door_leaf(mb: MB, w: float, h: float, t: float, sx: float, front: String, back: String, glass: bool,
		number: String, kind: String) -> void:
	if kind == "metal_door":
		# Leatherette quilting on the landing side, steel inside.
		_leaf(mb, w, h, t, sx, front, back, "rubber", false, true, 1.0)
		mb.cyl("chrome", Vector3(sx * w * 0.5, 1.5, -t), Vector3(0, 0, -0.012), 0.012, 0.012, 6)      # peephole
		mb.box("brass", Vector3(sx * w * 0.5 - 0.06, 1.68, -t - 0.004), Vector3(sx * w * 0.5 + 0.06, 1.8, -t))  # number plate
		mb.box("chrome", Vector3(sx * (w - 0.08) - 0.03, 1.12, -t - 0.01), Vector3(sx * (w - 0.08) + 0.03, 1.2, -t))  # keyhole plate
	else:
		_leaf(mb, w, h, t, sx, front, back, "door_paint", glass, true, 0.98)


# ---------------------------------------------------------------- living room

func _p_sofa(mb: MB, _root: Node3D) -> void:
	var wd := "wood_dark"
	var f := "fabric_sofa"
	for x in [-0.9, 0.9]:
		for z in [-0.34, 0.34]:
			mb.cyl(wd, Vector3(x, 0, z), Vector3(0, 0.1, 0), 0.022, 0.03, 6)
	mb.box(wd, Vector3(-0.95, 0.1, -0.42), Vector3(0.95, 0.3, 0.4), 0.5)
	for s in [-1.0, 1.0]:
		mb.box(wd, Vector3(0.93 * s, 0.06, -0.44), Vector3(1.0 * s, 0.6, 0.42), 0.5)
		mb.cyl(wd, Vector3(0.965 * s, 0.6, -0.44), Vector3(0, 0, 0.86), 0.036, 0.036, 6)
	mb.cbox(f, Vector3(-0.93, 0.3, -0.2), Vector3(0.93, 0.47, 0.42), 0.04, 0.5)
	mb.push(Transform3D(Basis(Vector3.RIGHT, -0.22), Vector3(0, 0.3, -0.42)))
	mb.cbox(f, Vector3(-0.93, 0.0, 0.0), Vector3(0.93, 0.62, 0.2), 0.05, 0.5)
	mb.pop()
	mb.push(Transform3D(Basis(Vector3.UP, 0.3) * Basis(Vector3.BACK, 0.5), Vector3(-0.7, 0.62, 0.0)))
	mb.cbox("fabric_chair", Vector3(-0.17, -0.06, -0.17), Vector3(0.17, 0.06, 0.17), 0.05)
	mb.pop()
	mb.col(Vector3(-1.0, 0, -0.45), Vector3(1.0, 0.5, 0.42))
	mb.col(Vector3(-1.0, 0, -0.45), Vector3(1.0, 0.95, -0.15))


func _p_armchair(mb: MB, _root: Node3D) -> void:
	var w := "wood_mid"
	var f := "fabric_chair"
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.cyl(w, Vector3(0.28 * sx, 0, 0.26 * sz), Vector3(-0.05 * sx, 0.22, -0.05 * sz), 0.014, 0.022, 6)
	mb.box(w, Vector3(-0.3, 0.21, -0.28), Vector3(0.3, 0.27, 0.3), 0.4)
	mb.cbox(f, Vector3(-0.26, 0.27, -0.24), Vector3(0.26, 0.4, 0.31), 0.03)
	mb.push(Transform3D(Basis(Vector3.RIGHT, -0.26), Vector3(0, 0.27, -0.28)))
	mb.cbox(f, Vector3(-0.27, 0, 0), Vector3(0.27, 0.52, 0.11), 0.035)
	mb.pop()
	for s in [-1.0, 1.0]:
		mb.box(f, Vector3(0.26 * s, 0.24, -0.27), Vector3(0.32 * s, 0.5, 0.26), 0.3)
		mb.box(w, Vector3(0.25 * s, 0.5, -0.3), Vector3(0.345 * s, 0.53, 0.31), 0.4)
	mb.col(Vector3(-0.36, 0, -0.34), Vector3(0.36, 0.55, 0.33))
	mb.col(Vector3(-0.36, 0, -0.4), Vector3(0.36, 0.85, -0.2))


func _p_wall_unit(mb: MB, root: Node3D, tv_path: String) -> void:
	var wd := "wood_dark"
	mb.box(wd, Vector3(-1.4, 0.0, -0.22), Vector3(1.4, 0.08, 0.2), 0.6, 0.55)
	mb.box(wd, Vector3(-1.4, 0.08, -0.25), Vector3(1.4, 0.1, 0.25), 0.6)
	mb.box(wd, Vector3(-1.41, 2.16, -0.25), Vector3(1.41, 2.2, 0.265), 0.6)
	mb.box(wd, Vector3(-1.4, 0.1, -0.25), Vector3(1.4, 2.16, -0.23), 0.6, 0.6)
	for x in [-1.4, -0.8, 0.2, 0.8, 1.38]:
		mb.box(wd, Vector3(x, 0.1, -0.25), Vector3(x + 0.02, 2.16, 0.25), 0.6)
	# A: wardrobe section with a coat.
	mb.cyl("chrome", Vector3(-1.38, 1.9, 0.0), Vector3(0.58, 0, 0), 0.01, 0.01, 6)
	_coat(mb, Vector3(-1.15, 1.9, 0.0), "coat_brown", 0.2, 1.1)
	# B: TV niche and the glass cabinet of dishes.
	for y in [0.7, 1.35, 1.75]:
		mb.box(wd, Vector3(-0.78, y, -0.23), Vector3(0.2, y + 0.02, 0.24), 0.6)
	for i in 5:
		mb.cyl("enamel", Vector3(-0.68 + i * 0.18, 1.37, -0.02), Vector3(0, 0.07, 0), 0.03, 0.038, 8)
		mb.cyl("enamel", Vector3(-0.68 + i * 0.18, 1.37, 0.1), Vector3(0, 0.008, 0), 0.05, 0.05, 8)
	for i in 4:
		mb.cyl("enamel", Vector3(-0.66 + i * 0.24, 1.87, -0.16), Vector3(0, 0, 0.015), 0.1, 0.1, 10)
	for i in 6:
		mb.cyl("glass_dark", Vector3(-0.7 + i * 0.15, 1.77, 0.06), Vector3(0, 0.12, 0), 0.02, 0.03, 6)
	for x in [-0.8, -0.31, 0.18]:
		mb.box(wd, Vector3(x, 1.35, 0.23), Vector3(x + 0.03, 2.16, 0.255))
	for y in [1.35, 2.13]:
		mb.box(wd, Vector3(-0.8, y, 0.23), Vector3(0.2, y + 0.03, 0.255))
	# C: open book shelves.
	for y in [0.7, 1.1, 1.5, 1.9]:
		mb.box(wd, Vector3(0.22, y, -0.23), Vector3(0.8, y + 0.02, 0.24), 0.6)
	for y in [0.72, 1.12, 1.52, 1.92]:
		mb.box("books", Vector3(0.23, y, -0.18), Vector3(0.52, y + 0.25, 0.04))
		mb.box("books", Vector3(0.52, y, -0.18), Vector3(0.79, y + 0.21, 0.06))
	# D: linen shelves.
	for y in [0.6, 1.1, 1.6]:
		mb.box(wd, Vector3(0.82, y, -0.23), Vector3(1.38, y + 0.02, 0.24), 0.6)
		mb.cbox("pillow", Vector3(0.86, y + 0.02, -0.18), Vector3(1.32, y + 0.16, 0.16), 0.03)
	mb.col(Vector3(-1.41, 0, -0.25), Vector3(1.41, 2.2, 0.22))
	_hinged(root, "WardrobeDoorL", Vector3(-1.38, 0.1, 0.25), _leaf.bind(0.58, 2.05, 0.02, 1.0, wd, wd, wd, false, false),
			"cabinet", -100.0, "Мужское пальто на плечиках. Пахнет нафталином.")
	_hinged(root, "WardrobeDoorR", Vector3(1.38, 0.1, 0.25), _leaf.bind(0.56, 2.05, 0.02, -1.0, wd, wd, wd, false, false),
			"cabinet", 100.0, "Стопки постельного белья, пожелтевшего по сгибам.")
	_hinged(root, "LowerDoor", Vector3(0.22, 0.1, 0.25), _leaf.bind(0.56, 0.58, 0.02, 1.0, wd, wd, wd, false, false),
			"cabinet", -95.0, "Пустые банки и моток бечёвки.")
	_drawer(root, "DrawerTop", Vector3(-0.3, 0.4, 0.0), _drawer_box.bind(0.96, 0.29, 0.42, wd, 0.25), "papers",
			"Квитанции за квартиру. Последняя — за март 1991 года.", 0.28)
	_drawer(root, "DrawerBottom", Vector3(-0.3, 0.1, 0.0), _drawer_box.bind(0.96, 0.29, 0.42, wd, 0.25), "cutlery",
			"Мельхиоровые ложки, потемневшие от времени.", 0.28)
	_inst(root, tv_path, Vector3(-0.3, 0.72, -0.02), 0.0, "TV")
	_item(root, "Dishes", Vector3(-0.3, 1.75, 0.2), 0.0, _hitbox.bind(Vector3(0.95, 0.8, 0.04)), "Сервиз",
			"Сервиз «Мадонна». Чашки перевёрнуты донышками вверх, как будто их убрали навсегда.", false, "glass")
	_item(root, "Book", Vector3(0.66, 1.52, 0.12), 0.0, _p_book, "Книга",
			"«Как закалялась сталь». На форзаце: «Серёже, 1978».", true, "book")


func _p_book(mb: MB) -> void:
	mb.box("books", Vector3(-0.07, 0, -0.04), Vector3(0.07, 0.03, 0.06))
	mb.col(Vector3(-0.09, 0, -0.06), Vector3(0.09, 0.06, 0.08))


func _p_tv(mb: MB, root: Node3D) -> void:
	var w := "wood_mid"
	var pd := "plastic_dark"
	mb.cbox(w, Vector3(-0.3, 0.0, -0.1), Vector3(0.3, 0.48, 0.21), 0.015, 0.4)
	mb.push(Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, 0.24, -0.1)))
	mb.tbox(pd, Vector3.ZERO, 0.52, 0.42, 0.3, 0.24, 0.22, 0.8)
	mb.pop()
	mb.box(pd, Vector3(-0.28, 0.04, 0.21), Vector3(0.13, 0.46, 0.214))
	mb.box("coat", Vector3(0.145, 0.05, 0.21), Vector3(0.275, 0.2, 0.215))
	for y in [0.39, 0.3]:
		mb.cyl(pd, Vector3(0.21, y, 0.21), Vector3(0, 0, 0.03), 0.028, 0.025, 8)
		mb.box("chrome", Vector3(0.205, y + 0.005, 0.24), Vector3(0.215, y + 0.022, 0.242))
	for i in 4:
		mb.box("chrome", Vector3(0.15 + i * 0.03, 0.235, 0.21), Vector3(0.17 + i * 0.03, 0.255, 0.226))
	mb.cyl(pd, Vector3(0, 0.48, -0.02), Vector3(0, 0.03, 0), 0.04, 0.035, 8)
	for s in [-1.0, 1.0]:
		mb.cyl("chrome", Vector3(0.0, 0.51, -0.02), Vector3(0.26 * s, 0.1, -0.04), 0.004, 0.003, 4)
	mb.col(Vector3(-0.3, 0, -0.32), Vector3(0.3, 0.52, 0.23))
	# The screen: its own mesh, bulging like a tube face, so the script can switch it.
	var sm := MB.new()
	var gx := 6
	for j in gx:
		for i in gx:
			var u0 := float(i) / gx
			var u1 := float(i + 1) / gx
			var v0 := float(j) / gx
			var v1 := float(j + 1) / gx
			sm.quad("crt_off", _crt(u0, v0), _crt(u1, v0), _crt(u0, v1), _crt(u1, v1), Vector2(u0, 1 - v0),
					Vector2(u1, 1 - v0), Vector2(u0, 1 - v1), Vector2(u1, 1 - v1), 1.0, 1, 1)
	root.add_child(_mesh(sm, "Screen"))
	var glow := _light(root, "Glow", Vector3(0, 0.3, 0.8), 0.9, Color(0.55, 0.68, 1.0), 3.8)
	glow.omni_attenuation = 1.0
	var s := AudioStreamPlayer3D.new()
	s.name = "Sound"
	s.stream = load("res://assets/audio/tv_loop.mp3")
	s.bus = "Foley"
	s.volume_db = -22.0
	s.unit_size = 1.2
	s.max_distance = 10.0
	s.position = Vector3(0, 0.25, 0.1)
	root.add_child(s)


func _crt(u: float, v: float) -> Vector3:
	var nx := u * 2.0 - 1.0
	var ny := v * 2.0 - 1.0
	return Vector3(lerpf(-0.255, 0.105, u), lerpf(0.07, 0.43, v), 0.215 + 0.022 * (1.0 - nx * nx) * (1.0 - ny * ny))


func _p_coffee_table(mb: MB, root: Node3D) -> void:
	var wd := "wood_dark"
	mb.cbox(wd, Vector3(-0.45, 0.48, -0.27), Vector3(0.45, 0.52, 0.27), 0.01, 0.5)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.cyl(wd, Vector3(0.42 * sx, 0, 0.23 * sz), Vector3(-0.05 * sx, 0.48, -0.04 * sz), 0.014, 0.022, 6)
	mb.box(wd, Vector3(-0.38, 0.18, -0.2), Vector3(0.38, 0.2, 0.2), 0.5)
	mb.cyl("glass_dark", Vector3(0.22, 0.52, 0.05), Vector3(0, 0.025, 0), 0.07, 0.07, 8)
	for i in 3:
		mb.cyl("plastic_cream", Vector3(0.2 + i * 0.02, 0.545, 0.03 + i * 0.015), Vector3(0.04, 0.004, 0.01), 0.004, 0.004, 4)
	mb.cyl("enamel", Vector3(-0.25, 0.52, -0.08), Vector3(0, 0.08, 0), 0.035, 0.04, 8)
	mb.face("newspaper", Vector3(-0.3, 0.205, 0.15), Vector3(0.42, 0, 0), Vector3(0, 0, -0.3))
	mb.col(Vector3(-0.47, 0, -0.29), Vector3(0.47, 0.53, 0.29))
	_item(root, "TVGuide", Vector3(0.0, 0.52, 0.06), 0.3, _p_paper.bind("newspaper"), "Программа передач",
			"Программа телепередач на неделю. Обведено карандашом: «Спокойной ночи, малыши!».", true, "paper")


func _p_paper(mb: MB, mat: String) -> void:
	mb.face(mat, Vector3(-0.1, 0.003, 0.14), Vector3(0.2, 0, 0), Vector3(0, 0, -0.28))
	mb.col(Vector3(-0.11, 0, -0.15), Vector3(0.11, 0.03, 0.15))


func _p_carpet_floor(mb: MB, _root: Node3D) -> void:
	mb.box("carpet_floor", Vector3(-1.2, 0, -1.55), Vector3(1.2, 0.01, 1.55))


func _p_carpet_wall(mb: MB, _root: Node3D, w: float, h: float) -> void:
	mb.box("carpet_wall", Vector3(-w * 0.5, 0, 0), Vector3(w * 0.5, h, 0.012))
	mb.col(Vector3(-w * 0.5, 0, 0), Vector3(w * 0.5, h, 0.03))


func _lamp_light(root: Node3D, pos: Vector3, reach: float, color := Color(1.0, 0.76, 0.48)) -> void:
	var l := _light(root, "Light", pos, 1.0, color, reach)
	l.omni_attenuation = 1.1


func _p_chandelier(mb: MB, root: Node3D) -> void:
	mb.cyl("brass", Vector3(0, -0.03, 0), Vector3(0, 0.03, 0), 0.07, 0.07, 8)
	mb.cyl("brass", Vector3(0, -0.4, 0), Vector3(0, 0.37, 0), 0.008, 0.008, 4)
	mb.cyl("brass", Vector3(0, -0.47, 0), Vector3(0, 0.07, 0), 0.03, 0.05, 8)
	var bm := MB.new()
	for i in 3:
		var a := TAU * i / 3.0
		var d := Vector3(cos(a), 0, sin(a))
		mb.cyl("brass", Vector3(0, -0.44, 0), d * 0.22 + Vector3(0, 0.06, 0), 0.007, 0.007, 4)
		var c := d * 0.22 + Vector3(0, -0.36, 0)
		mb.cyl("shade_glass", c, Vector3(0, -0.14, 0), 0.04, 0.1, 8, false)
		bm.tbox("bulb_off", c + Vector3(0, -0.11, 0), 0.04, 0.04, 0.03, 0.03, 0.07)
	root.add_child(_mesh(bm, "Bulb"))
	_lamp_light(root, Vector3(0, -0.55, 0), 5.5)


# ---------------------------------------------------------------- windows

func _p_window(mb: MB, root: Node3D, w: float, h: float, t: float) -> void:
	mb.face("plaster_grey", Vector3(-w * 0.5, 0, 0), Vector3(0, 0, -t), Vector3(0, h, 0), 0.5, 0.75)
	mb.face("plaster_grey", Vector3(w * 0.5, 0, -t), Vector3(0, 0, t), Vector3(0, h, 0), 0.5, 0.75)
	mb.face("plaster_grey", Vector3(-w * 0.5, h, -t), Vector3(w, 0, 0), Vector3(0, 0, t), 0.5, 0.6)
	mb.face("plaster_grey", Vector3(-w * 0.5, 0, 0), Vector3(w, 0, 0), Vector3(0, 0, -t), 0.5, 0.8)
	mb.face("window", Vector3(-w * 0.5, 0, -t * 0.7), Vector3(w, 0, 0), Vector3(0, h, 0))
	var fp := "frame_paint"
	for z in [-t * 0.6, -t * 0.25]:
		var zz: float = z
		mb.box(fp, Vector3(-w * 0.5, 0, zz - 0.04), Vector3(-w * 0.5 + 0.05, h, zz))
		mb.box(fp, Vector3(w * 0.5 - 0.05, 0, zz - 0.04), Vector3(w * 0.5, h, zz))
		mb.box(fp, Vector3(-w * 0.5, h - 0.05, zz - 0.04), Vector3(w * 0.5, h, zz))
		mb.box(fp, Vector3(-w * 0.5, 0, zz - 0.04), Vector3(w * 0.5, 0.05, zz))
		mb.box(fp, Vector3(-0.025, 0, zz - 0.04), Vector3(0.025, h, zz))
		mb.box(fp, Vector3(-w * 0.5, h * 0.72, zz - 0.04), Vector3(0, h * 0.72 + 0.04, zz))
	mb.box(fp, Vector3(-w * 0.5 - 0.06, -0.04, -t * 0.22), Vector3(w * 0.5 + 0.06, 0.0, 0.16))
	mb.col(Vector3(-w * 0.5 - 0.06, -0.05, -t), Vector3(w * 0.5 + 0.06, 0.0, 0.16))
	_item(root, "Glass", Vector3(0, h * 0.5, -t * 0.3), 0.0, _hitbox.bind(Vector3(w, h, 0.04)), "Окно",
			"За окном соседняя пятиэтажка. В нескольких окнах горит свет. Ни одного силуэта.", false, "glass")


func _p_curtains(mb: MB, _root: Node3D, w: float, drop: float, drapes: bool) -> void:
	mb.cyl("brass", Vector3(-w * 0.5 - 0.35, 0, 0.22), Vector3(w + 0.7, 0, 0), 0.012, 0.012, 6)
	for s in [-1.0, 1.0]:
		mb.box("brass", Vector3((w * 0.5 + 0.3) * s - 0.01, -0.01, 0), Vector3((w * 0.5 + 0.3) * s + 0.01, 0.01, 0.22))
	mb.folds("tulle", -w * 0.5 - 0.15, w * 0.5 + 0.15, -drop, -0.02, 0.18, int(w * 6), 0.03, 0.45)
	if drapes:
		mb.folds("drape", -w * 0.5 - 0.4, -w * 0.5 + 0.05, -drop - 0.02, -0.02, 0.23, 3, 0.05, 0.5)
		mb.folds("drape", w * 0.5 - 0.05, w * 0.5 + 0.4, -drop - 0.02, -0.02, 0.23, 3, 0.05, 0.5)


func _p_radiator(mb: MB, _root: Node3D, sections: int) -> void:
	var w := 0.085
	var total := sections * w
	for i in sections:
		var x := -total * 0.5 + i * w
		mb.cbox("iron_paint", Vector3(x + 0.006, 0.16, 0.03), Vector3(x + w - 0.006, 0.72, 0.13), 0.02, 0.3)
	mb.box("iron_paint", Vector3(-total * 0.5, 0.2, 0.06), Vector3(total * 0.5, 0.24, 0.1), 0.3, 0.7)
	mb.box("iron_paint", Vector3(-total * 0.5, 0.64, 0.06), Vector3(total * 0.5, 0.68, 0.1), 0.3, 0.7)
	var px := -total * 0.5 - 0.14
	mb.cyl("iron_paint", Vector3(px, 0.66, 0.08), Vector3(0.14, 0, 0), 0.016, 0.016, 6)
	mb.cyl("iron_paint", Vector3(px, 0.22, 0.08), Vector3(0.14, 0, 0), 0.016, 0.016, 6)
	mb.cyl("iron_paint", Vector3(px, 0.0, 0.08), Vector3(0, H, 0), 0.018, 0.018, 6)
	mb.box("chrome", Vector3(px + 0.05, 0.63, 0.06), Vector3(px + 0.08, 0.69, 0.1))       # valve
	mb.col(Vector3(-total * 0.5 - 0.2, 0, 0), Vector3(total * 0.5, 0.74, 0.14))


func _p_plant(mb: MB, _root: Node3D) -> void:
	mb.tbox("lampshade", Vector3.ZERO, 0.1, 0.1, 0.15, 0.15, 0.13, 0.8)
	mb.box("soil", Vector3(-0.07, 0.115, -0.07), Vector3(0.07, 0.125, 0.07))
	for i in 7:
		var a := TAU * i / 7.0
		mb.push(Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -0.5 - (i % 3) * 0.25), Vector3(0, 0.12, 0)))
		mb.quad("leaf", Vector3(-0.04, 0, 0), Vector3(0.04, 0, 0), Vector3(-0.06, 0.2, 0), Vector3(0.06, 0.2, 0),
				Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0), 0.6 + 0.1 * (i % 3), 1, 1)
		mb.pop()
	mb.col(Vector3(-0.09, 0, -0.09), Vector3(0.09, 0.3, 0.09))


# ---------------------------------------------------------------- bedroom

func _p_bed(mb: MB, _root: Node3D) -> void:
	var w := "wood_mid"
	mb.box(w, Vector3(-0.82, 0, 0), Vector3(0.82, 1.0, 0.05), 0.5)
	mb.box("wood_dark", Vector3(-0.68, 0.45, 0.05), Vector3(0.68, 0.88, 0.056), 0.5)
	mb.cyl(w, Vector3(-0.84, 1.0, 0.025), Vector3(1.68, 0, 0), 0.03, 0.03, 6)
	mb.box(w, Vector3(-0.82, 0, 1.95), Vector3(0.82, 0.58, 2.0), 0.5)
	mb.cyl(w, Vector3(-0.84, 0.58, 1.975), Vector3(1.68, 0, 0), 0.028, 0.028, 6)
	for s in [-1.0, 1.0]:
		mb.box(w, Vector3(0.78 * s, 0.16, 0.05), Vector3(0.82 * s, 0.32, 1.95), 0.5)
	mb.cbox("pillow", Vector3(-0.78, 0.3, 0.06), Vector3(0.78, 0.46, 1.94), 0.04, 0.5)
	mb.cbox("bedspread", Vector3(-0.8, 0.46, 0.4), Vector3(0.8, 0.5, 1.93), 0.02, 0.7)
	for s in [-1.0, 1.0]:
		mb.box("bedspread", Vector3(0.8 * s, 0.22, 0.4), Vector3(0.815 * s, 0.49, 1.93), 0.7)
	mb.box("bedspread", Vector3(-0.8, 0.22, 1.92), Vector3(0.8, 0.49, 1.935), 0.7)
	for s in [-1.0, 1.0]:
		mb.cbox("pillow", Vector3(0.05 * s, 0.46, 0.08), Vector3(0.72 * s, 0.6, 0.42), 0.06)
	mb.col(Vector3(-0.83, 0, 0), Vector3(0.83, 0.6, 2.0))
	mb.col(Vector3(-0.83, 0, 0), Vector3(0.83, 1.0, 0.06))


func _p_wardrobe(mb: MB, root: Node3D) -> void:
	var w := "wood_mid"
	mb.box(w, Vector3(-0.6, 0.06, 0), Vector3(0.6, 1.98, 0.02), 0.5, 0.6)
	for s in [-1.0, 1.0]:
		mb.box(w, Vector3(0.58 * s, 0, 0), Vector3(0.6 * s, 2.0, 0.58), 0.5)
	mb.box(w, Vector3(-0.62, 1.98, -0.01), Vector3(0.62, 2.06, 0.61), 0.5)
	mb.box(w, Vector3(-0.6, 0.06, 0), Vector3(0.6, 0.08, 0.58), 0.5)
	mb.box("wood_dark", Vector3(-0.58, 0, 0.02), Vector3(0.58, 0.06, 0.55), 0.5, 0.6)
	mb.box(w, Vector3(-0.58, 1.65, 0.02), Vector3(0.58, 1.67, 0.56), 0.5)
	mb.cyl("chrome", Vector3(-0.58, 1.55, 0.3), Vector3(1.16, 0, 0), 0.01, 0.01, 6)
	_coat(mb, Vector3(-0.34, 1.55, 0.25), "coat", 0.05, 1.05)
	_coat(mb, Vector3(0.0, 1.55, 0.35), "coat_brown", -0.08, 0.85)
	_coat(mb, Vector3(0.33, 1.55, 0.27), "drape", 0.1, 1.2)
	mb.cyl("lampshade", Vector3(0.25, 1.67, 0.3), Vector3(0, 0.18, 0), 0.15, 0.15, 10)
	mb.cbox("leather", Vector3(-0.5, 1.67, 0.1), Vector3(-0.05, 1.82, 0.45), 0.02)
	mb.col(Vector3(-0.62, 0, 0), Vector3(0.62, 2.06, 0.56))
	_hinged(root, "DoorL", Vector3(-0.58, 0.08, 0.58), _leaf.bind(0.58, 1.88, 0.02, 1.0, w, w, w, false, false),
			"cabinet", -105.0, "Платья на плечиках. В кармане пиджака — трамвайный билет и ключ от почтового ящика.")
	_hinged(root, "DoorR", Vector3(0.58, 0.08, 0.58), _leaf.bind(0.58, 1.88, 0.02, -1.0, w, w, w, false, false),
			"cabinet", 105.0, "Пальто и шапка-ушанка на полке. На шапке моль.")


func _p_nightstand(mb: MB, root: Node3D, lamp_path: String) -> void:
	var w := "wood_mid"
	mb.cbox(w, Vector3(-0.23, 0.53, -0.01), Vector3(0.23, 0.56, 0.42), 0.008, 0.4)
	for s in [-1.0, 1.0]:
		mb.box(w, Vector3(0.21 * s, 0.04, 0), Vector3(0.23 * s, 0.53, 0.41), 0.4)
	mb.box(w, Vector3(-0.21, 0.04, 0), Vector3(0.21, 0.53, 0.02), 0.4, 0.6)
	mb.box(w, Vector3(-0.21, 0.04, 0), Vector3(0.21, 0.06, 0.41), 0.4)
	mb.box(w, Vector3(-0.21, 0.36, 0.02), Vector3(0.21, 0.375, 0.41), 0.4)
	mb.box("wood_dark", Vector3(-0.2, 0, 0.02), Vector3(0.2, 0.04, 0.38), 0.4, 0.6)
	mb.col(Vector3(-0.23, 0, 0), Vector3(0.23, 0.56, 0.38))
	_drawer(root, "Drawer", Vector3(0, 0.375, 0), _drawer_box.bind(0.41, 0.15, 0.34, w, 0.41), "things",
			"Лекарства в коробочках, пожелтевший рецепт, очки в футляре.", 0.22)
	_hinged(root, "Door", Vector3(-0.205, 0.06, 0.41), _leaf.bind(0.41, 0.3, 0.018, 1.0, w, w, w, false, false),
			"cabinet", -100.0, "Стопка журналов «Работница» за восьмидесятые.")
	var lamp := _inst(root, lamp_path, Vector3(0.09, 0.56, 0.22), 0.0, "DeskLamp", {"on": true})
	lamp.add_to_group("lamp_bedside", true)
	_item(root, "Clock", Vector3(-0.12, 0.56, 0.28), 0.4, _p_alarm_clock, "Будильник",
			"Будильник «Слава». Стрелки стоят на четверть четвёртого.", false, "metal")
	_item(root, "Photo", Vector3(-0.1, 0.56, 0.1), 0.2, _p_photo_frame, "Фотография",
			"Мужчина, женщина и мальчик у моря. Подпись на обороте: «Сочи, 1984».", true, "wood")


func _p_alarm_clock(mb: MB) -> void:
	mb.cyl("enamel", Vector3(0, 0.05, -0.02), Vector3(0, 0, 0.04), 0.05, 0.05, 10)
	mb.disc("plastic_cream", Vector3(0, 0.05, 0.021), Vector3(0.042, 0, 0), Vector3(0, 0.042, 0), 10)
	mb.box("black", Vector3(-0.002, 0.05, 0.022), Vector3(0.002, 0.085, 0.024))
	mb.box("black", Vector3(-0.002, 0.048, 0.022), Vector3(0.025, 0.052, 0.024))
	for s in [-1.0, 1.0]:
		mb.cyl("chrome", Vector3(0.03 * s, 0.095, 0), Vector3(0, 0.015, 0), 0.015, 0.012, 6)
		mb.cyl("chrome", Vector3(0.03 * s, 0.0, 0.0), Vector3(0, 0.012, 0), 0.006, 0.006, 4)
	mb.col(Vector3(-0.06, 0, -0.04), Vector3(0.06, 0.12, 0.04))


func _p_photo_frame(mb: MB) -> void:
	mb.push(Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3.ZERO))
	mb.box("wood_dark", Vector3(-0.07, 0, -0.008), Vector3(0.07, 0.18, 0.0))
	mb.face("photo", Vector3(-0.055, 0.015, 0.001), Vector3(0.11, 0, 0), Vector3(0, 0.15, 0))
	mb.pop()
	mb.col(Vector3(-0.08, 0, -0.06), Vector3(0.08, 0.19, 0.04))


func _p_desk_lamp(mb: MB, root: Node3D) -> void:
	mb.cyl("plastic_cream", Vector3.ZERO, Vector3(0, 0.025, 0), 0.075, 0.065, 10)
	mb.box("chrome", Vector3(0.04, 0.025, -0.01), Vector3(0.06, 0.04, 0.01))
	mb.cyl("brass", Vector3(0, 0.025, 0), Vector3(0, 0.22, 0), 0.008, 0.008, 6)
	mb.cyl("shade_lamp", Vector3(0, 0.2, 0), Vector3(0, 0.16, 0), 0.13, 0.07, 10, false)
	var bm := MB.new()
	bm.tbox("bulb_off", Vector3(0, 0.22, 0), 0.04, 0.04, 0.035, 0.035, 0.06)
	root.add_child(_mesh(bm, "Bulb"))
	_lamp_light(root, Vector3(0, 0.25, 0.05), 3.2)
	mb.col(Vector3(-0.13, 0, -0.13), Vector3(0.13, 0.36, 0.13))


func _p_mirror_oval(mb: MB, _root: Node3D) -> void:
	mb.disc("mirror", Vector3(0, 0, 0.02), Vector3(0.21, 0, 0), Vector3(0, 0.29, 0), 14)
	mb.ring("wood_dark", Vector3(0, 0, 0.022), Vector3(0.25, 0, 0), Vector3(0, 0.33, 0), 0.86, 14)
	mb.cyl("wood_dark", Vector3(0, 0, 0), Vector3(0, 0, 0.02), 0.25, 0.25, 14, false, 0.7)
	mb.col(Vector3(-0.25, -0.33, 0), Vector3(0.25, 0.33, 0.04))


func _p_stool(mb: MB, _root: Node3D, clothes: bool) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.cyl("wood_light", Vector3(0.15 * sx, 0, 0.15 * sz), Vector3(-0.03 * sx, 0.42, -0.03 * sz), 0.016, 0.018, 4)
	mb.box("wood_light", Vector3(-0.13, 0.15, -0.13), Vector3(0.13, 0.17, -0.11))
	mb.box("wood_light", Vector3(-0.13, 0.15, 0.11), Vector3(0.13, 0.17, 0.13))
	mb.cbox("wood_light", Vector3(-0.16, 0.42, -0.16), Vector3(0.16, 0.45, 0.16), 0.01)
	if clothes:
		mb.cbox("coat", Vector3(-0.15, 0.45, -0.12), Vector3(0.15, 0.5, 0.13), 0.02)
		mb.box("coat", Vector3(0.15, 0.25, -0.1), Vector3(0.16, 0.48, 0.1))
	mb.col(Vector3(-0.17, 0, -0.17), Vector3(0.17, 0.46, 0.17))


func _p_slippers(mb: MB, _root: Node3D) -> void:
	for s in [-1.0, 1.0]:
		mb.push(Transform3D(Basis(Vector3.UP, 0.12 * s), Vector3(0.07 * s, 0, 0)))
		mb.tbox("fabric_chair", Vector3.ZERO, 0.09, 0.26, 0.08, 0.25, 0.025)
		mb.tbox("fabric_chair", Vector3(0, 0.025, 0.05), 0.09, 0.13, 0.08, 0.1, 0.04, 0.8)
		mb.pop()
	mb.col(Vector3(-0.15, 0, -0.14), Vector3(0.15, 0.07, 0.14))


func _p_pendant(mb: MB, root: Node3D) -> void:
	mb.cyl("rubber", Vector3(0, -0.3, 0), Vector3(0, 0.3, 0), 0.004, 0.004, 4)
	mb.cyl("chrome", Vector3(0, -0.02, 0), Vector3(0, 0.02, 0), 0.04, 0.04, 6)
	mb.cyl("shade_lamp", Vector3(0, -0.55, 0), Vector3(0, 0.25, 0), 0.26, 0.09, 12, false)
	var bm := MB.new()
	bm.tbox("bulb_off", Vector3(0, -0.47, 0), 0.05, 0.05, 0.04, 0.04, 0.08)
	root.add_child(_mesh(bm, "Bulb"))
	_lamp_light(root, Vector3(0, -0.6, 0), 4.8)


# ---------------------------------------------------------------- kitchen

func _p_stove(mb: MB, root: Node3D) -> void:
	var e := "enamel"
	mb.box(e, Vector3(-0.25, 0.05, 0), Vector3(0.25, 0.85, 0.55))
	mb.box(e, Vector3(-0.25, 0.85, 0), Vector3(0.25, 0.97, 0.03))
	for x in [-0.12, 0.12]:
		for z in [0.16, 0.4]:
			var c := Vector3(x, 0.85, z)
			mb.cyl("aluminium", c, Vector3(0, 0.012, 0), 0.05, 0.045, 8)
			mb.box("rubber", c + Vector3(-0.1, 0.012, -0.008), c + Vector3(0.1, 0.03, 0.008))
			mb.box("rubber", c + Vector3(-0.008, 0.012, -0.1), c + Vector3(0.008, 0.03, 0.1))
	mb.box(e, Vector3(-0.25, 0.7, 0.55), Vector3(0.25, 0.8, 0.57), 0.0, 0.9)
	for i in 5:
		mb.cyl("plastic_dark", Vector3(-0.18 + i * 0.09, 0.75, 0.57), Vector3(0, 0, 0.03), 0.022, 0.02, 8)
	for sx in [-1.0, 1.0]:
		for z in [0.05, 0.5]:
			mb.cyl("rubber", Vector3(0.22 * sx, 0, z), Vector3(0, 0.05, 0), 0.02, 0.02, 4)
	mb.box("black", Vector3(-0.22, 0.12, 0.12), Vector3(0.22, 0.66, 0.548))           # the dark oven
	# Kettle and a pot.
	mb.cyl("enamel", Vector3(-0.12, 0.88, 0.4), Vector3(0, 0.14, 0), 0.08, 0.06, 8)
	mb.cyl("enamel", Vector3(-0.06, 0.93, 0.4), Vector3(0.09, 0.07, 0), 0.015, 0.008, 4)
	mb.box("plastic_dark", Vector3(-0.17, 1.04, 0.39), Vector3(-0.07, 1.07, 0.41))
	mb.cyl("aluminium", Vector3(0.12, 0.88, 0.16), Vector3(0, 0.13, 0), 0.1, 0.1, 10)
	for s in [-1.0, 1.0]:
		mb.box("aluminium", Vector3(0.12 + 0.1 * s, 0.98, 0.15), Vector3(0.12 + 0.13 * s, 1.0, 0.17))
	mb.col(Vector3(-0.25, 0, 0), Vector3(0.25, 0.9, 0.55))
	_hinged(root, "Oven", Vector3(0, 0.1, 0.55), _p_oven_door, "oven", 80.0,
			"Духовка. Внутри противень с чёрным нагаром.", "x")
	_item(root, "Matches", Vector3(0.14, 0.88, 0.42), 0.4, _p_matches, "Спички",
			"Коробок спичек «Гигант». Осталось три спички.", true, "small")


func _p_oven_door(mb: MB) -> void:
	mb.box("enamel", Vector3(-0.23, 0.0, -0.02), Vector3(0.23, 0.58, 0.0))
	mb.box("glass_dark", Vector3(-0.13, 0.22, 0.0), Vector3(0.13, 0.45, 0.004))
	mb.cyl("chrome", Vector3(-0.17, 0.53, 0.04), Vector3(0.34, 0, 0), 0.008, 0.008, 6)
	for s in [-1.0, 1.0]:
		mb.box("chrome", Vector3(0.16 * s - 0.006, 0.525, 0.0), Vector3(0.16 * s + 0.006, 0.535, 0.04))
	mb.col(Vector3(-0.23, 0, -0.02), Vector3(0.23, 0.58, 0.05))


func _p_matches(mb: MB) -> void:
	mb.box("lampshade", Vector3(-0.025, 0, -0.035), Vector3(0.025, 0.015, 0.035))
	mb.col(Vector3(-0.05, 0, -0.05), Vector3(0.05, 0.05, 0.05))


func _cabinet_body(mb: MB, w: float, h: float, d: float, mat: String) -> void:
	for s in [-1.0, 1.0]:
		mb.box(mat, Vector3((w * 0.5 - 0.018) * s, 0.06, 0), Vector3(w * 0.5 * s, h, d), 0.4)
	mb.box(mat, Vector3(-w * 0.5, 0.06, 0), Vector3(w * 0.5, h, 0.015), 0.4, 0.6)
	mb.box(mat, Vector3(-w * 0.5, 0.06, 0), Vector3(w * 0.5, 0.08, d), 0.4, 0.7)
	mb.box("rubber", Vector3(-w * 0.5 + 0.02, 0, 0.02), Vector3(w * 0.5 - 0.02, 0.06, d - 0.06), 0.4)
	mb.ibox("wood_light", Vector3(-w * 0.5 + 0.018, 0.08, 0.015), Vector3(w * 0.5 - 0.018, h, d), 0.0, 0.45, "s")


func _p_sink_cab(mb: MB, root: Node3D) -> void:
	var c := "plastic_cream"
	_cabinet_body(mb, 0.6, 0.82, 0.58, c)
	mb.cyl("enamel", Vector3(0.12, 0.08, 0.25), Vector3(0, 0.25, 0), 0.1, 0.12, 8, true, 0.8)       # a bucket inside
	mb.cyl("pipe_paint", Vector3(0, 0.3, 0.2), Vector3(0, 0.45, 0), 0.02, 0.02, 6)
	# Steel top with a basin.
	var y := 0.85
	mb.box("chrome", Vector3(-0.3, 0.82, 0), Vector3(0.3, y, 0.6), 0.0, 1.0, "u")
	var bx := 0.2
	var bz0 := 0.12
	var bz1 := 0.48
	mb.face("chrome", Vector3(-0.3, y, 0.6), Vector3(0.6, 0, 0), Vector3(0, 0, -0.12))
	mb.face("chrome", Vector3(-0.3, y, bz0), Vector3(0.6, 0, 0), Vector3(0, 0, -bz0))
	mb.face("chrome", Vector3(-0.3, y, bz1), Vector3(0.1, 0, 0), Vector3(0, 0, bz0 - bz1))
	mb.face("chrome", Vector3(bx, y, bz1), Vector3(0.1, 0, 0), Vector3(0, 0, bz0 - bz1))
	mb.ibox("aluminium", Vector3(-bx, y - 0.16, bz0), Vector3(bx, y, bz1), 0.0, 0.6, "u")
	mb.cyl("black", Vector3(0, y - 0.159, 0.3), Vector3(0, 0.002, 0), 0.025, 0.025, 6)
	# Tap from the wall.
	mb.cyl("chrome", Vector3(0, y, 0.05), Vector3(0, 0.16, 0), 0.012, 0.012, 6)
	mb.cyl("chrome", Vector3(0, y + 0.15, 0.05), Vector3(0, -0.03, 0.18), 0.01, 0.008, 6)
	for s in [-1.0, 1.0]:
		mb.cyl("chrome", Vector3(0.05 * s, y + 0.1, 0.0), Vector3(0, 0, 0.06), 0.008, 0.008, 4)
		mb.box("chrome", Vector3(0.05 * s - 0.025, y + 0.095, 0.055), Vector3(0.05 * s + 0.025, y + 0.105, 0.065))
	mb.col(Vector3(-0.3, 0, 0), Vector3(0.3, 0.86, 0.6))
	_hinged(root, "DoorL", Vector3(-0.29, 0.08, 0.6), _leaf.bind(0.285, 0.72, 0.018, 1.0, c, c, c, false, false),
			"cabinet", -95.0, "Под мойкой — ведро и сифон, обмотанный изолентой.")
	_hinged(root, "DoorR", Vector3(0.29, 0.08, 0.6), _leaf.bind(0.285, 0.72, 0.018, -1.0, c, c, c, false, false),
			"cabinet", 95.0, "Пачки соды и хозяйственное мыло.")


func _p_counter_cab(mb: MB, root: Node3D) -> void:
	var c := "plastic_cream"
	_cabinet_body(mb, 0.6, 0.82, 0.58, c)
	mb.box(c, Vector3(-0.282, 0.62, 0.015), Vector3(0.282, 0.635, 0.58), 0.4)
	mb.box("wood_light", Vector3(-0.31, 0.82, 0), Vector3(0.31, 0.86, 0.62), 0.5)
	mb.box("wood_light", Vector3(-0.18, 0.86, 0.15), Vector3(0.12, 0.88, 0.4))                 # bread board
	mb.cyl("glass_dark", Vector3(0.2, 0.86, 0.12), Vector3(0, 0.16, 0), 0.05, 0.05, 8)        # a jar
	mb.cyl("aluminium", Vector3(0.2, 1.02, 0.12), Vector3(0, 0.015, 0), 0.052, 0.052, 8)
	mb.col(Vector3(-0.31, 0, 0), Vector3(0.31, 0.88, 0.6))
	_drawer(root, "Drawer", Vector3(0, 0.64, 0), _drawer_box.bind(0.56, 0.17, 0.5, c, 0.6), "cutlery",
			"Вилки, половник, штопор. На дне — пожелтевший рецепт пирога.", 0.3)
	_hinged(root, "Door", Vector3(-0.28, 0.08, 0.6), _leaf.bind(0.56, 0.53, 0.018, 1.0, c, c, c, false, false),
			"cabinet", -95.0, "Кастрюли, вставленные одна в другую.")


func _p_wall_cab(mb: MB, root: Node3D) -> void:
	var c := "plastic_cream"
	for s in [-1.0, 1.0]:
		mb.box(c, Vector3(0.282 * s, 0, 0), Vector3(0.3 * s, 0.6, 0.3), 0.4)
	mb.box(c, Vector3(-0.3, 0, 0), Vector3(0.3, 0.018, 0.3), 0.4)
	mb.box(c, Vector3(-0.3, 0.582, 0), Vector3(0.3, 0.6, 0.3), 0.4)
	mb.ibox("wood_light", Vector3(-0.282, 0.018, 0.0), Vector3(0.282, 0.582, 0.3), 0.0, 0.45, "s")
	mb.box(c, Vector3(-0.282, 0.29, 0.01), Vector3(0.282, 0.305, 0.29), 0.4)
	for i in 4:
		mb.cyl("enamel", Vector3(-0.2 + i * 0.03, 0.12, 0.15), Vector3(0, 0, 0.012), 0.09, 0.09, 10)
	for i in 3:
		mb.cyl("glass_dark", Vector3(0.05 + i * 0.08, 0.305, 0.15), Vector3(0, 0.12, 0), 0.03, 0.03, 6)
	mb.col(Vector3(-0.3, 0, 0), Vector3(0.3, 0.6, 0.29))
	_hinged(root, "Door", Vector3(-0.29, 0.005, 0.3), _leaf.bind(0.58, 0.59, 0.018, 1.0, c, c, c, false, false),
			"cabinet", -100.0, "Тарелки с отбитыми краями. Пачка соли превратилась в камень.")


func _p_fridge(mb: MB, root: Node3D) -> void:
	var e := "enamel"
	mb.box(e, Vector3(-0.3, 0.06, 0), Vector3(0.3, 1.4, 0.56), 0.0, 1.0, "s")
	mb.cyl(e, Vector3(-0.3, 1.4, 0.06), Vector3(0.6, 0, 0), 0.06, 0.06, 6, false)              # rounded top edges
	mb.cyl(e, Vector3(-0.3, 1.4, 0.5), Vector3(0.6, 0, 0), 0.06, 0.06, 6, false)
	mb.box(e, Vector3(-0.3, 1.4, 0.06), Vector3(0.3, 1.46, 0.5))
	for s in [-1.0, 1.0]:
		mb.box(e, Vector3(0.27 * s, 0.06, 0.5), Vector3(0.3 * s, 1.4, 0.56))
	mb.box(e, Vector3(-0.27, 0.06, 0.5), Vector3(0.27, 0.12, 0.56))
	mb.box(e, Vector3(-0.27, 1.34, 0.5), Vector3(0.27, 1.4, 0.56))
	mb.ibox("enamel", Vector3(-0.27, 0.12, 0.03), Vector3(0.27, 1.34, 0.56), 0.0, 0.55, "s")
	mb.box("aluminium", Vector3(-0.22, 1.1, 0.06), Vector3(0.22, 1.32, 0.42), 0.0, 0.8)        # freezer box
	for y in [0.45, 0.8]:
		mb.box("chrome", Vector3(-0.27, y, 0.04), Vector3(0.27, y + 0.01, 0.5))
	mb.cyl("glass_dark", Vector3(-0.1, 0.81, 0.25), Vector3(0, 0.18, 0), 0.06, 0.06, 8)
	mb.cyl("aluminium", Vector3(-0.1, 0.99, 0.25), Vector3(0, 0.02, 0), 0.062, 0.062, 8)
	for sx in [-1.0, 1.0]:
		mb.cyl("rubber", Vector3(0.25 * sx, 0, 0.45), Vector3(0, 0.06, 0), 0.02, 0.02, 4)
	mb.col(Vector3(-0.3, 0, 0), Vector3(0.3, 1.46, 0.55))
	_hinged(root, "Door", Vector3(0.3, 0.08, 0.56), _p_fridge_door, "fridge", 105.0,
			"Пусто. Банка с чем-то тёмным и запах ржавчины.", "y", 0.0, 0.7)


func _p_fridge_door(mb: MB) -> void:
	mb.cbox("enamel", Vector3(-0.6, 0.0, 0.0), Vector3(0.0, 1.36, 0.06), 0.03)
	mb.box("rubber", Vector3(-0.58, 0.02, -0.005), Vector3(-0.02, 1.34, 0.0))
	mb.box("chrome", Vector3(-0.57, 0.85, 0.06), Vector3(-0.55, 1.05, 0.09))
	mb.box("chrome", Vector3(-0.42, 1.22, 0.06), Vector3(-0.18, 1.27, 0.065))
	mb.col(Vector3(-0.6, 0, -0.01), Vector3(0, 1.36, 0.09))


func _p_kitchen_table(mb: MB, root: Node3D) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.tbox("wood_light", Vector3(0.3 * sx, 0, 0.25 * sz), 0.035, 0.035, 0.045, 0.045, 0.72)
	mb.box("wood_light", Vector3(-0.34, 0.62, -0.28), Vector3(0.34, 0.72, 0.28), 0.4, 0.8)
	mb.box("wood_light", Vector3(-0.36, 0.72, -0.31), Vector3(0.36, 0.75, 0.31), 0.4)
	mb.box("oilcloth", Vector3(-0.37, 0.75, -0.32), Vector3(0.37, 0.755, 0.32), 0.3)
	for s in [-1.0, 1.0]:
		mb.box("oilcloth", Vector3(0.37 * s, 0.67, -0.32), Vector3(0.373 * s, 0.755, 0.32), 0.3, 0.8)
		mb.box("oilcloth", Vector3(-0.37, 0.67, 0.32 * s), Vector3(0.37, 0.755, 0.323 * s), 0.3, 0.8)
	mb.cyl("enamel", Vector3(0.15, 0.755, -0.12), Vector3(0, 0.09, 0), 0.04, 0.045, 8)
	mb.box("enamel", Vector3(0.19, 0.78, -0.125), Vector3(0.21, 0.83, -0.115))
	mb.cyl("glass_dark", Vector3(-0.2, 0.755, -0.18), Vector3(0, 0.07, 0), 0.02, 0.02, 6)
	mb.col(Vector3(-0.37, 0, -0.32), Vector3(0.37, 0.76, 0.32))
	_item(root, "Newspaper", Vector3(-0.05, 0.756, 0.06), 0.25, _p_paper.bind("newspaper"), "Газета",
			"«Правда», 19 августа 1991 года. Кроссворд разгадан наполовину.", true, "paper")


func _p_dish_rack(mb: MB, _root: Node3D) -> void:
	for x in [-0.25, 0.25]:
		mb.box("chrome", Vector3(x - 0.005, 0, 0), Vector3(x + 0.005, 0.4, 0.25))
	for y in [0.02, 0.35]:
		for z in [0.05, 0.22]:
			mb.cyl("chrome", Vector3(-0.25, y, z), Vector3(0.5, 0, 0), 0.004, 0.004, 4)
	for i in 3:
		mb.cyl("enamel", Vector3(-0.15 + i * 0.05, 0.13, 0.13), Vector3(0.01, 0, 0), 0.11, 0.11, 10)
	mb.cyl("enamel", Vector3(0.15, 0.36, 0.13), Vector3(0, 0.09, 0), 0.04, 0.045, 8)
	mb.col(Vector3(-0.26, 0, 0), Vector3(0.26, 0.45, 0.26))


func _p_vent(mb: MB, _root: Node3D) -> void:
	mb.box("plastic_cream", Vector3(-0.12, -0.12, 0), Vector3(0.12, 0.12, 0.01))
	mb.face("black", Vector3(-0.1, -0.1, 0.011), Vector3(0.2, 0, 0), Vector3(0, 0.2, 0))
	for i in 7:
		var y := -0.09 + i * 0.03
		mb.push(Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(0, y, 0.015)))
		mb.box("plastic_cream", Vector3(-0.1, -0.005, -0.004), Vector3(0.1, 0.005, 0.004))
		mb.pop()
	mb.col(Vector3(-0.13, -0.13, 0), Vector3(0.13, 0.13, 0.03))


func _p_kitchen_lamp(mb: MB, root: Node3D) -> void:
	mb.cyl("rubber", Vector3(0, -0.3, 0), Vector3(0, 0.3, 0), 0.004, 0.004, 4)
	mb.cyl("enamel", Vector3(0, -0.42, 0), Vector3(0, 0.14, 0), 0.2, 0.05, 10, false)
	mb.cyl("enamel", Vector3(0, -0.42, 0), Vector3(0, 0.14, 0), 0.198, 0.048, 10, false, 0.5, true)
	var bm := MB.new()
	bm.tbox("bulb_off", Vector3(0, -0.4, 0), 0.05, 0.05, 0.04, 0.04, 0.08)
	root.add_child(_mesh(bm, "Bulb"))
	_lamp_light(root, Vector3(0, -0.5, 0), 4.0)


# ---------------------------------------------------------------- hallway

func _p_coat_rack(mb: MB, _root: Node3D) -> void:
	mb.box("wood_dark", Vector3(-0.45, 1.6, 0), Vector3(0.45, 1.7, 0.025), 0.5)
	for i in 5:
		mb.cyl("chrome", Vector3(-0.36 + i * 0.18, 1.65, 0.025), Vector3(0, 0.03, 0.06), 0.006, 0.006, 4)
	mb.box("wood_dark", Vector3(-0.45, 1.84, 0), Vector3(0.45, 1.86, 0.26), 0.5)
	for s in [-1.0, 1.0]:
		mb.box("wood_dark", Vector3(0.43 * s, 1.7, 0), Vector3(0.45 * s, 1.84, 0.18))
	mb.cbox("coat_brown", Vector3(-0.3, 1.86, 0.05), Vector3(-0.08, 1.98, 0.22), 0.04)        # ushanka
	_coat(mb, Vector3(-0.3, 1.7, 0.1), "coat", 0.05, 1.05)
	_coat(mb, Vector3(0.0, 1.7, 0.19), "drape", -0.05, 1.1)
	_coat(mb, Vector3(0.3, 1.7, 0.1), "coat_brown", 0.08, 0.6)
	for i in 3:
		var x := -0.3 + i * 0.2
		for s in [-1.0, 1.0]:
			mb.tbox("leather", Vector3(x + 0.05 * s, 0, 0.25), 0.08, 0.26, 0.07, 0.24, 0.05)
	for s in [-1.0, 1.0]:
		mb.tbox("leather", Vector3(0.32 + 0.05 * s, 0, 0.2), 0.08, 0.1, 0.07, 0.09, 0.4)
		mb.tbox("leather", Vector3(0.32 + 0.05 * s, 0, 0.27), 0.08, 0.2, 0.07, 0.18, 0.06)
		mb.tbox("fabric_chair", Vector3(-0.38 + 0.035 * s, 0, 0.35), 0.05, 0.14, 0.05, 0.13, 0.03)   # child's sandals
	mb.col(Vector3(-0.46, 0.55, 0), Vector3(0.46, 1.98, 0.3))
	mb.col(Vector3(-0.46, 0, 0), Vector3(0.46, 0.4, 0.38))


func _p_mirror_rect(mb: MB, _root: Node3D) -> void:
	mb.box("wood_dark", Vector3(-0.24, -0.36, 0), Vector3(0.24, 0.36, 0.02))
	mb.face("mirror", Vector3(-0.2, -0.32, 0.021), Vector3(0.4, 0, 0), Vector3(0, 0.64, 0))
	mb.col(Vector3(-0.24, -0.36, 0), Vector3(0.24, 0.36, 0.04))


func _p_tumba(mb: MB, root: Node3D) -> void:
	var w := "wood_mid"
	_cabinet_body(mb, 0.5, 0.45, 0.3, w)
	mb.box(w, Vector3(-0.26, 0.45, -0.005), Vector3(0.26, 0.47, 0.31), 0.4)
	mb.box(w, Vector3(-0.232, 0.2, 0.015), Vector3(0.232, 0.215, 0.3), 0.4)
	for s in [-1.0, 1.0]:
		mb.tbox("leather", Vector3(0.1 * s, 0.08, 0.15), 0.08, 0.24, 0.07, 0.22, 0.05)
	# Rotary telephone.
	mb.tbox("plastic_dark", Vector3(-0.08, 0.47, 0.15), 0.2, 0.2, 0.15, 0.14, 0.08)
	mb.disc("plastic_cream", Vector3(-0.08, 0.552, 0.16), Vector3(0.05, 0, 0), Vector3(0, 0, -0.05), 10)
	mb.cbox("plastic_dark", Vector3(-0.18, 0.55, 0.07), Vector3(0.02, 0.59, 0.12), 0.015)
	mb.col(Vector3(-0.26, 0, 0), Vector3(0.26, 0.6, 0.3))
	_drawer(root, "Drawer", Vector3(0, 0.3, 0), _drawer_box.bind(0.46, 0.14, 0.26, w, 0.3), "things",
			"Квитанции, рожок для обуви, вязаные варежки.", 0.18)
	_item(root, "Keys", Vector3(0.14, 0.47, 0.16), 0.6, _p_keys, "Ключи",
			"Связка ключей. На кожаном брелоке выдавлено: «17».", true, "keys")
	_item(root, "Phone", Vector3(-0.08, 0.47, 0.15), 0.0, _hitbox.bind(Vector3(0.22, 0.14, 0.22), Vector3(0, 0.07, 0)),
			"Телефон", "Телефон. Подняли трубку — ни гудка, только тихое шипение.", false, "small")


func _p_keys(mb: MB) -> void:
	mb.cyl("chrome", Vector3(0, 0.003, 0), Vector3(0, 0.004, 0), 0.015, 0.015, 6)
	mb.box("brass", Vector3(-0.002, 0, 0.0), Vector3(0.012, 0.004, 0.06))
	mb.box("chrome", Vector3(-0.03, 0, -0.01), Vector3(-0.005, 0.004, 0.04))
	mb.box("leather", Vector3(0.01, 0, -0.04), Vector3(0.04, 0.005, -0.005))
	mb.col(Vector3(-0.05, 0, -0.06), Vector3(0.05, 0.04, 0.08))


func _p_el_panel(mb: MB, root: Node3D) -> void:
	var p := "pipe_paint"
	mb.box(p, Vector3(-0.16, 0, 0), Vector3(0.16, 0.42, 0.12), 0.0, 0.9, "s")
	mb.ibox(p, Vector3(-0.15, 0.01, 0.0), Vector3(0.15, 0.41, 0.12), 0.0, 0.4, "s")
	mb.box("enamel", Vector3(-0.1, 0.22, 0.0), Vector3(0.06, 0.38, 0.08))
	mb.face("glass_dark", Vector3(-0.08, 0.27, 0.081), Vector3(0.12, 0, 0), Vector3(0, 0.08, 0))
	for x in [-0.08, 0.06]:
		mb.cyl("plastic_cream", Vector3(x, 0.1, 0.0), Vector3(0, 0, 0.07), 0.025, 0.02, 8)
	mb.cyl("rubber", Vector3(0.12, 0.42, 0.04), Vector3(0, 0.3, 0), 0.008, 0.008, 4)
	mb.col(Vector3(-0.16, 0, 0), Vector3(0.16, 0.42, 0.12))
	_hinged(root, "Door", Vector3(-0.16, 0.0, 0.125), _leaf.bind(0.32, 0.42, 0.012, 1.0, p, p, p, false, false),
			"small_metal", -110.0, "Счётчик «СО-2». Диск не крутится. Пробки вывернуты наполовину.")


func _p_switch(mb: MB, root: Node3D) -> void:
	mb.box("plastic_cream", Vector3(-0.038, -0.05, 0), Vector3(0.038, 0.05, 0.012))
	mb.col(Vector3(-0.07, -0.08, 0), Vector3(0.07, 0.08, 0.05))
	var rocker := Node3D.new()
	rocker.name = "Rocker"
	rocker.position = Vector3(0, 0, 0.012)
	root.add_child(rocker)
	var rm := MB.new()
	rm.box("plastic_cream", Vector3(-0.022, -0.032, 0), Vector3(0.022, 0.032, 0.012), 0.0, 1.1)
	rocker.add_child(_mesh(rm))


func _p_bulb(mb: MB, root: Node3D) -> void:
	mb.cyl("rubber", Vector3(0, -0.28, 0), Vector3(0, 0.28, 0), 0.004, 0.004, 4)
	mb.cyl("plastic_dark", Vector3(0, -0.33, 0), Vector3(0, 0.06, 0), 0.02, 0.018, 8)
	var bm := MB.new()
	bm.cyl("bulb_off", Vector3(0, -0.38, 0), Vector3(0, 0.05, 0), 0.03, 0.015, 8)
	bm.cyl("bulb_off", Vector3(0, -0.4, 0), Vector3(0, 0.02, 0), 0.015, 0.03, 8)
	root.add_child(_mesh(bm, "Bulb"))
	_lamp_light(root, Vector3(0, -0.45, 0), 4.2)


func _p_wall_lamp(mb: MB, root: Node3D) -> void:
	mb.box("plastic_cream", Vector3(-0.08, -0.06, 0), Vector3(0.08, 0.06, 0.03))
	mb.tbox("shade_glass", Vector3(0, -0.06, 0.09), 0.16, 0.1, 0.12, 0.06, 0.12)
	var bm := MB.new()
	bm.tbox("bulb_off", Vector3(0, -0.03, 0.08), 0.04, 0.04, 0.03, 0.03, 0.06)
	root.add_child(_mesh(bm, "Bulb"))
	_lamp_light(root, Vector3(0, 0.0, 0.3), 3.0)


func _p_doormat(mb: MB, _root: Node3D) -> void:
	mb.box("coat", Vector3(-0.35, 0, -0.22), Vector3(0.35, 0.01, 0.22), 0.3)


# ---------------------------------------------------------------- bathroom and toilet

func _p_bathtub(mb: MB, _root: Node3D) -> void:
	var e := "enamel_bath"
	var y := 0.56
	mb.box(e, Vector3(-0.35, 0.09, -0.675), Vector3(0.35, y, 0.675), 0.0, 1.0, "u")
	var ix := 0.28
	var iz := 0.6
	mb.face(e, Vector3(-0.35, y, 0.675), Vector3(0.7, 0, 0), Vector3(0, 0, -(0.675 - iz)))
	mb.face(e, Vector3(-0.35, y, -iz), Vector3(0.7, 0, 0), Vector3(0, 0, -(0.675 - iz)))
	mb.face(e, Vector3(-0.35, y, iz), Vector3(0.35 - ix, 0, 0), Vector3(0, 0, -2 * iz))
	mb.face(e, Vector3(ix, y, iz), Vector3(0.35 - ix, 0, 0), Vector3(0, 0, -2 * iz))
	mb.ibox(e, Vector3(-ix, 0.16, -iz), Vector3(ix, y, iz), 0.0, 0.85, "u")
	mb.cyl("black", Vector3(0, 0.161, -0.5), Vector3(0, 0.002, 0), 0.025, 0.025, 6)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.tbox("iron_paint", Vector3(0.28 * sx, 0, 0.6 * sz), 0.06, 0.06, 0.09, 0.09, 0.09)
	mb.col(Vector3(-0.35, 0, -0.675), Vector3(0.35, y, 0.675))


func _p_mixer(mb: MB, _root: Node3D) -> void:
	var c := "chrome"
	mb.cyl(c, Vector3(-0.12, 0, 0.05), Vector3(0.24, 0, 0), 0.018, 0.018, 8)
	for s in [-1.0, 1.0]:
		mb.cyl(c, Vector3(0.12 * s, 0, 0), Vector3(0, 0, 0.05), 0.012, 0.012, 6)
		mb.cyl(c, Vector3(0.1 * s, 0.0, 0.05), Vector3(0, 0.06, 0), 0.008, 0.008, 4)
		mb.box(c, Vector3(0.1 * s - 0.03, 0.055, 0.045), Vector3(0.1 * s + 0.03, 0.065, 0.055))
	mb.cyl(c, Vector3(0, -0.01, 0.05), Vector3(0.0, -0.02, 0.28), 0.01, 0.008, 6)
	var pts := [Vector3(0.02, -0.02, 0.07), Vector3(0.05, -0.25, 0.12), Vector3(0.06, -0.4, 0.15),
			Vector3(0.1, -0.35, 0.18), Vector3(0.15, 0.1, 0.05), Vector3(0.15, 0.85, 0.04)]
	for i in pts.size() - 1:
		mb.cyl("chrome", pts[i], pts[i + 1] - pts[i], 0.008, 0.008, 4)
	mb.tbox(c, Vector3(0.15, 0.85, 0.05), 0.03, 0.03, 0.08, 0.08, 0.1, 1.0, Vector3(0, 0, 0.02))
	mb.box(c, Vector3(0.13, 0.84, 0), Vector3(0.17, 0.87, 0.05))
	mb.col(Vector3(-0.15, -0.1, 0), Vector3(0.2, 0.1, 0.32))


func _p_basin(mb: MB, _root: Node3D) -> void:
	var e := "enamel"
	var y0 := 0.66
	var y1 := 0.82
	mb.tbox(e, Vector3(0, y0, 0.2), 0.36, 0.26, 0.5, 0.4, y1 - y0, 1.0, Vector3.ZERO, "u")
	mb.face(e, Vector3(-0.25, y1, 0.4), Vector3(0.5, 0, 0), Vector3(0, 0, -0.06))
	mb.face(e, Vector3(-0.25, y1, 0.06), Vector3(0.5, 0, 0), Vector3(0, 0, -0.06))
	mb.face(e, Vector3(-0.25, y1, 0.34), Vector3(0.06, 0, 0), Vector3(0, 0, -0.28))
	mb.face(e, Vector3(0.19, y1, 0.34), Vector3(0.06, 0, 0), Vector3(0, 0, -0.28))
	mb.ibox(e, Vector3(-0.19, y0 + 0.03, 0.06), Vector3(0.19, y1, 0.34), 0.0, 0.8, "u")
	mb.cyl("black", Vector3(0, y0 + 0.031, 0.2), Vector3(0, 0.002, 0), 0.02, 0.02, 6)
	mb.cyl("pipe_paint", Vector3(0, 0.0, 0.12), Vector3(0, y0, 0), 0.022, 0.022, 6)
	mb.box("pipe_paint", Vector3(-0.04, 0.3, 0.08), Vector3(0.04, 0.38, 0.16))
	mb.cyl("chrome", Vector3(0, y1 + 0.12, 0.0), Vector3(0, 0, 0.12), 0.01, 0.008, 6)
	for s in [-1.0, 1.0]:
		mb.cyl("chrome", Vector3(0.06 * s, y1 + 0.16, 0), Vector3(0, 0, 0.04), 0.008, 0.008, 4)
		mb.box("chrome", Vector3(0.06 * s - 0.02, y1 + 0.155, 0.035), Vector3(0.06 * s + 0.02, y1 + 0.165, 0.045))
	mb.col(Vector3(-0.25, 0, 0), Vector3(0.25, y1, 0.4))


func _p_bath_mirror(mb: MB, _root: Node3D) -> void:
	mb.box("chrome", Vector3(-0.19, 0.12, 0), Vector3(0.19, 0.6, 0.012))
	mb.face("mirror", Vector3(-0.17, 0.14, 0.013), Vector3(0.34, 0, 0), Vector3(0, 0.44, 0))
	mb.box("glass_dark", Vector3(-0.22, 0.0, 0), Vector3(0.22, 0.012, 0.12))
	mb.cyl("glass_dark", Vector3(0.12, 0.012, 0.06), Vector3(0, 0.09, 0), 0.03, 0.035, 6)
	for s in [-1.0, 1.0]:
		mb.cyl("plastic_cream", Vector3(0.12 + 0.01 * s, 0.03, 0.06), Vector3(0.01 * s, 0.15, 0.0), 0.005, 0.005, 4)
	mb.box("plastic_cream", Vector3(-0.12, 0.012, 0.03), Vector3(-0.04, 0.04, 0.08))
	mb.col(Vector3(-0.22, 0, 0), Vector3(0.22, 0.6, 0.12))


func _p_towel_rail(mb: MB, _root: Node3D) -> void:
	var c := "chrome"
	for s in [-1.0, 1.0]:
		mb.cyl(c, Vector3(0.22 * s, 0, 0), Vector3(0, 0, 0.06), 0.014, 0.014, 6)
		mb.cyl(c, Vector3(0.22 * s, 0, 0.06), Vector3(0, 0.5, 0), 0.014, 0.014, 6)
	for y in [0.0, 0.25, 0.5]:
		mb.cyl(c, Vector3(-0.22, y, 0.06), Vector3(0.44, 0, 0), 0.014, 0.014, 6)
	mb.quad("towel", Vector3(-0.15, 0.08, 0.075), Vector3(0.15, 0.08, 0.075), Vector3(-0.15, 0.5, 0.075),
			Vector3(0.15, 0.5, 0.075), Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0), 1.0, 1, 2)
	mb.quad("towel", Vector3(-0.15, 0.5, 0.045), Vector3(0.15, 0.5, 0.045), Vector3(-0.15, 0.2, 0.045),
			Vector3(0.15, 0.2, 0.045), Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0), 0.75, 1, 2)
	mb.col(Vector3(-0.24, 0, 0), Vector3(0.24, 0.52, 0.09))


func _p_bucket(mb: MB, _root: Node3D) -> void:
	mb.cyl("enamel", Vector3.ZERO, Vector3(0, 0.28, 0), 0.11, 0.14, 10, false)
	mb.cyl("enamel", Vector3(0, 0.02, 0), Vector3(0, 0.26, 0), 0.105, 0.135, 10, false, 0.5, true)
	mb.disc("coat", Vector3(0, 0.03, 0), Vector3(0.1, 0, 0), Vector3(0, 0, -0.1), 8)
	mb.cyl("chrome", Vector3(-0.14, 0.27, 0), Vector3(0.14, 0.12, 0), 0.003, 0.003, 4)
	mb.cyl("chrome", Vector3(0.0, 0.39, 0), Vector3(0.14, -0.12, 0), 0.003, 0.003, 4)
	mb.col(Vector3(-0.15, 0, -0.15), Vector3(0.15, 0.3, 0.15))


func _p_toilet(mb: MB, _root: Node3D) -> void:
	var e := "enamel"
	mb.tbox(e, Vector3(0, 0, 0.03), 0.22, 0.32, 0.28, 0.38, 0.28)
	mb.tbox(e, Vector3(0, 0.28, 0.05), 0.3, 0.42, 0.38, 0.52, 0.11, 1.0, Vector3.ZERO, "u")
	mb.disc("black", Vector3(0, 0.385, 0.08), Vector3(0.11, 0, 0), Vector3(0, 0, -0.16), 10)
	mb.ring("plastic_dark", Vector3(0, 0.395, 0.08), Vector3(0.18, 0, 0), Vector3(0, 0, -0.24), 0.62, 12)
	mb.ring(e, Vector3(0, 0.39, 0.05), Vector3(0.19, 0, 0), Vector3(0, 0, -0.26), 0.9, 12)
	mb.push(Transform3D(Basis(Vector3.RIGHT, -0.15), Vector3(0, 0.39, -0.17)))
	mb.cbox("plastic_dark", Vector3(-0.17, 0, -0.02), Vector3(0.17, 0.42, 0.0), 0.01)
	mb.pop()
	mb.cyl("pipe_paint", Vector3(0, 0.3, -0.2), Vector3(0, 0, -0.12), 0.05, 0.05, 8)
	mb.col(Vector3(-0.2, 0, -0.32), Vector3(0.2, 0.42, 0.32))


func _p_tank(mb: MB, _root: Node3D) -> void:
	mb.cbox("iron_paint", Vector3(-0.2, 0, 0), Vector3(0.2, 0.3, 0.18), 0.02, 0.3)
	mb.cyl("pipe_paint", Vector3(0, 0, 0.12), Vector3(0, -1.38, 0.18), 0.02, 0.02, 6)
	mb.box("iron_paint", Vector3(0.16, 0.26, 0.17), Vector3(0.18, 0.28, 0.24))
	mb.cyl("chrome", Vector3(0.17, 0.26, 0.24), Vector3(0, -0.62, 0), 0.003, 0.003, 4)
	mb.cyl("wood_light", Vector3(0.17, -0.42, 0.24), Vector3(0, 0.08, 0), 0.015, 0.012, 6)
	mb.col(Vector3(-0.2, 0, 0), Vector3(0.2, 0.3, 0.2))
	mb.col(Vector3(0.13, -0.45, 0.2), Vector3(0.21, 0.26, 0.28))


func _p_paper_nail(mb: MB, _root: Node3D) -> void:
	mb.cyl("chrome", Vector3(0, 0.0, 0), Vector3(0, 0.0, 0.04), 0.003, 0.003, 4)
	for i in 4:
		mb.quad("newspaper", Vector3(-0.07, -0.16, 0.005 + i * 0.003), Vector3(0.07, -0.16, 0.005 + i * 0.003),
				Vector3(-0.07, 0.01, 0.005 + i * 0.003), Vector3(0.07, 0.01, 0.005 + i * 0.003), Vector2(0, 1), Vector2(1, 1),
				Vector2(0, 0), Vector2(1, 0), 1.0 - i * 0.05, 1, 1)
	mb.col(Vector3(-0.08, -0.17, 0), Vector3(0.08, 0.02, 0.04))


# ================================================================ rooms

## Builds the shell of one room into mb: floor, ceiling, four walls with door and window holes,
## skirting boards, and the colliders. holes: side -> [[from, to, bottom, top]] along that wall's
## world axis (x for front/back, z for left/right). bands: [[material, y0, y1, tile_u, tile_v]],
## tile_v <= 0 stretches the texture over the full height.
func _shell(mb: MB, x0: float, x1: float, z0: float, z1: float, floor_mat: String, floor_tile: float,
		bands: Array, holes: Dictionary, skirting := "wood_dark") -> void:
	mb.ao = func(p: Vector3) -> float:
		var f := lerpf(0.6, 1.0, clampf(p.y / 0.7, 0.0, 1.0)) * lerpf(0.78, 1.0, clampf((H - p.y) / 0.35, 0.0, 1.0))
		var dx := minf(absf(p.x - x0), absf(x1 - p.x))
		var dz := minf(absf(p.z - z0), absf(z1 - p.z))
		f *= lerpf(0.55, 1.0, clampf(maxf(dx, dz) / 0.7, 0.0, 1.0))
		f *= lerpf(0.85, 1.0, clampf(minf(dx, dz) / 0.35, 0.0, 1.0))
		return f
	mb.face(floor_mat, Vector3(x0, 0, z1), Vector3(x1 - x0, 0, 0), Vector3(0, 0, z0 - z1), floor_tile)
	mb.face("ceiling", Vector3(x0, H, z0), Vector3(x1 - x0, 0, 0), Vector3(0, 0, z1 - z0), 1.2, 0.9)
	mb.col(Vector3(x0, -0.15, z0), Vector3(x1, 0, z1))
	var sides := {
		"front": [Vector3(x1, 0, z1), Vector3(-1, 0, 0), Vector3(0, 0, -1), x1 - x0],
		"back": [Vector3(x0, 0, z0), Vector3(1, 0, 0), Vector3(0, 0, 1), x1 - x0],
		"left": [Vector3(x0, 0, z1), Vector3(0, 0, -1), Vector3(1, 0, 0), z1 - z0],
		"right": [Vector3(x1, 0, z0), Vector3(0, 0, 1), Vector3(-1, 0, 0), z1 - z0],
	}
	for side: String in sides:
		var d: Array = sides[side]
		var start: Vector3 = d[0]
		var r: Vector3 = d[1]
		var hs := []
		for hole in holes.get(side, []):
			var a: float = hole[0]
			var b: float = hole[1]
			var sa: float
			var sb: float
			match side:
				"front":
					sa = x1 - maxf(a, b)
					sb = x1 - minf(a, b)
				"back":
					sa = minf(a, b) - x0
					sb = maxf(a, b) - x0
				"left":
					sa = z1 - maxf(a, b)
					sb = z1 - minf(a, b)
				"right":
					sa = minf(a, b) - z0
					sb = maxf(a, b) - z0
			hs.append([sa, sb, hole[2], hole[3]])
		_wall(mb, start, r, d[2], d[3], hs, bands, skirting)
	mb.ao = Callable()


func _wall(mb: MB, start: Vector3, r: Vector3, n: Vector3, length: float, holes: Array, bands: Array, skirting: String) -> void:
	var cuts := [0.0, length]
	for h in holes:
		cuts.append(clampf(h[0], 0.0, length))
		cuts.append(clampf(h[1], 0.0, length))
	cuts.sort()
	var uoff := start.x * 0.37 + start.z * 0.61
	for i in cuts.size() - 1:
		var sa: float = cuts[i]
		var sb: float = cuts[i + 1]
		if sb - sa < 0.001:
			continue
		var mid := (sa + sb) * 0.5
		var spans := [[0.0, H]]
		var door := false
		for h in holes:
			if mid > h[0] and mid < h[1]:
				spans = []
				if h[2] > 0.001:
					spans.append([0.0, h[2]])
				else:
					door = true
				if h[3] < H - 0.001:
					spans.append([h[3], H])
		for sp in spans:
			for band in bands:
				var y0 := maxf(sp[0], band[1])
				var y1 := minf(sp[1], band[2])
				if y1 - y0 < 0.001:
					continue
				var p00 := start + r * sa + Vector3.UP * y0
				var p10 := start + r * sb + Vector3.UP * y0
				var p01 := start + r * sa + Vector3.UP * y1
				var p11 := start + r * sb + Vector3.UP * y1
				var tu: float = band[3]
				var tv: float = band[4]
				var va: float = (-y0 / tv) if tv > 0.0 else (1.0 - y0 / H)
				var vb: float = (-y1 / tv) if tv > 0.0 else (1.0 - y1 / H)
				mb.quad(band[0], p00, p10, p01, p11, Vector2((sa + uoff) / tu, va), Vector2((sb + uoff) / tu, va),
						Vector2((sa + uoff) / tu, vb), Vector2((sb + uoff) / tu, vb), 1.0, 0, 0, n)
			mb.col(start + r * sa + Vector3.UP * sp[0] - n * 0.12, start + r * sb + Vector3.UP * sp[1])
		if skirting != "" and not door:
			mb.box(skirting, start + r * sa, start + r * sb + n * 0.018 + Vector3.UP * 0.07, 0.0, 0.8)


func _room(title: String, bit: int, build: Callable) -> String:
	var root := Node3D.new()
	root.name = title
	root.set_script(load(SCRIPTS + "room.gd"))
	root.set("layer_bit", bit)
	var mb := MB.new()
	build.call(mb, root)
	var mesh := _mesh(mb, "Shell")
	root.add_child(mesh)
	root.move_child(mesh, 0)
	root.add_child(_body(mb.cols, "Walls"))
	var path := ROOMS + title.to_snake_case() + ".tscn"
	_save(root, path)
	return path


func _lamp_at(parent: Node3D, path: String, pos: Vector3, title: String, group: String, on := false, flicker := 0.0,
		rot := 0.0) -> Node3D:
	var n := _inst(parent, path, pos, rot, title, {"on": on, "flicker": flicker})
	n.add_to_group(group, true)
	return n


func _switch_at(parent: Node3D, path: String, pos: Vector3, rot: float, title: String, group: String, on := false) -> void:
	_inst(parent, path, pos, rot, title, {"lamp_group": group, "on": on})


## A door between two rooms: it is lit by the lamps on both sides.
func _door_at(parent: Node3D, path: String, pos: Vector3, rot: float, title: String, bits: Array) -> void:
	var d := _inst(parent, path, pos, rot, title)
	var mask := 0
	for b in bits:
		mask |= 1 << int(b)
	d.set_meta("layers", mask)


func _window_light(parent: Node3D, pos: Vector3) -> void:
	var l := _light(parent, "WindowLight", pos, 0.45, Color(0.45, 0.58, 0.85), 3.2)
	l.omni_attenuation = 1.6


func _rooms(p: Dictionary) -> void:
	P = p
	print("rooms:")
	var rooms := {}
	rooms.hall = _room("Hallway", L_HALL, _r_hall)
	rooms.kitchen = _room("Kitchen", L_KITCHEN, _r_kitchen)
	rooms.living = _room("LivingRoom", L_LIVING, _r_living)
	rooms.bed = _room("Bedroom", L_BED, _r_bed)
	rooms.bath = _room("Bathroom", L_BATH, _r_bath)
	rooms.toilet = _room("Toilet", L_TOILET, _r_toilet)
	var flat := Node3D.new()
	flat.name = "Flat17"
	for k in ["hall", "kitchen", "living", "bed", "bath", "toilet"]:
		_inst(flat, rooms[k], Vector3.ZERO)
	_save(flat, "res://apartment/apartment_17.tscn")


func _r_hall(mb: MB, root: Node3D) -> void:
	var p := P
	_shell(mb, -1.155, 1.155, -2.6, -0.2, "linoleum", 0.8, [["wallpaper_hall", 0.0, H, 0.7, 0.7]], {
		"front": [[-0.45, 0.45, 0.0, 2.05]],
		"left": [[-1.4, -2.2, 0.0, 2.0]],
		"right": [[-0.33, -0.99, 0.0, 2.0], [-1.59, -2.25, 0.0, 2.0]],
		"back": [[-1.0, -0.2, 0.0, 2.0], [0.445, 1.105, 0.0, 2.0]]})
	_door_at(root, p.door_entrance, Vector3(0, 0, -0.1), PI, "EntranceDoor", [L_LANDING, L_HALL])
	_door_at(root, p.door_80_glass_l, Vector3(-1.215, 0, -1.8), -PI / 2, "KitchenDoor", [L_HALL, L_KITCHEN])
	_door_at(root, p.door_66_l, Vector3(1.215, 0, -0.66), -PI / 2, "ToiletDoor", [L_HALL, L_TOILET])
	_door_at(root, p.door_66_r, Vector3(1.215, 0, -1.92), -PI / 2, "BathroomDoor", [L_HALL, L_BATH])
	_door_at(root, p.door_80_glass_l, Vector3(-0.6, 0, -2.66), PI, "LivingRoomDoor", [L_HALL, L_LIVING])
	_door_at(root, p.door_66_l, Vector3(0.775, 0, -2.66), PI, "BedroomDoor", [L_HALL, L_BED])
	_inst(root, p.coat_rack, Vector3(-1.155, 0, -0.85), PI / 2, "CoatRack")
	_inst(root, p.tumba, Vector3(0.12, 0, -2.6), 0.0, "ShoeCabinet")
	_inst(root, p.mirror_rect, Vector3(0.12, 1.45, -2.6), 0.0, "Mirror")
	_inst(root, p.el_panel, Vector3(0.78, 1.55, -0.2), PI, "ElectricPanel")
	_inst(root, p.doormat, Vector3(0, 0.0, -0.55), 0.0, "Doormat")
	_lamp_at(root, p.bulb, Vector3(0, H, -1.4), "Lamp", "lamp_hall")
	_switch_at(root, p.switch, Vector3(-0.68, 1.35, -0.2), PI, "Switch", "lamp_hall")
	_switch_at(root, p.switch, Vector3(1.155, 1.45, -1.22), -PI / 2, "SwitchToilet", "lamp_toilet")
	_switch_at(root, p.switch, Vector3(1.155, 1.45, -1.37), -PI / 2, "SwitchBathroom", "lamp_bath")
	_decal(root, "decal_grime", Vector3(-0.68, 1.35, -0.2), Vector3(0, 0, -1), 0.3, 0.4)
	_decal(root, "decal_torn", Vector3(-1.155, 0.35, -1.25), Vector3(1, 0, 0), 0.6, 0.6)
	_decal(root, "decal_crack", Vector3(0.0, 2.3, -0.2), Vector3(0, 0, -1), 0.5, 0.5, 0.3)
	_decal(root, "decal_mould", Vector3(1.0, 2.35, -2.6), Vector3(0, 0, 1), 0.5, 0.5, PI / 2)
	_decal(root, "decal_damp", Vector3(-0.3, H, -1.9), Vector3(0, -1, 0), 0.9, 0.9, 0.0, "CeilingDamp")


func _r_kitchen(mb: MB, root: Node3D) -> void:
	var p := P
	_shell(mb, -3.575, -1.275, -2.6, -0.2, "tile_floor", 0.5, [["paint_kitchen", 0.0, H, 1.3, 0.0]], {
		"right": [[-1.4, -2.2, 0.0, 2.0]],
		"left": [[-1.05, -1.95, 0.85, 2.1]]})
	mb.face("tile_kitchen", Vector3(-1.875, 0.86, -0.205), Vector3(-1.7, 0, 0), Vector3(0, 0.6, 0), 0.6)
	mb.cyl("gas_pipe", Vector3(-2.53, 1.0, -0.25), Vector3(0, H - 1.0, 0), 0.014, 0.014, 6)
	mb.cyl("gas_pipe", Vector3(-2.53, 1.0, -0.25), Vector3(-0.22, 0, 0), 0.014, 0.014, 6)
	mb.box("gas_pipe", Vector3(-2.56, 1.2, -0.28), Vector3(-2.5, 1.26, -0.22))
	mb.box("rubber", Vector3(-2.54, 1.26, -0.27), Vector3(-2.46, 1.27, -0.23))
	_inst(root, p.sink_cab, Vector3(-3.275, 0, -0.2), PI, "Sink")
	_inst(root, p.stove, Vector3(-2.725, 0, -0.2), PI, "Stove")
	_inst(root, p.counter_cab, Vector3(-2.175, 0, -0.2), PI, "Counter")
	_inst(root, p.fridge, Vector3(-1.575, 0, -0.2), PI, "Fridge")
	_inst(root, p.wall_cab, Vector3(-3.275, 1.5, -0.2), PI, "WallCabinetL")
	_inst(root, p.wall_cab, Vector3(-2.175, 1.5, -0.2), PI, "WallCabinetR")
	_inst(root, p.dish_rack, Vector3(-3.275, 1.04, -0.2), PI, "DishRack")
	_inst(root, p.window_90, Vector3(-3.575, 0.85, -1.5), PI / 2, "Window")
	_inst(root, p.radiator_6, Vector3(-3.575, 0, -1.5), PI / 2, "Radiator")
	_inst(root, p.curtains_90, Vector3(-3.575, 2.22, -1.5), PI / 2, "Curtains")
	_inst(root, p.kitchen_table, Vector3(-3.18, 0, -2.22), 0.0, "Table")
	_inst(root, p.stool, Vector3(-2.62, 0, -2.25), 0.3, "Stool1")
	_inst(root, p.stool, Vector3(-3.12, 0, -1.72), -0.2, "Stool2")
	_inst(root, p.vent, Vector3(-1.95, 2.25, -0.2), PI, "Vent")
	_lamp_at(root, p.kitchen_lamp, Vector3(-2.425, H, -1.4), "Lamp", "lamp_kitchen")
	_switch_at(root, p.switch, Vector3(-1.275, 1.35, -1.22), -PI / 2, "Switch", "lamp_kitchen")
	_window_light(root, Vector3(-3.2, 1.5, -1.5))
	_decal(root, "decal_grime", Vector3(-2.725, 1.15, -0.2), Vector3(0, 0, -1), 0.7, 0.6)
	_decal(root, "decal_mould", Vector3(-3.4, 2.3, -2.6), Vector3(0, 0, 1), 0.5, 0.5)
	_decal(root, "decal_damp", Vector3(-2.0, H, -1.8), Vector3(0, -1, 0), 1.0, 1.0, 0.0, "CeilingDamp")


func _r_living(mb: MB, root: Node3D) -> void:
	var p := P
	_shell(mb, -3.575, 0.225, -7.32, -2.72, "parquet", 0.8, [["wallpaper_living", 0.0, H, 0.75, 0.75]], {
		"front": [[-1.0, -0.2, 0.0, 2.0]],
		"back": [[-2.425, -0.925, 0.85, 2.1]]})
	_inst(root, p.window_150, Vector3(-1.675, 0.85, -7.32), 0.0, "Window")
	_inst(root, p.radiator_10, Vector3(-1.675, 0, -7.32), 0.0, "Radiator")
	_inst(root, p.curtains_150, Vector3(-1.675, 2.28, -7.32), 0.0, "Curtains")
	_inst(root, p.plant, Vector3(-1.15, 0.85, -7.25), 0.0, "Plant")
	_inst(root, p.sofa, Vector3(-3.0, 0, -5.2), PI / 2, "Sofa")
	_inst(root, p.carpet_wall, Vector3(-3.575, 0.8, -5.2), PI / 2, "WallCarpet")
	_inst(root, p.wall_unit, Vector3(-0.025, 0, -5.0), -PI / 2, "WallUnit")
	_inst(root, p.armchair, Vector3(-2.95, 0, -3.35), PI / 2 + 0.35, "Armchair1")
	_inst(root, p.armchair, Vector3(-2.8, 0, -6.75), PI / 2 - 0.55, "Armchair2")
	_inst(root, p.coffee_table, Vector3(-2.0, 0, -5.2), PI / 2, "CoffeeTable")
	_inst(root, p.carpet_floor, Vector3(-1.75, 0, -5.0), 0.0, "Carpet")
	_lamp_at(root, p.chandelier, Vector3(-1.675, H, -5.0), "Chandelier", "lamp_living")
	_switch_at(root, p.switch, Vector3(0.06, 1.35, -2.72), PI, "Switch", "lamp_living")
	_window_light(root, Vector3(-1.675, 1.6, -6.9))
	_item(root, "Clock", Vector3(-3.575, 1.95, -3.3), PI / 2, _p_wall_clock, "Часы",
			"Часы с кукушкой. Гиря опустилась до пола. Стрелки — на без четверти четыре.", false, "wood")
	_decal(root, "decal_torn", Vector3(-2.6, 0.5, -7.32), Vector3(0, 0, 1), 0.7, 0.7)
	_decal(root, "decal_mould", Vector3(-3.3, 2.25, -7.32), Vector3(0, 0, 1), 0.6, 0.6)
	_decal(root, "decal_crack", Vector3(0.225, 2.2, -6.8), Vector3(-1, 0, 0), 0.5, 0.6, 0.2)
	_decal(root, "decal_damp", Vector3(-2.8, H, -6.6), Vector3(0, -1, 0), 1.3, 1.3, 0.4, "CeilingDamp")
	_decal(root, "decal_grime", Vector3(-3.575, 0.55, -4.0), Vector3(1, 0, 0), 0.5, 0.4, 0.0, "SofaGrime")


func _r_bed(mb: MB, root: Node3D) -> void:
	var p := P
	_shell(mb, 0.345, 2.825, -7.32, -2.72, "parquet", 0.8, [["wallpaper_bed", 0.0, H, 0.6, 0.6]], {
		"front": [[0.445, 1.105, 0.0, 2.0]],
		"back": [[0.985, 2.185, 0.85, 2.1]]})
	_inst(root, p.window_120, Vector3(1.585, 0.85, -7.32), 0.0, "Window")
	_inst(root, p.radiator_8, Vector3(1.585, 0, -7.32), 0.0, "Radiator")
	_inst(root, p.curtains_120, Vector3(1.585, 2.28, -7.32), 0.0, "Curtains")
	_inst(root, p.bed, Vector3(2.825, 0, -5.8), -PI / 2, "Bed")
	_inst(root, p.carpet_wall_bed, Vector3(2.825, 0.85, -5.8), -PI / 2, "WallCarpet")
	_inst(root, p.nightstand, Vector3(2.825, 0, -4.73), -PI / 2, "Nightstand")
	_inst(root, p.wardrobe, Vector3(0.345, 0, -4.2), PI / 2, "Wardrobe")
	_inst(root, p.mirror_oval, Vector3(2.05, 1.55, -2.72), PI, "Mirror")
	_inst(root, p.stool_clothes, Vector3(1.95, 0, -3.25), 0.4, "Stool")
	_inst(root, p.slippers, Vector3(1.0, 0, -5.4), PI / 2 + 0.15, "Slippers")
	_lamp_at(root, p.pendant, Vector3(1.585, H, -5.0), "Lamp", "lamp_bedroom")
	_switch_at(root, p.switch, Vector3(1.26, 1.35, -2.72), PI, "Switch", "lamp_bedroom")
	_window_light(root, Vector3(1.585, 1.6, -6.9))
	_decal(root, "decal_torn", Vector3(0.345, 1.2, -6.4), Vector3(1, 0, 0), 0.8, 0.9)
	_decal(root, "decal_mould", Vector3(2.6, 2.25, -7.32), Vector3(0, 0, 1), 0.5, 0.6, PI / 2)
	_decal(root, "decal_damp", Vector3(0.9, H, -6.6), Vector3(0, -1, 0), 1.1, 1.1, 1.0, "CeilingDamp")
	_decal(root, "decal_crack", Vector3(1.4, 2.0, -2.72), Vector3(0, 0, -1), 0.4, 0.7, -0.3)


func _r_bath(mb: MB, root: Node3D) -> void:
	var p := P
	_shell(mb, 1.275, 2.825, -2.6, -1.25, "tile_floor", 0.4,
			[["tile_bath", 0.0, 1.6, 0.6, 0.6], ["plaster_grey", 1.6, H, 1.0, 1.0]], {"left": [[-1.59, -2.25, 0.0, 2.0]]}, "")
	for x in [2.74, 2.68]:
		var xf: float = x
		mb.cyl("pipe_paint", Vector3(xf, 0, -1.31), Vector3(0, H, 0), 0.022, 0.022, 6)
	mb.cyl("iron_paint", Vector3(2.76, 0, -2.52), Vector3(0, H, 0), 0.055, 0.055, 8)
	mb.cyl("pipe_paint", Vector3(1.4, 0.25, -1.3), Vector3(1.3, 0, 0), 0.016, 0.016, 6)
	mb.box("chrome", Vector3(2.64, 1.0, -1.34), Vector3(2.7, 1.06, -1.28))
	_inst(root, p.bathtub, Vector3(2.475, 0, -1.925), 0.0, "Bathtub")
	_inst(root, p.mixer, Vector3(2.825, 0.95, -1.95), -PI / 2, "Mixer")
	_inst(root, p.basin, Vector3(1.65, 0, -1.25), PI, "Basin")
	_inst(root, p.bath_mirror, Vector3(1.65, 1.15, -1.25), PI, "MirrorShelf")
	_inst(root, p.towel_rail, Vector3(1.62, 1.0, -2.6), 0.0, "TowelRail")
	_inst(root, p.bucket, Vector3(1.95, 0, -2.42), 0.0, "Bucket")
	_lamp_at(root, p.wall_lamp, Vector3(1.65, 2.2, -1.25), "Lamp", "lamp_bath", false, 0.0, PI)
	_decal(root, "decal_mould", Vector3(2.7, 2.3, -2.6), Vector3(0, 0, 1), 0.6, 0.6)
	_decal(root, "decal_damp", Vector3(2.0, H, -1.9), Vector3(0, -1, 0), 1.0, 1.0, 0.7, "CeilingDamp")
	_decal(root, "decal_grime", Vector3(2.825, 0.7, -1.9), Vector3(-1, 0, 0), 0.9, 0.5, 0.0, "TubGrime")


func _r_toilet(mb: MB, root: Node3D) -> void:
	var p := P
	_shell(mb, 1.275, 2.825, -1.13, -0.2, "tile_floor", 0.4,
			[["tile_bath", 0.0, 1.2, 0.6, 0.6], ["plaster_grey", 1.2, H, 1.0, 1.0]], {"left": [[-0.33, -0.99, 0.0, 2.0]]}, "")
	mb.cyl("iron_paint", Vector3(2.74, 0, -0.29), Vector3(0, H, 0), 0.06, 0.06, 8)
	for x in [2.6, 2.54]:
		var xf: float = x
		mb.cyl("pipe_paint", Vector3(xf, 0, -0.25), Vector3(0, H, 0), 0.018, 0.018, 6)
	mb.box("chrome", Vector3(2.57, 1.4, -0.29), Vector3(2.63, 1.46, -0.23))
	_inst(root, p.toilet, Vector3(2.45, 0, -0.66), -PI / 2, "Toilet")
	_inst(root, p.tank, Vector3(2.825, 1.85, -0.66), -PI / 2, "Tank")
	_inst(root, p.vent, Vector3(2.1, 2.2, -1.13), 0.0, "Vent")
	_inst(root, p.paper_nail, Vector3(2.1, 1.0, -1.13), 0.0, "Paper")
	_lamp_at(root, p.bulb, Vector3(2.05, H, -0.66), "Lamp", "lamp_toilet", false, 0.6)
	_decal(root, "decal_mould", Vector3(2.8, 0.4, -1.13), Vector3(0, 0, 1), 0.5, 0.6)
	_decal(root, "decal_damp", Vector3(2.3, H, -0.6), Vector3(0, -1, 0), 0.8, 0.8, 0.2, "CeilingDamp")


func _p_wall_clock(mb: MB) -> void:
	mb.push(Transform3D(Basis.IDENTITY, Vector3.ZERO))
	mb.tbox("wood_dark", Vector3(0, -0.15, 0.06), 0.24, 0.12, 0.24, 0.12, 0.25)
	mb.tbox("wood_dark", Vector3(0, 0.1, 0.06), 0.3, 0.14, 0.02, 0.14, 0.14)
	mb.disc("plastic_cream", Vector3(0, -0.03, 0.121), Vector3(0.07, 0, 0), Vector3(0, 0.07, 0), 10)
	mb.box("black", Vector3(-0.003, -0.03, 0.122), Vector3(0.003, 0.03, 0.124))
	mb.box("black", Vector3(-0.05, -0.033, 0.122), Vector3(0.0, -0.027, 0.124))
	mb.cyl("rubber", Vector3(-0.04, -0.15, 0.06), Vector3(0, -0.75, 0), 0.002, 0.002, 3)
	mb.cyl("rubber", Vector3(0.04, -0.15, 0.06), Vector3(0, -0.5, 0), 0.002, 0.002, 3)
	mb.cyl("brass", Vector3(-0.04, -1.05, 0.06), Vector3(0, 0.15, 0), 0.02, 0.02, 6)
	mb.cyl("brass", Vector3(0.04, -0.8, 0.06), Vector3(0, 0.15, 0), 0.02, 0.02, 6)
	mb.pop()
	mb.col(Vector3(-0.16, -0.2, 0), Vector3(0.16, 0.25, 0.14))
