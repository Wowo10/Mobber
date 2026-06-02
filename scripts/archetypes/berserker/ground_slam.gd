extends Node2D

const SLAM_RADIUS = 150.0
const SLAM_DAMAGE = 45.0
const SLAM_KNOCKBACK = 8000.0
const VISUAL_DURATION = 0.5

var player_ref: Node = null
var visual_only := false

var _elapsed := 0.0

func _ready() -> void:
	if not visual_only:
		call_deferred("_apply_damage")
	_spawn_particles()
	$SfxSlam.play()

func _apply_damage() -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = SLAM_RADIUS
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 1
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var body = hit["collider"]
		if body.has_method("take_damage"):
			var dir: Vector2 = (body.global_position - global_position).normalized()
			body.take_damage(SLAM_DAMAGE, dir * SLAM_KNOCKBACK, player_ref)

func _spawn_particles() -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 36
	p.lifetime = 0.5
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 100.0
	p.initial_velocity_max = 350.0
	p.scale_amount_min = 4.0
	p.scale_amount_max = 10.0
	p.color = Color(0.9, 0.3, 0.05, 1.0)
	p.emitting = true
	add_child(p)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= VISUAL_DURATION + 0.5:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	if _elapsed >= VISUAL_DURATION:
		return
	var t := 1.0 - (_elapsed / VISUAL_DURATION)
	draw_circle(Vector2.ZERO, SLAM_RADIUS, Color(0.9, 0.3, 0.05, 0.15 * t))
	draw_arc(Vector2.ZERO, SLAM_RADIUS * (0.7 + 0.3 * t), 0.0, TAU, 48, Color(0.95, 0.4, 0.1, 0.9 * t), 4.0)
