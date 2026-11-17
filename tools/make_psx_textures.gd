extends SceneTree
## Paints the low-resolution PS1-style textures into assets/psx.
## Run:  godot --headless --path . --script tools/make_psx_textures.gd

const OUT := "res://assets/psx/"
const SRC := "res://assets/textures/"

var fnl := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 1986
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.fractal_octaves = 3
	fnl.frequency = 1.0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var plaster := _src("worn_plaster_wall")
	var peel := _src("peeling_painted_wall")
	var concrete := _src("concrete_floor_worn_001")
	var metal := _src("rusty_painted_metal")
	_wall(plaster, peel)
	_tinted("plaster", plaster, Color(0.86, 0.84, 0.76), 0.25)
	_tinted("concrete", concrete, Color(0.62, 0.6, 0.56), 0.45)
	_tinted("metal_teal", metal, Color(0.42, 0.8, 0.72), 0.2)
	_tinted("metal_grey", metal, Color(0.5, 0.5, 0.48), 0.3, true)
	_tile()
	_door()
	_door_metal()
	_window()
	_panel()
	_mailbox()
	_rail()
	_wood()
	_doormat()
	_blob("peel_a", 11, false)
	_blob("peel_b", 23, false)
	_blob("stain", 37, true)
	_paper("paper_a", 5)
	_paper("paper_b", 9)
	_figure()
	print("textures done")
	quit()


func _src(n: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC + n + "_diff.jpg"))
	img.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	return img


func _new(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


func _save(img: Image, n: String) -> void:
	img.save_png(ProjectSettings.globalize_path(OUT + n + ".png"))


## Noise in 0..1 that wraps seamlessly across a texture `w` pixels wide.
func _cn(x: float, y: float, w: float, f: float, seed: float) -> float:
	var a := TAU * x / w
	var r := w * f / TAU
	return fnl.get_noise_3d(cos(a) * r + seed * 17.0, sin(a) * r, y * f + seed * 5.0) * 0.5 + 0.5


func _mul(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0, 1), clampf(c.g * k, 0, 1), clampf(c.b * k, 0, 1), 1.0)


func _lum(c: Color) -> float:
	return (c.r + c.g + c.b) / 3.0


## One storey of wall, 1.5 m wide and 3 m tall: baseboard, oil paint, dirty line, whitewash.
func _wall(plaster: Image, peel: Image) -> void:
	var img := _new(128, 256)
	var teal := Color(0.12, 0.47, 0.42)
	for y in 256:
		var h := 3.0 * (1.0 - (y + 0.5) / 256.0)
		for x in 128:
			var pl := plaster.get_pixel(x, y % 128)
			var pt := peel.get_pixel(x, y % 128)
			var white := _mul(Color(pl.r * 0.95, pl.g * 0.93, pl.b * 0.84), lerpf(0.72, 1.08, _cn(x, y, 128, 0.012, 1)))
			var streak := maxf(_cn(x, y * 0.08, 128, 0.09, 5) - 0.55, 0.0) / 0.45
			white = _mul(white, 1.0 - 0.3 * streak * clampf((h - 1.3) / 1.2, 0, 1))
			var lum := _lum(pt)
			var chip := 1.0 - smoothstep(0.06, 0.16, pt.r - pt.b)
			var paint := _mul(teal, lum * 2.6).lerp(_mul(pt, 0.85), chip)
			var n := _cn(x, y, 128, 0.02, 2)
			var th := 0.66 - 0.12 * clampf(1.0 - h, 0, 1)
			if n > th:
				paint = Color(pl.r * 0.6, pl.g * 0.56, pl.b * 0.5)
				if n > th + 0.1:
					# Deep patches go down to the brick.
					var brick := 0.75 if (y % 8 == 0 or (x + (y / 8 % 2) * 8) % 16 == 0) else 1.0
					paint = _mul(Color(0.42, 0.2, 0.14), brick * lerpf(0.7, 1.1, lum * 2.0))
			elif n > th - 0.012:
				paint = _mul(paint, 1.3)
			paint = _mul(paint, lerpf(0.5, 1.0, smoothstep(0.0, 0.5, h)))
			var edge := 1.45 + (_cn(x, 0, 128, 0.15, 3) - 0.5) * 0.03
			var col := paint if h < edge else white
			if absf(h - edge) < 0.018:
				col = _mul(col, 0.55)
			if h < 0.1:
				col = _mul(Color(0.13, 0.07, 0.05), lum * 2.2)
			if h > 2.55:
				col = _mul(col, lerpf(1.0, 0.72, (h - 2.55) / 0.45))
			img.set_pixel(x, y, col)
	_save(img, "wall")


func _tinted(n: String, src: Image, tint: Color, grime: float, grey := false) -> void:
	var img := _new(128, 128)
	for y in 128:
		for x in 128:
			var c := src.get_pixel(x, y)
			if grey:
				var l := _lum(c)
				c = Color(l, l, l)
			var g := 1.0 - grime * _cn(x, y, 128, 0.03, 7)
			img.set_pixel(x, y, Color(c.r * tint.r * g, c.g * tint.g * g, c.b * tint.b * g, 1.0))
	_save(img, n)


## Small two-colour floor tiles, cracked and dirty.
func _tile() -> void:
	var img := _new(64, 64)
	for ty in 4:
		for tx in 4:
			var base := Color(0.42, 0.19, 0.13) if (tx + ty) % 2 == 0 else Color(0.58, 0.48, 0.3)
			var k := rng.randf_range(0.75, 1.05)
			if rng.randf() < 0.1:
				base = Color(0.2, 0.19, 0.18)
			for y in 16:
				for x in 16:
					var px := tx * 16 + x
					var py := ty * 16 + y
					var c := _mul(base, k * lerpf(0.75, 1.05, _cn(px, py, 64, 0.11, 4)))
					if x == 0 or y == 0:
						c = Color(0.1, 0.09, 0.08)
					img.set_pixel(px, py, c)
	_save(img, "tile")


## Quilted leatherette apartment door with brass studs.
func _door() -> void:
	var img := _new(64, 128)
	for y in 128:
		for x in 64:
			var c := _mul(Color(0.75, 0.72, 0.7), lerpf(0.7, 1.0, _cn(x, y, 64, 0.06, 8)))
			var a := (x + y) % 16
			var b := (x - y + 256) % 16
			if a == 0 or b == 0:
				c = _mul(c, 0.55)
			elif a == 1 or b == 1:
				c = _mul(c, 1.18)
			if (a == 0 and b == 0):
				c = Color(0.85, 0.7, 0.35)
			if x < 2 or x > 61 or y < 2 or y > 125:
				c = _mul(c, 0.45)
			img.set_pixel(x, y, c)
	# Peephole, lock plate, handle.
	for p in [Vector2i(32, 40), Vector2i(31, 40), Vector2i(32, 41), Vector2i(31, 41)]:
		img.set_pixel(p.x, p.y, Color(0.05, 0.05, 0.06))
	img.set_pixel(31, 40, Color(0.5, 0.55, 0.6))
	img.fill_rect(Rect2i(52, 62, 6, 14), Color(0.45, 0.42, 0.36))
	img.fill_rect(Rect2i(53, 66, 8, 2), Color(0.6, 0.57, 0.5))
	img.fill_rect(Rect2i(54, 72, 2, 2), Color(0.05, 0.05, 0.05))
	_save(img, "door")


## Riveted steel entrance door leaf.
func _door_metal() -> void:
	var img := _new(64, 128)
	for y in 128:
		for x in 64:
			var r := _cn(x, y, 64, 0.05, 12)
			var c := _mul(Color(0.3, 0.31, 0.3), lerpf(0.7, 1.05, _cn(x, y, 64, 0.2, 13)))
			if r > 0.62:
				c = c.lerp(Color(0.38, 0.17, 0.07), clampf((r - 0.62) * 6.0, 0, 1))
			if x < 3 or x > 60 or y < 3 or y > 124 or absi(y - 64) < 2:
				c = _mul(c, 0.6)
			if (x == 5 or x == 58) and y % 10 == 5 or (y == 6 or y == 121) and x % 10 == 5:
				c = Color(0.55, 0.55, 0.52)
			img.set_pixel(x, y, c)
	img.fill_rect(Rect2i(6, 58, 5, 16), Color(0.12, 0.12, 0.12))
	img.fill_rect(Rect2i(7, 60, 3, 3), Color(0.5, 0.5, 0.45))
	_save(img, "door_metal")


## Night outside: a dark sky and a neighbouring block with a few lit windows.
func _window() -> void:
	var img := _new(64, 64)
	for y in 64:
		for x in 64:
			var t := y / 63.0
			var c := Color(0.02, 0.035, 0.07).lerp(Color(0.07, 0.1, 0.16), t)
			c = _mul(c, lerpf(0.7, 1.2, _cn(x, y, 64, 0.05, 15)))
			img.set_pixel(x, y, c)
	for b in [[2, 30, 20], [24, 22, 26], [52, 34, 12]]:
		img.fill_rect(Rect2i(b[0], b[1], b[2], 64 - b[1]), Color(0.015, 0.02, 0.03))
		for wy in range(b[1] + 3, 62, 5):
			for wx in range(b[0] + 2, b[0] + b[2] - 2, 4):
				if rng.randf() < 0.13:
					img.fill_rect(Rect2i(wx, wy, 2, 2), Color(0.75, 0.6, 0.25))
	# Grime on the glass.
	for y in 64:
		for x in 64:
			var g := _cn(x, y, 64, 0.09, 16)
			if g > 0.6:
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color(0.1, 0.1, 0.09), (g - 0.6) * 1.5))
	_save(img, "window")


## Electrical panel with two meters.
func _panel() -> void:
	var img := _new(64, 64)
	for y in 64:
		for x in 64:
			var c := _mul(Color(0.36, 0.4, 0.38), lerpf(0.7, 1.05, _cn(x, y, 64, 0.1, 18)))
			var r := _cn(x, y, 64, 0.06, 19)
			if r > 0.66:
				c = c.lerp(Color(0.35, 0.16, 0.07), 0.8)
			if x < 2 or x > 61 or y < 2 or y > 61 or x == 32:
				c = _mul(c, 0.45)
			img.set_pixel(x, y, c)
	for cx in [16, 48]:
		for y in range(-9, 10):
			for x in range(-9, 10):
				var d := sqrt(x * x + y * y)
				if d < 9.0:
					var c := Color(0.07, 0.07, 0.07) if d > 7.0 else Color(0.62, 0.6, 0.5)
					if d < 7.0 and y == 2 and absi(x) < 5:
						c = Color(0.1, 0.1, 0.1)
					img.set_pixel(cx + x, 22 + y, c)
	# Warning sign.
	for y in 10:
		for x in range(-y, y + 1):
			img.set_pixel(32 + x / 2 - 16, 44 + y, Color(0.75, 0.62, 0.1))
	img.fill_rect(Rect2i(15, 48, 2, 4), Color(0.05, 0.05, 0.05))
	img.fill_rect(Rect2i(42, 44, 12, 8), Color(0.12, 0.12, 0.12))
	_save(img, "panel")


func _mailbox() -> void:
	var img := _new(32, 32)
	for y in 32:
		for x in 32:
			var c := _mul(Color(0.16, 0.42, 0.4), lerpf(0.65, 1.05, _cn(x, y, 32, 0.12, 21)))
			if _cn(x, y, 32, 0.2, 22) > 0.68:
				c = c.lerp(Color(0.33, 0.15, 0.07), 0.8)
			if x == 0 or y == 0 or x == 31 or y == 31:
				c = Color(0.03, 0.05, 0.05)
			elif x == 1 or y == 1:
				c = _mul(c, 1.3)
			img.set_pixel(x, y, c)
	img.fill_rect(Rect2i(5, 6, 22, 2), Color(0.02, 0.02, 0.02))
	for i in 3:
		img.fill_rect(Rect2i(11 + i * 4, 18, 2, 2), Color(0.02, 0.02, 0.02))
	img.fill_rect(Rect2i(15, 25, 2, 3), Color(0.5, 0.5, 0.45))
	_save(img, "mailbox")


## Railing bars with a see-through background.
func _rail() -> void:
	var img := _new(32, 64)
	img.fill(Color(0, 0, 0, 0))
	for y in 64:
		for x in 32:
			var bar := x % 8 < 2
			var rail := y < 2 or (y >= 54 and y < 57)
			if bar or rail:
				var c := _mul(Color(0.1, 0.3, 0.28), lerpf(0.6, 1.1, _cn(x, y, 32, 0.15, 24)))
				if _cn(x, y, 32, 0.1, 25) > 0.62:
					c = Color(0.3, 0.14, 0.07)
				img.set_pixel(x, y, c)
	_save(img, "rail")


func _wood() -> void:
	var img := _new(32, 32)
	for y in 32:
		for x in 32:
			var g := _cn(x * 0.25, y, 32, 0.3, 27)
			img.set_pixel(x, y, _mul(Color(0.3, 0.17, 0.09), lerpf(0.6, 1.1, g)))
	_save(img, "wood")


func _doormat() -> void:
	var img := _new(32, 16)
	for y in 16:
		for x in 32:
			var c := Color(0.4, 0.1, 0.08) if (x / 4) % 2 == 0 else Color(0.14, 0.24, 0.12)
			c = _mul(c, lerpf(0.55, 1.0, _cn(x, y, 32, 0.25, 29)))
			if x == 0 or x == 31 or y == 0 or y == 15:
				c = _mul(c, 0.5)
			img.set_pixel(x, y, c)
	_save(img, "doormat")


## An irregular patch: bare plaster and brick (peel) or a dark smear (stain).
func _blob(n: String, seed: int, stain: bool) -> void:
	var img := _new(64, 64)
	img.fill(Color(0, 0, 0, 0))
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			var v := fnl.get_noise_2d(x * 0.045 + seed, y * 0.045) * 0.5 + 0.5
			var s := v + (0.75 - d) * 0.9
			if s < 0.78:
				continue
			var g := lerpf(0.7, 1.05, fnl.get_noise_2d(x * 0.3, y * 0.3 + seed) * 0.5 + 0.5)
			var c: Color
			if stain:
				c = _mul(Color(0.2, 0.03, 0.02), g * lerpf(1.3, 0.6, clampf((s - 0.78) * 2.0, 0, 1)))
			elif s > 1.05:
				var mortar := y % 8 == 0 or (x + (y / 8 % 2) * 8) % 16 == 0
				c = _mul(Color(0.4, 0.19, 0.13), g * (0.7 if mortar else 1.0))
			elif s < 0.8:
				c = _mul(Color(0.75, 0.75, 0.68), g)
			else:
				c = _mul(Color(0.5, 0.47, 0.42), g)
			img.set_pixel(x, y, c)
	_save(img, n)


func _paper(n: String, seed: int) -> void:
	var img := _new(32, 32)
	img.fill(Color(0, 0, 0, 0))
	for y in 32:
		for x in 32:
			var edge := fnl.get_noise_2d(x * 0.2 + seed, y * 0.2) * 3.0
			if x < 3 + edge or x > 28 + edge or y < 2 - edge or y > 29 - edge:
				continue
			var c := _mul(Color(0.62, 0.6, 0.5), lerpf(0.7, 1.0, fnl.get_noise_2d(x * 0.1, y * 0.1 + seed) * 0.5 + 0.5))
			if y % 4 == 1 and x > 6 and x < 26 and (x + y * seed) % 7 != 0:
				c = _mul(c, 0.45)
			img.set_pixel(x, y, c)
	_save(img, n)


func _seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return (p - (a + ab * t)).length()


## A tall, thin silhouette with pale eyes.
func _figure() -> void:
	var img := _new(64, 128)
	img.fill(Color(0, 0, 0, 0))
	var parts := [
		[Vector2(32, 12), Vector2(32, 19), 6.5], [Vector2(32, 22), Vector2(32, 31), 2.4],
		[Vector2(24, 33), Vector2(40, 33), 3.2], [Vector2(32, 33), Vector2(32, 68), 5.6],
		[Vector2(22, 34), Vector2(18, 70), 2.2], [Vector2(18, 70), Vector2(19, 92), 1.8],
		[Vector2(42, 34), Vector2(46, 70), 2.2], [Vector2(46, 70), Vector2(45, 92), 1.8],
		[Vector2(29, 68), Vector2(27, 127), 3.0], [Vector2(35, 68), Vector2(37, 127), 3.0],
	]
	for y in 128:
		for x in 64:
			var p := Vector2(x + 0.5, y + 0.5)
			for s in parts:
				if _seg(p, s[0], s[1]) < s[2]:
					img.set_pixel(x, y, Color(0.012, 0.012, 0.016, 1.0))
					break
	for e in [Vector2i(29, 14), Vector2i(35, 14)]:
		img.set_pixel(e.x, e.y, Color(0.8, 0.8, 0.72))
	_save(img, "figure")
