@tool
extends Node3D
## One room of the flat. Puts everything in it on the room's render layer so that the room's own
## lamps light only this room (lights cast no shadows here, as on the PS1, so without this a lamp
## would shine straight through the walls). A node with a "layers" meta (a door between two rooms)
## keeps that mask for itself and everything under it.

## Render layer bit of this room, 0-19 (shown in the editor as layer bit + 1).
@export_range(0, 19) var layer_bit := 15


func _ready() -> void:
	_apply(self, 1 << layer_bit)


func _apply(n: Node, mask: int) -> void:
	if n.has_meta("layers"):
		mask = int(n.get_meta("layers"))
	if n is Light3D:
		(n as Light3D).light_cull_mask = mask | int(n.get_meta("extra_cull", 0))
	if n is Decal:
		(n as Decal).cull_mask = mask
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = mask
	for c in n.get_children():
		_apply(c, mask)
