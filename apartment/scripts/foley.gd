class_name Foley
## Plays real recordings (Kenney RPG sounds, CC0, and the user's own recordings) at a point in
## the world, a little different each time. Used by everything you can handle in the flat.

const DIR := "res://assets/audio/foley/"

## Files started, newest last. The automated test reads this to check what was heard.
static var history: Array[String] = []
static var _cache := {}


static func stream(sound: String) -> AudioStream:
	if not _cache.has(sound):
		var path := sound if sound.begins_with("res://") else DIR + sound + ".ogg"
		_cache[sound] = load(path)
	return _cache[sound]


## One of several takes, e.g. pick("cloth", 4) -> "cloth1".."cloth4".
static func pick(prefix: String, count: int) -> String:
	var i := randi() % count + 1
	# Some takes in the pack are named "x", "x2", "x3" rather than "x1", "x2", ...
	if i == 1 and not ResourceLoader.exists(DIR + prefix + "1.ogg"):
		return prefix
	return prefix + str(i)


static func play(from: Node3D, sound: String, pos: Vector3, db := -14.0, pitch := 1.0, delay := 0.0) -> void:
	if not from.is_inside_tree():
		return
	if delay > 0.0:
		await from.get_tree().create_timer(delay).timeout
		if not from.is_inside_tree():
			return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(sound)
	p.bus = "Foley"
	p.volume_db = db + randf_range(-1.5, 1.0)
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.unit_size = 1.0
	p.max_distance = 16.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	from.get_viewport().add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	history.append(sound.get_file())
