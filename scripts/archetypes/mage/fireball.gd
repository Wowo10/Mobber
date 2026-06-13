extends "res://scripts/archetypes/projectile_base.gd"

const SPEED = 500.0
const ACCELERATION = 900.0
const RANGE = 900.0
const EXPLOSION_RADIUS = 120.0
const DAMAGE = 60.0
const KNOCKBACK = 8000.0

var skill_level: int = 0
var _exploded := false
var _returning := false
var _current_speed := SPEED

func _ready() -> void:
	$SfxFire.play()

func _process(_delta: float) -> void:
	queue_redraw()

func _physics_process(delta: float) -> void:
	var prev_pos := global_position
	if _returning:
		_current_speed += ACCELERATION * delta
	if _returning:
		if player_ref != null and is_instance_valid(player_ref):
			direction = (player_ref.global_position - global_position).normalized()
			var ret_step := direction * _current_speed * delta
			global_position += ret_step
			_check_hit(prev_pos)
			if global_position.distance_to(player_ref.global_position) < player_ref.radius + 24.0:
				queue_free()
		else:
			queue_free()
		return
	var step := direction * _current_speed * delta
	global_position += step
	_distance_traveled += step.length()
	if _distance_traveled >= RANGE:
		_returning = true
		return
	_check_hit(prev_pos)

func _on_hit(_body: Node2D) -> void:
	_explode()

func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	_spawn_explosion_visual()
	_play_explode()
	if not visual_only:
		_apply_explosion_damage()
	queue_free()

func _play_explode() -> void:
	var sfx := $SfxExplode
	remove_child(sfx)
	get_parent().add_child(sfx)
	sfx.global_position = global_position
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

func _apply_explosion_damage() -> void:
	var radius := EXPLOSION_RADIUS * (1.0 + 0.25 * skill_level)
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 1
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var body = hit["collider"]
		if body.has_method("take_damage"):
			var dir: Vector2 = (body.global_position - global_position).normalized()
			body.take_damage(DAMAGE, dir * KNOCKBACK, player_ref)

func _spawn_explosion_visual() -> void:
	var p := CPUParticles2D.new()
	p.global_position = global_position
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 28
	p.lifetime = 0.45
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 220.0
	p.initial_velocity_max = 520.0
	p.scale_amount_min = 2.5
	p.scale_amount_max = 6.0
	p.color = Color(1.0, 0.4, 0.05, 1.0)
	ParticleUtils.polish(p)
	p.emitting = true
	get_parent().add_child(p)
	get_tree().create_timer(p.lifetime + 0.2).timeout.connect(p.queue_free)

func _draw() -> void:
	draw_circle(Vector2.ZERO, 22.0, Color(1.0, 0.45, 0.1))
	draw_circle(Vector2.ZERO, 13.0, Color(1.0, 0.85, 0.3))
