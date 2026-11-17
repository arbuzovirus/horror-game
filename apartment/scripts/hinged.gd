extends Node3D
## Anything on a hinge: room doors, the flat's steel door, wardrobe and cabinet doors, the fridge,
## the oven flap. This node sits on the hinge line; the leaf (mesh and collider) is its child.
## E opens or closes it with a short animation and the sounds of what physically happens.

@export var description := ""
## Fully open angle in degrees; the sign sets the swing direction.
@export var open_angle := 95.0
## "y" for doors, "x" for flaps that drop down (oven).
@export_enum("y", "x") var axis := "y"
@export var open_time := 0.9
@export var opened := false
## Start this far open (degrees) without counting as fully open; 0 = closed or fully open.
@export var ajar_angle := 0.0
@export var locked := false
@export var locked_text := "Заперто."
@export_enum("wood_door", "metal_door", "cabinet", "fridge", "small_metal", "oven") var kind := "wood_door"

var _base: Vector3
var _busy := false
var _ajar := false


func _ready() -> void:
	_base = rotation
	if ajar_angle != 0.0:
		rotation = _rot(ajar_angle)
		_ajar = true
	elif opened:
		rotation = _rot(open_angle)


func _rot(deg: float) -> Vector3:
	var r := _base
	if axis == "y":
		r.y += deg_to_rad(deg)
	else:
		r.x += deg_to_rad(deg)
	return r


func interact(player: Node, at: Vector3) -> float:
	if _busy:
		return 0.3
	if locked:
		_sounds_locked(at)
		player._show_hint(locked_text)
		return 1.0
	_busy = true
	# A door left ajar is simply pushed open: no handle, the latch isn't engaged.
	var pushed := _ajar
	_ajar = false
	var opening := not opened
	opened = opening
	var start := 0.05 if pushed else (0.18 if opening else 0.0)   # the hand works the handle first
	var tw := create_tween()
	tw.tween_interval(start)
	tw.tween_property(self, "rotation", _rot(open_angle if opening else 0.0), open_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT if opening else Tween.EASE_IN)
	tw.tween_callback(func() -> void: _busy = false)
	if pushed:
		Foley.play(self, "res://assets/audio/door_creak_long.mp3" if kind == "metal_door" else Foley.pick("creak", 2),
				at, -14.0, 1.0, 0.05)
	elif opening:
		_sounds_open(at)
		if description != "":
			player._show_hint(description)
	else:
		_sounds_close(at, open_time)
	return start + open_time + 0.1


func _sounds_open(at: Vector3) -> void:
	match kind:
		"wood_door":
			Foley.play(self, "metalClick", at, -20.0, 0.95, 0.04)             # hand on the handle
			Foley.play(self, "metalLatch", at, -17.0, 1.1, 0.12)              # latch slides out of the strike
			Foley.play(self, Foley.pick("doorOpen_", 2), at, -13.0, randf_range(0.92, 1.05), 0.2)
		"metal_door":
			Foley.play(self, "metalClick", at, -15.0, 0.7, 0.04)
			Foley.play(self, "metalLatch", at, -10.0, 0.6, 0.14)              # heavy bolt
			Foley.play(self, "res://assets/audio/door_creak_long.mp3", at, -16.0, 1.15, 0.25)
		"cabinet":
			Foley.play(self, "creak3", at, -21.0, randf_range(1.2, 1.5), 0.1) # dry little hinge
			Foley.play(self, Foley.pick("bookPlace", 3), at, -26.0, 1.4, 0.05)  # catch lets go
		"fridge":
			Foley.play(self, "metalLatch", at, -16.0, 1.35, 0.04)             # handle lever
			Foley.play(self, Foley.pick("cloth", 4), at, -17.0, 0.6, 0.16)    # the seal unsticks
		"small_metal":
			Foley.play(self, "metalClick", at, -19.0, 1.25, 0.05)
			Foley.play(self, "creak3", at, -25.0, 1.7, 0.15)
		"oven":
			Foley.play(self, "metalClick", at, -18.0, 0.9, 0.05)
			Foley.play(self, "creak3", at, -20.0, 1.0, 0.15)


func _sounds_close(at: Vector3, t: float) -> void:
	match kind:
		"wood_door":
			Foley.play(self, "creak%d" % (randi() % 2 + 1), at, -22.0, 1.1, 0.05)
			Foley.play(self, Foley.pick("doorClose_", 4), at, -11.0, randf_range(0.95, 1.05), t * 0.92)
			Foley.play(self, "metalLatch", at, -17.0, 1.05, t * 0.95)         # latch catches
		"metal_door":
			Foley.play(self, "res://assets/audio/door_close_metal.mp3", at, -9.0, 1.0, t * 0.85)
		"cabinet":
			Foley.play(self, "creak3", at, -24.0, 1.4, 0.05)
			Foley.play(self, Foley.pick("bookPlace", 3), at, -16.0, randf_range(0.8, 0.95), t * 0.95)
		"fridge":
			Foley.play(self, Foley.pick("doorClose_", 4), at, -15.0, 1.25, t * 0.9)
			Foley.play(self, "metalLatch", at, -19.0, 1.45, t * 0.95)
		"small_metal":
			Foley.play(self, "metalLatch", at, -16.0, 1.35, t * 0.9)
		"oven":
			Foley.play(self, Foley.pick("doorClose_", 4), at, -15.0, 1.3, t * 0.9)


func _sounds_locked(at: Vector3) -> void:
	var heavy := kind == "metal_door"
	Foley.play(self, "metalClick", at, -18.0, 0.7 if heavy else 0.85, 0.08)
	Foley.play(self, "metalLatch", at, -11.0, 0.6 if heavy else 0.85, 0.2)
