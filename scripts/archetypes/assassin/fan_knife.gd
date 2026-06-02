extends Area2D

const SPEED = 2000.0
const RANGE = 400.0
const DAMAGE = 12.0
const KNOCKBACK = 2500.0

var direction := Vector2.RIGHT
var player_ref: Node = null
var visual_only := false
var _distance_traveled := 0.0

func _ready() -> void:
	monitoring = true
	rotation = direction.angle()
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	var step := SPEED * delta
	global_position += direction * step
	_distance_traveled += step
	if _distance_traveled >= RANGE:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if not body.has_method("take_damage"):
		return
	if not visual_only:
		body.take_damage(DAMAGE, direction * KNOCKBACK, player_ref)
	queue_free()

func _draw() -> void:
	draw_rect(Rect2(-9.0, -2.0, 18.0, 4.0), Color(0.85, 0.9, 1.0))
	draw_rect(Rect2(5.0, -2.0, 5.0, 4.0), Color(0.55, 0.6, 0.75))
