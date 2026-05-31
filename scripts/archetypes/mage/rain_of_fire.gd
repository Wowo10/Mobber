extends Node2D

const DURATION = 4.0
const INTERVAL = 0.4
const STRIKE_RADIUS = 60.0
const SCATTER_RADIUS = 200.0
const DAMAGE = 25.0
const WARN_TIME = 0.3
const IMPACT_FADE = 0.25

var player_ref: Node = null
var visual_only := false

var _elapsed := 0.0
var _next_strike := 0.0
var _strikes_done := 0
var _max_strikes: int = int(DURATION / INTERVAL)
var _warnings: Array = []
var _impacts: Array = []

func _process(delta: float) -> void:
	_elapsed += delta

	for w in _warnings.duplicate():
		w["age"] += delta
		if w["age"] >= WARN_TIME:
			_warnings.erase(w)
			_impacts.append({"pos": w["pos"], "age": 0.0})
			_do_strike(w["pos"])

	for imp in _impacts.duplicate():
		imp["age"] += delta
		if imp["age"] >= IMPACT_FADE:
			_impacts.erase(imp)

	_next_strike -= delta
	if _next_strike <= 0.0 and _strikes_done < _max_strikes:
		_next_strike = INTERVAL
		_strikes_done += 1
		var angle := randf() * TAU
		var dist := sqrt(randf()) * SCATTER_RADIUS
		var strike_pos := global_position + Vector2(cos(angle), sin(angle)) * dist
		_warnings.append({"pos": strike_pos, "age": 0.0})

	if _elapsed >= DURATION + WARN_TIME and _warnings.is_empty() and _impacts.is_empty():
		queue_free()
		return

	queue_redraw()

func _do_strike(pos: Vector2) -> void:
	if visual_only:
		return
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = STRIKE_RADIUS
	query.shape = circle
	query.transform = Transform2D(0.0, pos)
	query.collision_mask = 1
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var body = hit["collider"]
		if body.has_method("take_damage"):
			var dir = (body.global_position - pos).normalized()
			body.take_damage(DAMAGE, dir * 2000.0, player_ref)

func _draw() -> void:
	for w in _warnings:
		var t: float = w["age"] / WARN_TIME
		var lp: Vector2 = w["pos"] - global_position
		draw_circle(lp, STRIKE_RADIUS, Color(1.0, 0.3, 0.0, 0.1 + 0.25 * t))
		draw_arc(lp, STRIKE_RADIUS, 0.0, TAU, 32, Color(1.0, 0.5, 0.0, 0.6 + 0.4 * t), 2.0)
	for imp in _impacts:
		var t: float = 1.0 - imp["age"] / IMPACT_FADE
		var lp: Vector2 = imp["pos"] - global_position
		draw_circle(lp, STRIKE_RADIUS, Color(1.0, 0.15, 0.0, 0.45 * t))
		draw_circle(lp, STRIKE_RADIUS * 0.4, Color(1.0, 0.9, 0.3, 0.8 * t))
