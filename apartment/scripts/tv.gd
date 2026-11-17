extends Node3D
## An old CRT set. E turns the knob: on, it warms up into snow with the hiss of a dead channel and
## lights the room a flickering blue; off, the picture collapses and the room goes dark.

@export var on := true
@export var screen_off: Material
@export var screen_on: Material
@export var glow := 0.9

var _t := 0.0


func _ready() -> void:
	var hiss := get_node_or_null("Sound") as AudioStreamPlayer3D
	if hiss and hiss.stream is AudioStreamMP3:
		(hiss.stream as AudioStreamMP3).loop = true
	_apply(true)


func _apply(instant := false) -> void:
	var screen := get_node_or_null("Screen") as MeshInstance3D
	if screen:
		screen.material_override = screen_on if on else screen_off
	var light := get_node_or_null("Glow") as Light3D
	if light:
		light.visible = on
	var hiss := get_node_or_null("Sound") as AudioStreamPlayer3D
	if hiss:
		if on and not hiss.playing:
			hiss.play(randf() * 20.0 if instant else 0.0)
		elif not on:
			hiss.stop()


func interact(_player: Node, at: Vector3) -> float:
	on = not on
	# The power knob on the front panel.
	Foley.play(self, "metalClick", at, -15.0, 0.75, 0.04)
	Foley.play(self, "metalLatch", at, -22.0, 1.5, 0.1)
	if on:
		# The tube needs a moment; then the channel noise comes up.
		Foley.play(self, "res://assets/audio/tv_channel.mp3", global_position, -16.0, 1.0, 0.5)
		get_tree().create_timer(0.5).timeout.connect(func() -> void: _apply())
	else:
		_apply()
	return 0.8


func _process(delta: float) -> void:
	if not on:
		return
	_t -= delta
	if _t <= 0.0:
		_t = randf_range(0.03, 0.12)
		var light := get_node_or_null("Glow") as Light3D
		if light:
			light.light_energy = glow * randf_range(0.55, 1.0)
		var screen := get_node_or_null("Screen") as MeshInstance3D
		if screen and screen_on is ShaderMaterial:
			# Jump to a different frame of the snow strip.
			(screen_on as ShaderMaterial).set_shader_parameter(&"uv_offset", Vector2(0.0, float(randi() % 4) * 0.25))
