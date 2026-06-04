extends "res://scripts/archetypes/projectile_base.gd"

const SPEED = 2000.0
const RANGE = 400.0
const DAMAGE = 12.0
const KNOCKBACK = 2500.0

func _ready() -> void:
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	var prev_pos := global_position
	var step := SPEED * delta
	global_position += direction * step
	_distance_traveled += step
	if _distance_traveled >= RANGE:
		queue_free()
		return
	_check_hit(prev_pos)

func _on_hit(body: Node2D) -> void:
	if not visual_only:
		body.take_damage(DAMAGE, direction * KNOCKBACK, player_ref)
	queue_free()

func _draw() -> void:
	draw_rect(Rect2(-9.0, -2.0, 18.0, 4.0), Color(0.85, 0.9, 1.0))
	draw_rect(Rect2(5.0, -2.0, 5.0, 4.0), Color(0.55, 0.6, 0.75))
