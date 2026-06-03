extends Area2D

const SPEED = 2200.0
const RANGE = 800.0
const DAMAGE = 12.0
const KNOCKBACK = 2500.0

var direction := Vector2.RIGHT
var player_ref: Node = null
var visual_only := false
var mega_mode := false
var _distance_traveled := 0.0

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	$SfxFire.play()

func _process(delta: float) -> void:
	var step := direction * SPEED * delta
	global_position += step
	_distance_traveled += step.length()
	queue_redraw()
	if _distance_traveled >= RANGE:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if not body.has_method("take_damage"):
		return
	if not visual_only:
		var dmg := DAMAGE * (2.5 if mega_mode else 1.0)
		body.take_damage(dmg, direction * KNOCKBACK, player_ref)
	queue_free()

func _draw() -> void:
	if mega_mode:
		draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 32, Color(0.1, 0.85, 1.0), 4.0)
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 32, Color(0.7, 1.0, 1.0, 0.5), 2.0)
	else:
		draw_circle(Vector2.ZERO, 8.0, Color(0.1, 0.85, 1.0))
		draw_circle(Vector2.ZERO, 4.0, Color(0.9, 1.0, 1.0))
