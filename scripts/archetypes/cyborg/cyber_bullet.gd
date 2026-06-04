extends "res://scripts/archetypes/projectile_base.gd"

const SPEED = 2200.0
const MEGA_SPEED = 1350.0
const RANGE = 800.0
const DAMAGE = 12.0
const KNOCKBACK = 2500.0

var mega_mode := false

func _ready() -> void:
	$SfxFire.play()

func _process(_delta: float) -> void:
	queue_redraw()

func _physics_process(delta: float) -> void:
	var prev_pos := global_position
	var spd := MEGA_SPEED if mega_mode else SPEED
	var step := direction * spd * delta
	global_position += step
	_distance_traveled += step.length()
	if _distance_traveled >= RANGE:
		queue_free()
		return
	_check_hit(prev_pos)

func _on_hit(body: Node2D) -> void:
	if not visual_only:
		body.take_damage(DAMAGE * (2.5 if mega_mode else 1.0), direction * KNOCKBACK, player_ref)
	queue_free()

func _draw() -> void:
	if mega_mode:
		draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 32, Color(0.1, 0.85, 1.0), 4.0)
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 32, Color(0.7, 1.0, 1.0, 0.5), 2.0)
	else:
		draw_circle(Vector2.ZERO, 8.0, Color(0.1, 0.85, 1.0))
		draw_circle(Vector2.ZERO, 4.0, Color(0.9, 1.0, 1.0))
