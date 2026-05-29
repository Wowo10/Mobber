extends Area2D

var direction := Vector2.RIGHT
var player_ref: Node = null
var homing := true
var visual_only := false
var _distance_traveled := 0.0
var _target: Node2D = null

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if homing:
		_update_target()
		if _target and is_instance_valid(_target):
			var to_target := (_target.global_position - global_position).normalized()
			var turn: float = clamp(angle_difference(direction.angle(), to_target.angle()),
				-Constants.SKILL_CANNON_TURN_SPEED * delta,
				Constants.SKILL_CANNON_TURN_SPEED * delta)
			direction = direction.rotated(turn)
	var step := direction * Constants.SKILL_CANNON_SPEED * delta
	global_position += step
	_distance_traveled += step.length()
	queue_redraw()
	if _distance_traveled >= Constants.SKILL_CANNON_RANGE:
		queue_free()

func _update_target() -> void:
	if _target and is_instance_valid(_target) and not _target.is_queued_for_deletion():
		return
	_target = null
	var closest_dist := INF
	for mob in get_tree().get_nodes_in_group("mobs"):
		var d := global_position.distance_to(mob.global_position)
		if d < closest_dist:
			closest_dist = d
			_target = mob

func _spawn_impact() -> void:
	var p := CPUParticles2D.new()
	p.global_position = global_position
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 20
	p.lifetime = 0.4
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 300.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 8.0
	p.color = Color(1.0, 0.55, 0.1, 1.0)
	p.emitting = true
	get_parent().add_child(p)
	get_tree().create_timer(p.lifetime + 0.2).timeout.connect(p.queue_free)

func _on_body_entered(body: Node2D) -> void:
	if not body.has_method("take_damage"):
		return
	_spawn_impact()
	if not visual_only:
		body.take_damage(Constants.SKILL_CANNON_DAMAGE, direction * Constants.SKILL_CANNON_KNOCKBACK, player_ref)
	queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 8.0, Color(0.95, 0.7, 0.1))
