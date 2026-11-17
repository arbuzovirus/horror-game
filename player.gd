extends CharacterBody3D
## First-person walker: WASD, mouse look, Shift to run, F flashlight, E interact.

const WALK_SPEED := 2.2
const RUN_SPEED := 3.8
const MOUSE_SENS := 0.0022
const GRAVITY := 14.0

var camera: Camera3D
var flashlight: SpotLight3D
var hint: Label
var _pitch := 0.0
var _bob := 0.0
var _hint_time := 0.0
var auto_forward := false  # used by the automated walk test
var _step_dist := 0.0
var _last_step := -1
var _steps: Array[AudioStream] = []
var _step_player: AudioStreamPlayer
var _knocks: Array[AudioStream] = []
var _last_knock := -1
var _sfx := {}
var _busy_until := 0
var played: Array[String] = []  # every foley sound started, for the automated test
var inventory: Array[String] = []

const FOLEY := "res://assets/audio/foley/"


func _ready() -> void:
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)

	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.75
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.875
	add_child(col)

	camera = Camera3D.new()
	camera.position.y = 1.62
	camera.fov = 72.0
	camera.near = 0.03
	camera.far = 60.0
	camera.current = true
	add_child(camera)

	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(0.18, -0.2, -0.1)
	flashlight.light_color = Color(1.0, 0.93, 0.78)
	flashlight.light_energy = 3.2
	flashlight.spot_range = 11.0
	flashlight.spot_angle = 30.0
	flashlight.spot_angle_attenuation = 1.6
	flashlight.spot_attenuation = 1.4
	flashlight.shadow_enabled = false
	camera.add_child(flashlight)

	for i in 6:
		_steps.append(load("res://assets/audio/step_%d.wav" % i))
	for i in 3:
		_knocks.append(load("res://assets/audio/knock_%d.mp3" % (i + 1)))
	# Real recordings only (Kenney RPG sounds, CC0, and the user's own door recordings).
	for n in ["metalClick", "metalLatch", "creak1", "creak2", "creak3",
			"doorClose_1", "doorClose_2", "doorClose_3", "doorClose_4"]:
		_sfx[n] = load(FOLEY + n + ".ogg")
	_step_player = AudioStreamPlayer.new()
	_step_player.bus = "Reverb"
	_step_player.volume_db = -9.0
	add_child(_step_player)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Called by main.gd, which sits outside the PSX screen and receives the input.
func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		_pitch = clamp(_pitch - event.relative.y * MOUSE_SENS, -1.45, 1.45)
		camera.rotation.x = _pitch
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_F:
				flashlight.visible = not flashlight.visible
				# A small slide switch, right by the hand.
				_foley("metalClick", flashlight.global_position, -24.0, 1.75 if flashlight.visible else 1.6)
			KEY_E:
				_interact()


func _interact() -> void:
	# One action at a time: a hand can't try two doors at once.
	if Time.get_ticks_msec() < _busy_until:
		return
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * 2.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit:
		return
	# Things with their own behaviour (doors, drawers, switches, lamps, the TV, small objects)
	# have an interact() on the collider or one of its parents.
	var n: Node = hit.collider
	for i in 4:
		if n == null or n.has_method("interact"):
			break
		n = n.get_parent()
	if n and n.has_method("interact"):
		var t: float = n.interact(self, hit.position)
		_busy_until = Time.get_ticks_msec() + int(t * 1000.0)
		return
	if not hit.collider.has_meta("message"):
		return
	var thing: Node = hit.collider
	var at: Vector3 = hit.position
	var title := String(thing.name)
	_show_hint(thing.get_meta("message"))
	var took := 0.6
	if thing.has_node("Leaf"):
		took = _push_ajar_door(thing, at)
	elif title.begins_with("Door_"):
		took = _try_locked_door(at)
	elif title == "EntranceDoor":
		took = _try_steel_door(at)
	elif title == "Mailboxes":
		took = _try_mailbox(at)
	elif title.begins_with("Panel"):
		took = _try_panel(at)
	elif title.begins_with("Chute") or String(thing.get_meta("message")).begins_with("Мусоропровод"):
		took = _open_chute(at)
	elif title == "AtticLadder":
		took = _try_padlock(at)
	else:
		_foley("metalClick", at, -20.0, 0.9, 0.1)
	_busy_until = Time.get_ticks_msec() + int(took * 1000.0)


# Each action is split into what physically happens: the hand reaches it, the mechanism moves,
# and how it ends. The delays are when each part happens after the key press.

func _try_locked_door(at: Vector3) -> float:
	_foley("metalClick", at, -18.0, 0.8, 0.12)                   # hand closes on the handle
	_foley("metalLatch", at, -11.0, 0.82, 0.24)                  # handle down, bolt hits the strike
	if randf() < 0.55:
		_foley("metalLatch", at, -14.0, 0.78, 0.5)               # a second, harder tug
		if randf() < 0.5:
			_foley("creak3", at, -25.0, 0.65, 0.55)              # the old frame gives a little
	# Nobody opens, so knock.
	var i := randi() % _knocks.size()
	if i == _last_knock:
		i = (i + 1) % _knocks.size()
	_last_knock = i
	_foley_stream(_knocks[i], at, randf_range(-7.0, -4.0), randf_range(0.92, 1.05), 1.0)
	return 2.4


func _try_steel_door(at: Vector3) -> float:
	_foley("metalClick", at, -16.0, 0.62, 0.12)
	_foley("metalLatch", at, -9.0, 0.58, 0.24)                   # heavy bolt, no give
	_foley("doorClose_%d" % (randi() % 4 + 1), at, -15.0, 0.5, 0.3)   # leaf knocks against the frame
	_foley("metalLatch", at, -12.0, 0.55, 0.7)
	_foley("doorClose_%d" % (randi() % 4 + 1), at, -18.0, 0.48, 0.76)
	return 1.4


func _push_ajar_door(door: Node, at: Vector3) -> float:
	# The open door really moves a little on its hinges.
	var leaf: Node3D = door.get_node("Leaf")
	var start := leaf.rotation.y
	var tw := create_tween()
	tw.tween_interval(0.15)
	tw.tween_property(leaf, "rotation:y", start - 0.12, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(leaf, "rotation:y", start, 1.2).set_trans(Tween.TRANS_SINE)
	_foley("creak%d" % (randi() % 2 + 1), at, -13.0, 0.8, 0.15)
	_foley("creak3", at, -20.0, 0.7, 1.0)
	return 2.1


func _try_mailbox(at: Vector3) -> float:
	_foley("metalClick", at, -20.0, 1.35, 0.1)                   # fingertip on the tin flap
	_foley("metalLatch", at, -16.0, 1.45, 0.18)                  # locked, the little door rattles
	_foley("metalClick", at, -21.0, 1.25, 0.34)
	return 0.7


func _try_panel(at: Vector3) -> float:
	_foley("metalClick", at, -17.0, 1.05, 0.1)                   # the latch handle turns
	_foley("creak3", at, -25.0, 1.4, 0.18)                       # small hinge
	_foley("metalLatch", at, -13.0, 1.1, 0.24)                   # held by the lock
	return 0.8


func _open_chute(at: Vector3) -> float:
	_foley("metalClick", at, -16.0, 0.75, 0.1)
	_foley("creak1", at, -15.0, 0.72, 0.18)                      # the hatch swings out
	_foley("doorClose_%d" % (randi() % 4 + 1), at, -12.0, 0.66, 1.05)  # and drops back shut
	return 1.6


func _try_padlock(at: Vector3) -> float:
	_foley("metalClick", at, -18.0, 0.6, 0.1)                    # hand on the rung
	_foley("metalLatch", at, -12.0, 0.52, 0.32)                  # yanks the padlock
	_foley("metalLatch", at, -15.0, 0.48, 0.58)
	return 1.0


func _foley(sound: String, pos: Vector3, db: float, pitch: float, delay := 0.0) -> void:
	_foley_stream(_sfx[sound], pos, db, pitch, delay)


## Plays a recording at a point in the world, a little different each time.
func _foley_stream(stream: AudioStream, pos: Vector3, db: float, pitch: float, delay := 0.0) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "Foley"
	p.volume_db = db + randf_range(-1.5, 1.0)
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.unit_size = 1.2
	p.max_distance = 20.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	get_parent().add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	played.append(stream.resource_path.get_file())


func _show_hint(text: String) -> void:
	if hint:
		hint.text = text
		hint.modulate.a = 1.0
		_hint_time = 2.0


func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO
	if auto_forward or Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.z += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	dir = (global_transform.basis * dir)
	dir.y = 0.0
	dir = dir.normalized()

	var speed := RUN_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
	velocity.x = move_toward(velocity.x, dir.x * speed, 20.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, 20.0 * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	# Head bob.
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed > 0.3 and is_on_floor():
		_bob += delta * hspeed * 3.4
		_step_dist += delta * hspeed
		if _step_dist > (0.95 if hspeed > 3.0 else 0.72):
			_step_dist = 0.0
			var si := randi() % _steps.size()
			if si == _last_step:
				si = (si + 1) % _steps.size()
			_last_step = si
			_step_player.stream = _steps[si]
			_step_player.pitch_scale = randf_range(0.93, 1.07)
			_step_player.volume_db = (-14.0 if hspeed < 3.0 else -10.5) + randf_range(-1.5, 1.0)
			_step_player.play()
	camera.position.y = lerp(camera.position.y, 1.62 + sin(_bob * 2.0) * 0.035 * min(hspeed, 1.0), 12.0 * delta)
	camera.position.x = lerp(camera.position.x, cos(_bob) * 0.02 * min(hspeed, 1.0), 12.0 * delta)

	if hint and _hint_time > 0.0:
		_hint_time -= delta
		if _hint_time < 0.6:
			hint.modulate.a = max(_hint_time / 0.6, 0.0)
