extends StaticBody2D

const RADIUS := 30.0
const COLOR := Color(0.45, 0.45, 0.52)

class FloatingNumber extends Node2D:
	var _text: String = ""
	var _timer := 0.0
	const DURATION := 0.9
	const RISE := 55.0

	func init(amount: float) -> void:
		_text = "%d" % int(amount)

	func _process(delta: float) -> void:
		_timer += delta
		position.y -= RISE * delta
		queue_redraw()
		if _timer >= DURATION:
			queue_free()

	func _draw() -> void:
		var alpha := 1.0 - (_timer / DURATION)
		var font := ThemeDB.fallback_font
		var w := 80.0
		draw_string(font, Vector2(-w * 0.5, 0.0), _text,
			HORIZONTAL_ALIGNMENT_CENTER, w, 22,
			Color(1.0, 0.85, 0.2, alpha))

func _ready() -> void:
	add_to_group("mobs")
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	cs.shape = shape
	add_child(cs)

func take_damage(amount: float, _knockback: Vector2 = Vector2.ZERO, _attacker: Node = null) -> void:
	var lbl := FloatingNumber.new()
	lbl.init(amount)
	lbl.position = Vector2(randf_range(-8.0, 8.0), -(RADIUS + 10.0))
	add_child(lbl)

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, COLOR)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 32, Color(0.25, 0.25, 0.3), 3.0)
	var font := ThemeDB.fallback_font
	var w := 80.0
	draw_string(font, Vector2(-w * 0.5, RADIUS + 20.0),
		"DUMMY", HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color(0.75, 0.75, 0.8, 0.8))
