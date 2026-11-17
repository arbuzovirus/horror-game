extends Node3D
## Something small to look at (E shows its description) and, if take is on, to pick up.
## The sound is the object itself being touched or lifted, by what it's made of.

@export var title := ""
@export_multiline var description := ""
@export var take := false
@export_enum("wood", "fabric", "metal", "keys", "paper", "book", "glass", "ceramic", "small") var material := "wood"


func interact(player: Node, at: Vector3) -> float:
	_sound(at, take)
	if take:
		player.inventory.append(title)
		player._show_hint("Взято: %s.%s" % [title, (" " + description) if description != "" else ""])
		# Gone from where it lay once the hand has it.
		get_tree().create_timer(0.25).timeout.connect(queue_free)
		return 0.6
	if description != "":
		player._show_hint(description)
	return 0.5


func _sound(at: Vector3, lift: bool) -> void:
	var d := 0.12 if lift else 0.08
	match material:
		"wood":
			Foley.play(self, Foley.pick("bookPlace", 3), at, -24.0, randf_range(1.1, 1.3), d)
		"fabric":
			Foley.play(self, Foley.pick("cloth", 4), at, -20.0, 1.0, d)
		"metal":
			Foley.play(self, "metalClick", at, -23.0, randf_range(0.9, 1.1), d)
		"keys":
			Foley.play(self, Foley.pick("handleCoins", 2), at, -22.0, randf_range(1.15, 1.3), d)
		"paper":
			Foley.play(self, Foley.pick("bookFlip", 3), at, -20.0, 1.0, d)
		"book":
			Foley.play(self, "bookClose" if lift else Foley.pick("bookFlip", 3), at, -19.0, 1.0, d)
		"glass", "ceramic":
			Foley.play(self, Foley.pick("bookPlace", 3), at, -24.0, randf_range(1.6, 1.8), d)
		"small":
			Foley.play(self, Foley.pick("handleSmallLeather", 2), at, -22.0, 1.1, d)
