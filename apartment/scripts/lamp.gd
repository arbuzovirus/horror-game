extends Node3D
## A light fitting: an OmniLight3D called "Light" and a mesh called "Bulb" whose material shows
## whether it's lit. Switched by a wall switch (same group) or, with pull_switch, by hand.

@export var on := false
@export var energy := 1.0
@export var flicker := 0.0
## Desk and table lamps have their own switch you can press.
@export var pull_switch := false
@export var on_material: Material
@export var off_material: Material

var _t := 0.0


func _ready() -> void:
	_apply()


func set_on(value: bool) -> void:
	on = value
	_apply()


func _apply() -> void:
	var light := get_node_or_null("Light") as Light3D
	if light:
		light.visible = on
		light.light_energy = energy
	var bulb := get_node_or_null("Bulb") as MeshInstance3D
	if bulb:
		bulb.material_override = on_material if on else off_material


func interact(player: Node, at: Vector3) -> float:
	if not pull_switch:
		return 0.0
	# The little rotary switch on the lamp's base: a dry click, then the filament.
	Foley.play(self, "metalClick", at, -21.0, randf_range(1.55, 1.7), 0.05)
	get_tree().create_timer(0.07).timeout.connect(func() -> void: set_on(not on))
	return 0.4


func _process(delta: float) -> void:
	if not on or flicker <= 0.0:
		return
	_t -= delta
	if _t <= 0.0:
		_t = randf_range(0.04, 0.4)
		var light := get_node_or_null("Light") as Light3D
		if light:
			light.light_energy = energy * (1.0 - randf() * flicker)
