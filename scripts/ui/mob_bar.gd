extends Control

const THRESHOLDS := [0.10, 0.40, 0.70]

var current: int = 0
var maximum: int = 100
var label_prefix: String = ""

func set_count(cur: int, max_count: int) -> void:
	current = cur
	maximum = max_count
	queue_redraw()

func _get_minimum_size() -> Vector2:
	return Vector2(240.0, 30.0)

func _draw() -> void:
	var w := size.x
	var h := size.y
	var frac := clampf(float(current) / float(maximum if maximum > 0 else 1), 0.0, 1.0)
	var font := ThemeDB.fallback_font
	var font_size := 14

	draw_rect(Rect2(0, 0, w, h), Color(0.08, 0.08, 0.12, 0.88))
	draw_rect(Rect2(0, 0, w, h), Color(0.35, 0.35, 0.45, 0.9), false, 1.5)

	var fill_color: Color
	if frac < 0.10:
		fill_color = Color(0.22, 0.72, 0.32)
	elif frac < 0.40:
		fill_color = Color(0.78, 0.72, 0.10)
	elif frac < 0.70:
		fill_color = Color(0.88, 0.44, 0.08)
	else:
		fill_color = Color(0.88, 0.12, 0.12)

	if frac > 0.0:
		draw_rect(Rect2(2, 2, (w - 4) * frac, h - 4), fill_color)

	for t: float in THRESHOLDS:
		var x := w * t
		draw_line(Vector2(x, 0), Vector2(x, h), Color(1.0, 1.0, 1.0, 0.65), 2.0)

	var text := "%s%d / %d" % [label_prefix, current, maximum]
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var tx := (w - tw) * 0.5
	var ty := h * 0.5 + font_size * 0.38
	draw_string(font, Vector2(tx + 1, ty + 1), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.0, 0.0, 0.0, 0.9))
	draw_string(font, Vector2(tx, ty), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
