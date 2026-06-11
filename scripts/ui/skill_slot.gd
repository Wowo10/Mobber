extends Control

signal unlock_requested

const SIZE := 56.0
const PLUS_RADIUS := 11.0
const PLUS_CENTER := Vector2(SIZE - PLUS_RADIUS - 3.0, PLUS_RADIUS + 3.0)

@export var key_text: String = ""
@export var icon_color: Color = Color(0.5, 0.5, 0.5)
@export var available: bool = true
@export var icon: Texture2D = null

var _cd_remaining: float = 0.0
var _cd_max: float = 1.0
var _passive_counter: int = -1  # -1 = not a passive
var locked: bool = false
var unlock_available: bool = false
var disabled: bool = false

func set_cooldown(remaining: float, max_cd: float) -> void:
	_cd_remaining = remaining
	_cd_max = max_cd
	queue_redraw()

func set_passive_counter(count: int) -> void:
	_passive_counter = count
	queue_redraw()

func set_locked(value: bool) -> void:
	locked = value
	queue_redraw()

func set_unlock_available(value: bool) -> void:
	unlock_available = value
	mouse_filter = MOUSE_FILTER_STOP if value else MOUSE_FILTER_IGNORE
	queue_redraw()

func _get_minimum_size() -> Vector2:
	return Vector2(SIZE, SIZE)

func _gui_input(event: InputEvent) -> void:
	if not (locked and unlock_available):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if (event.position - PLUS_CENTER).length() <= PLUS_RADIUS:
			accept_event()
			unlock_requested.emit()

func _draw() -> void:
	var s := SIZE
	var col := icon_color if (available and not locked) else Color(0.22, 0.22, 0.25)
	var font := ThemeDB.fallback_font

	draw_rect(Rect2(0, 0, s, s), Color(0.08, 0.08, 0.12, 0.92))
	draw_rect(Rect2(0, 0, s, s), Color(0.45, 0.45, 0.55, 0.9), false, 2.0)

	var m := 9.0
	if icon:
		draw_texture_rect(icon, Rect2(m, m, s - m * 2, s - m * 2), false, col)
	else:
		draw_rect(Rect2(m, m, s - m * 2, s - m * 2), col)

	if locked:
		draw_rect(Rect2(0, 0, s, s), Color(0.0, 0.0, 0.0, 0.55))
		if unlock_available:
			draw_circle(PLUS_CENTER, PLUS_RADIUS, Color(0.1, 0.65, 0.2, 0.95))
			draw_arc(PLUS_CENTER, PLUS_RADIUS, 0, TAU, 24, Color(0.4, 1.0, 0.5, 0.9), 1.5)
			var arm := PLUS_RADIUS * 0.55
			draw_line(PLUS_CENTER + Vector2(-arm, 0), PLUS_CENTER + Vector2(arm, 0), Color.WHITE, 2.0)
			draw_line(PLUS_CENTER + Vector2(0, -arm), PLUS_CENTER + Vector2(0, arm), Color.WHITE, 2.0)
		else:
			draw_string(font, Vector2(s * 0.5 - 10, s * 0.5 + 6), "LCK",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.7, 0.1))
	else:
		if not available:
			draw_string(font, Vector2(s * 0.5 - 5, s * 0.5 + 6), "?",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.4, 0.4, 0.4))

		if _passive_counter >= 0:
			draw_rect(Rect2(0, 0, s, s), Color(0.55, 0.2, 0.05, 0.35))
			draw_string(font, Vector2(s - 16, 14), "P",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.6, 0.2, 0.9))
			var combo_text := "%d/4" % (_passive_counter % 4)
			var tw := font.get_string_size(combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_string(font, Vector2((s - tw) * 0.5, s * 0.5 + 8), combo_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.75, 0.3))
		elif available and _cd_max > 0.0 and _cd_remaining > 0.0:
			var frac := clampf(_cd_remaining / _cd_max, 0.0, 1.0)
			draw_rect(Rect2(m, m, s - m * 2, (s - m * 2) * frac), Color(0.0, 0.0, 0.0, 0.75))
			draw_string(font, Vector2(s * 0.5 - 8, s * 0.5 + 6), "%.1f" % _cd_remaining,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	if disabled:
		draw_rect(Rect2(0, 0, s, s), Color(0.7, 0.1, 0.1, 0.45))
		var c := Vector2(s * 0.5, s * 0.5)
		var r := s * 0.28
		draw_arc(c, r, 0, TAU, 32, Color(0.95, 0.2, 0.2, 0.95), 2.5)
		var off := r * 0.707
		draw_line(c + Vector2(-off, -off), c + Vector2(off, off), Color(0.95, 0.2, 0.2, 0.95), 2.5)

	draw_string(font, Vector2(4, s - 5), key_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.82, 0.82, 0.82))
