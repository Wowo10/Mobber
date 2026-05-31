extends Area2D

const SPEED = 2200.0
const RANGE = 800.0
const DAMAGE = 12.0
const KNOCKBACK = 2500.0

var direction := Vector2.RIGHT
var player_ref: Node = null
var visual_only := false
var _distance_traveled := 0.0

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)

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
		body.take_damage(DAMAGE, direction * KNOCKBACK, player_ref)
	queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 8.0, Color(0.1, 0.85, 1.0))
	draw_circle(Vector2.ZERO, 4.0, Color(0.9, 1.0, 1.0))
