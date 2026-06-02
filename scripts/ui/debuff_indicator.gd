extends Control

const SIZE := Vector2(52, 52)

var debuff_name: String = ""
var icon_color: Color = Color(0.8, 0.15, 0.15)
var time_remaining: float = 0.0

func _ready() -> void:
	custom_minimum_size = SIZE

func _process(delta: float) -> void:
	time_remaining = max(0.0, time_remaining - delta)
	if time_remaining == 0.0:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, SIZE)
	draw_rect(r, icon_color.darkened(0.55))
	draw_rect(r, icon_color, false, 2.5)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(SIZE.x * 0.5, 18.0), debuff_name,
		HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 11, Color(1, 1, 1, 0.9))
	var secs := ceili(time_remaining)
	draw_string(font, Vector2(SIZE.x * 0.5, SIZE.y - 8.0), str(secs),
		HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 22, Color(1, 0.9, 0.3))
