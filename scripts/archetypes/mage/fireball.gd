extends Area2D

const SPEED = 700.0
const RANGE = 900.0
const EXPLOSION_RADIUS = 120.0
const DAMAGE = 60.0
const KNOCKBACK = 8000.0

var direction := Vector2.RIGHT
var player_ref: Node = null
var visual_only := false
var _distance_traveled := 0.0
var _exploded := false

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	var step := direction * SPEED * delta
	global_position += step
	_distance_traveled += step.length()
	queue_redraw()
	if _distance_traveled >= RANGE:
		_explode()

func _on_body_entered(body: Node2D) -> void:
	if not body.has_method("take_damage"):
		return
	_explode()

func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	_spawn_explosion_visual()
	if not visual_only:
		_apply_explosion_damage()
	queue_free()

func _apply_explosion_damage() -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = EXPLOSION_RADIUS
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
	p.amount = 48
	p.lifetime = 0.55
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 220.0
	p.initial_velocity_max = 520.0
	p.scale_amount_min = 5.0
	p.scale_amount_max = 12.0
	p.color = Color(1.0, 0.4, 0.05, 1.0)
	p.emitting = true
	get_parent().add_child(p)
	get_tree().create_timer(p.lifetime + 0.2).timeout.connect(p.queue_free)

func _draw() -> void:
	draw_circle(Vector2.ZERO, 16.0, Color(1.0, 0.45, 0.1))
	draw_circle(Vector2.ZERO, 9.0, Color(1.0, 0.85, 0.3))
