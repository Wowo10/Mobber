extends Area2D

var player_ref: Node = null
var visual_only := false

var _triggered := false
var _anim_t := 0.0

func _ready() -> void:
	monitoring = not visual_only
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if _triggered or not body.has_method("take_damage"):
		return
	_triggered = true
	monitoring = false
	body.take_damage(999999.0, Vector2.ZERO, player_ref)
	_notify_archetype()
	_spawn_burst()
	get_tree().create_timer(0.4).timeout.connect(queue_free)

func _notify_archetype() -> void:
	if player_ref and is_instance_valid(player_ref):
		player_ref.notify_trap_triggered()

func _spawn_burst() -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 9
	p.lifetime = 0.25
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 180.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	p.color = Color(0.6, 0.1, 0.9, 0.9)
	ParticleUtils.polish(p)
	p.emitting = true
	add_child(p)

func _process(delta: float) -> void:
	_anim_t += delta
	queue_redraw()

func _draw() -> void:
	if _triggered:
		return
	var pulse := sin(_anim_t * 4.0) * 0.15 + 0.85
	var c := Color(0.75, 0.15, 1.0, 0.95 * pulse)
	var r := 16.0
	draw_line(Vector2(-r, -r), Vector2(r, r), c, 4.0)
	draw_line(Vector2(r, -r), Vector2(-r, r), c, 4.0)
	draw_arc(Vector2.ZERO, r * 1.15, 0.0, TAU, 24, Color(0.55, 0.05, 0.8, 0.75 * pulse), 2.5)
	draw_arc(Vector2.ZERO, r * 1.7, 0.0, TAU, 32, Color(0.4, 0.0, 0.65, 0.35 * pulse), 1.5)
