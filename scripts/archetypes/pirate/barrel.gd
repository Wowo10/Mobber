extends Node2D

const DETONATION_RADIUS = 170.0
const DETONATION_DAMAGE = 65.0
const KNOCKBACK_FORCE = 4500.0
const MAX_LIFETIME = 30.0

var player_ref: Node = null
var visual_only := false
var skill_level: int = 0

var _elapsed := 0.0
var _detonated := false
var _detonate_elapsed := 0.0

func _process(delta: float) -> void:
	if _detonated:
		_detonate_elapsed += delta
		queue_redraw()
		return
	_elapsed += delta
	if _elapsed >= MAX_LIFETIME:
		_trigger_detonate()
	queue_redraw()

func detonate() -> void:
	if _detonated:
		return
	_trigger_detonate()

func _trigger_detonate() -> void:
	_detonated = true
	if not visual_only:
		_do_damage()
	_spawn_explosion()
	get_tree().create_timer(0.6).timeout.connect(queue_free)

func _do_damage() -> void:
	var radius := DETONATION_RADIUS * (1.0 + 0.25 * skill_level)
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 1
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 32):
		var body = hit["collider"]
		if body.has_method("take_damage"):
			var dir: Vector2 = (body.global_position - global_position).normalized()
			body.take_damage(DETONATION_DAMAGE, dir * KNOCKBACK_FORCE, player_ref)

func _spawn_explosion() -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 72
	p.lifetime = 0.5
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 100.0
	p.initial_velocity_max = 480.0
	p.scale_amount_min = 4.0
	p.scale_amount_max = 13.0
	p.color = Color(1.0, 0.55, 0.1, 1.0)
	ParticleUtils.polish(p)
	p.emitting = true
	add_child(p)

func _draw() -> void:
	var det_radius := DETONATION_RADIUS * (1.0 + 0.25 * skill_level)
	if _detonated:
		var t := clampf(1.0 - _detonate_elapsed / 0.5, 0.0, 1.0)
		if t > 0.0:
			var ring_r := det_radius * (1.0 - t)
			draw_circle(Vector2.ZERO, ring_r, Color(1.0, 0.6, 0.1, 0.18 * t))
			draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 64,
				Color(1.0, 0.75, 0.2, 0.9 * t), 4.0)
		return
	var pulse := sin(_elapsed * 2.5) * 0.15 + 0.85
	draw_circle(Vector2.ZERO, 12.0, Color(0.5, 0.28, 0.08))
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 32, Color(0.3, 0.16, 0.04), 2.5)
	draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 32, Color(0.6, 0.6, 0.6, 0.85), 2.5)
	draw_line(Vector2(-6.0, -6.0), Vector2(6.0, 6.0), Color(1.0, 0.2, 0.1, 0.75), 2.0)
	draw_line(Vector2(6.0, -6.0), Vector2(-6.0, 6.0), Color(1.0, 0.2, 0.1, 0.75), 2.0)
	draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 32, Color(1.0, 0.55, 0.1, 0.25 * pulse), 2.0)
