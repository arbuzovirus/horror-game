extends Node3D
## A drawer: slides out along its local +Z and back in. The drawer box (mesh and collider) is
## this node's child.

@export var description := ""
@export var slide := 0.3
@export var open_time := 0.45
## What rattles inside when it moves.
@export_enum("none", "cutlery", "papers", "things") var contents := "none"

var opened := false
var _base: Vector3
var _busy := false


func _ready() -> void:
	_base = position


func interact(player: Node, at: Vector3) -> float:
	if _busy:
		return 0.3
	_busy = true
	opened = not opened
	var to := _base + transform.basis.z.normalized() * (slide if opened else 0.0)
	var tw := create_tween()
	tw.tween_interval(0.08)
	tw.tween_property(self, "position", to, open_time).set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT if opened else Tween.EASE_IN)
	tw.tween_callback(func() -> void: _busy = false)
	# Old wooden runners squeal, the drawer knocks against its stop, the contents shift.
	Foley.play(self, "creak3", at, -22.0, randf_range(1.6, 1.9), 0.08)
	Foley.play(self, Foley.pick("bookPlace", 3), at, -17.0 if not opened else -21.0,
			randf_range(1.0, 1.2), 0.08 + open_time * 0.95)
	match contents:
		"cutlery":
			Foley.play(self, Foley.pick("handleCoins", 2), at, -24.0, 0.75, 0.12)
		"papers":
			Foley.play(self, Foley.pick("bookFlip", 3), at, -24.0, 1.0, 0.15)
		"things":
			Foley.play(self, Foley.pick("handleSmallLeather", 2), at, -22.0, 1.0, 0.15)
	if opened and description != "":
		player._show_hint(description)
	return open_time + 0.15
