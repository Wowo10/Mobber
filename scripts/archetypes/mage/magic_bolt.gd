extends "res://scripts/archetypes/projectile_base.gd"

const SPEED = 1800.0
const RANGE = 700.0
const DAMAGE = 15.0
const KNOCKBACK = 3000.0

func _ready() -> void:
	$SfxFire.play()
	_add_trail(Color(0.8, 0.3, 1.0, 0.75), 0.2, 0.6, 10, 0.18)

func _process(_delta: float) -> void:
	queue_redraw()

func _physics_process(delta: float) -> void:
	var prev_pos := global_position
	var step := direction * SPEED * delta
	global_position += step
	_distance_traveled += step.length()
	if _distance_traveled >= RANGE:
		queue_free()
		return
	_check_hit(prev_pos)

func _on_hit(body: Node2D) -> void:
	if not visual_only:
		body.take_damage(DAMAGE, direction * KNOCKBACK, player_ref)
	queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 10.0, Color(0.8, 0.3, 1.0))
	draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.85, 1.0))
