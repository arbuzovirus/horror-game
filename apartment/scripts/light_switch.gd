extends Node3D
## A wall switch. Toggles every lamp in its group (lamps add themselves to that group in their
## scenes), so a switch in the hall can work the bathroom light.

@export var lamp_group := ""
@export var on := false


func _ready() -> void:
	var rocker := get_node_or_null("Rocker") as Node3D
	if rocker:
		rocker.rotation.x = -0.25 if on else 0.25


func interact(_player: Node, at: Vector3) -> float:
	on = not on
	var rocker := get_node_or_null("Rocker") as Node3D
	if rocker:
		create_tween().tween_property(rocker, "rotation:x", -0.25 if on else 0.25, 0.05)
	# One short, dry click of the mechanism. Then the light comes (or goes).
	Foley.play(self, "metalClick", at, -19.0, randf_range(1.3, 1.45), 0.03)
	get_tree().create_timer(0.06).timeout.connect(_apply_lamps)
	return 0.35


func _apply_lamps() -> void:
	for lamp in get_tree().get_nodes_in_group(lamp_group):
		lamp.set_on(on)
