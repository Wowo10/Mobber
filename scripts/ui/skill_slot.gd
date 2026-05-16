extends Control

const SIZE := 56.0

@export var key_text: String = ""
@export var icon_color: Color = Color(0.5, 0.5, 0.5)
@export var available: bool = true

var _cd_remaining: float = 0.0
var _cd_max: float = 1.0

func set_cooldown(remaining: float, max_cd: float) -> void:
	_cd_remaining = remaining
	_cd_max = max_cd
	queue_redraw()

func _get_minimum_size() -> Vector2:
	return Vector2(SIZE, SIZE)

func _draw() -> void:
	var s := SIZE
	var col := icon_color if available else Color(0.22, 0.22, 0.25)
	var font := ThemeDB.fallback_font

	draw_rect(Rect2(0, 0, s, s), Color(0.08, 0.08, 0.12, 0.92))
	draw_rect(Rect2(0, 0, s, s), Color(0.45, 0.45, 0.55, 0.9), false, 2.0)

	var m := 9.0
	draw_rect(Rect2(m, m, s - m * 2, s - m * 2), col)

	if not available:
		draw_string(font, Vector2(s * 0.5 - 5, s * 0.5 + 6), "?",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.4, 0.4, 0.4))

	if available and _cd_max > 0.0 and _cd_remaining > 0.0:
		var frac := clampf(_cd_remaining / _cd_max, 0.0, 1.0)
		draw_rect(Rect2(m, m, s - m * 2, (s - m * 2) * frac), Color(0.0, 0.0, 0.0, 0.75))
		draw_string(font, Vector2(s * 0.5 - 8, s * 0.5 + 6), "%.1f" % _cd_remaining,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	draw_string(font, Vector2(4, s - 5), key_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.82, 0.82, 0.82))
