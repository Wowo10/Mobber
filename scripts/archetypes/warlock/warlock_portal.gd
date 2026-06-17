extends Node2D

var _elapsed := 0.0

func _ready() -> void:
	$SfxAmbient.play()

func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()

func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_elapsed * 3.0)
	draw_arc(Vector2.ZERO, 25.0, 0.0, TAU, 32, Color(0.15, 0.3, 1.0, 0.7 + 0.3 * pulse), 3.5)
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 24, Color(0.4, 0.6, 1.0, 0.55 * pulse), 2.0)
	draw_circle(Vector2.ZERO, 7.0, Color(0.1, 0.15, 0.8, 0.3 * pulse))
