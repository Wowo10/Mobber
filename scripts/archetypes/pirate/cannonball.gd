extends "res://scripts/archetypes/projectile_base.gd"

const SPEED = 1200.0
const RANGE = 800.0
const DAMAGE = 20.0
const KNOCKBACK = 10000.0
const TURN_SPEED = 12.0

var homing := true
var _target: Node2D = null

func _ready() -> void:
	$SfxFire.play()

func _process(_delta: float) -> void:
	queue_redraw()

func _physics_process(delta: float) -> void:
	if homing:
		_update_target()
		if _target and is_instance_valid(_target):
			var to_target := (_target.global_position - global_position).normalized()
			var turn: float = clamp(angle_difference(direction.angle(), to_target.angle()),
				-TURN_SPEED * delta,
				TURN_SPEED * delta)
			direction = direction.rotated(turn)
	var prev_pos := global_position
	var step := direction * SPEED * delta
	global_position += step
	_distance_traveled += step.length()
	if _distance_traveled >= RANGE:
		queue_free()
		return
	_check_hit(prev_pos)

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

func _on_hit(body: Node2D) -> void:
	_spawn_impact()
	_play_impact()
	if not visual_only:
		body.take_damage(DAMAGE, direction * KNOCKBACK, player_ref)
	queue_free()

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

func _play_impact() -> void:
	var sfx := $SfxImpact
	remove_child(sfx)
	get_parent().add_child(sfx)
	sfx.global_position = global_position
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

func _draw() -> void:
	draw_circle(Vector2.ZERO, 8.0, Color(0.95, 0.7, 0.1))
