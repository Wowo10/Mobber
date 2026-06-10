extends Node2D

const RADIUS = 220.0
const WINDUP = 1.5
const BASE_DAMAGE = 40.0
const PER_MOB_DAMAGE = 15.0
const KNOCKBACK_FORCE = 5000.0

var player_ref: Node = null
var visual_only := false
var skill_level: int = 0

var _elapsed := 0.0
var _detonated := false

func _ready() -> void:
	if not visual_only:
		call_deferred("_check_detonation_setup")

func _check_detonation_setup() -> void:
	pass  # detonation driven by _process

func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if not _detonated and _elapsed >= WINDUP:
		_detonated = true
		if not visual_only:
			_detonate()
		else:
			_spawn_burst()
		get_tree().create_timer(0.4).timeout.connect(queue_free)

func _detonate() -> void:
	var radius := RADIUS * (1.0 + 0.25 * skill_level)
	var force := KNOCKBACK_FORCE * (1.0 + 0.2 * skill_level)
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 1
	var hits := get_world_2d().direct_space_state.intersect_shape(query, 32)
	var mobs: Array = []
	for h in hits:
		var body = h["collider"]
		if body.has_method("take_damage"):
			mobs.append(body)
	var damage: float = BASE_DAMAGE + PER_MOB_DAMAGE * max(0, mobs.size() - 1)
	for mob in mobs:
		var dir: Vector2 = (global_position - mob.global_position).normalized()
		mob.take_damage(damage, dir * force, player_ref)
	if player_ref:
		player_ref.shake_camera(0.5, 12.0)
	_spawn_burst()

func _spawn_burst() -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 36
	p.lifetime = 0.35
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 150.0
	p.initial_velocity_max = 500.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.5
	p.color = Color(0.65, 0.1, 1.0, 0.9)
	ParticleUtils.polish(p)
	p.emitting = true
	add_child(p)

func _draw() -> void:
	var draw_radius := RADIUS * (1.0 + 0.25 * skill_level)
	if _detonated:
		var t := 1.0 - (_elapsed - WINDUP) / 0.4
		if t > 0.0:
			draw_arc(Vector2.ZERO, draw_radius, 0.0, TAU, 64,
				Color(0.65, 0.1, 1.0, 0.8 * t), 4.0 * t)
		return
	var pulse := sin(_elapsed * TAU / WINDUP * 2.0) * 0.5 + 0.5
	var r := draw_radius * (0.3 + 0.7 * (_elapsed / WINDUP))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64,
		Color(0.6, 0.05, 0.95, 0.25 + 0.4 * pulse), 3.0)
	draw_arc(Vector2.ZERO, draw_radius, 0.0, TAU, 64,
		Color(0.5, 0.05, 0.8, 0.15 + 0.15 * pulse), 1.5)
