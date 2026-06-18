extends Control

const REDRAW_INTERVAL := 1.0 / 30.0  # arrow doesn't need 60Hz precision
var _redraw_accum := 0.0

func _process(delta: float) -> void:
	_redraw_accum += delta
	if _redraw_accum >= REDRAW_INTERVAL:
		_redraw_accum = 0.0
		queue_redraw()

func _draw() -> void:
	var camera := _get_local_camera()
	if camera == null:
		return

	var vp_size := get_viewport_rect().size
	var canvas_xform := get_viewport().get_canvas_transform()
	var screen_rect := Rect2(Vector2.ZERO, vp_size)
	var player_pos := camera.global_position

	# Single pass over mobs: skip the other arena, bail if any local mob is on
	# screen (no arrow needed), otherwise track the nearest off-screen one.
	var nearest: Node2D = null
	var nearest_dist := INF
	for mob in get_tree().get_nodes_in_group("mobs"):
		var gp := (mob as Node2D).global_position
		if gp.x < camera.limit_left or gp.x > camera.limit_right:
			continue  # other arena
		if screen_rect.has_point(canvas_xform * gp):
			return  # at least one mob is visible
		var d := player_pos.distance_squared_to(gp)
		if d < nearest_dist:
			nearest_dist = d
			nearest = mob

	if nearest == null:
		return

	var mob_screen := canvas_xform * nearest.global_position
	var screen_center := vp_size * 0.5
	var dir := (mob_screen - screen_center).normalized()
	if dir.is_zero_approx():
		return

	var edge := _screen_edge_point(screen_center, dir, 52.0, vp_size)
	_draw_arrow(edge, dir)

func _get_local_camera() -> Camera2D:
	for p in get_tree().get_nodes_in_group("players"):
		if (p as Node).is_multiplayer_authority():
			return (p as Node).get_node_or_null("Camera2D") as Camera2D
	return null

func _screen_edge_point(center: Vector2, dir: Vector2, margin: float, vp_size: Vector2) -> Vector2:
	var t := INF
	if dir.x > 0.001:
		t = min(t, (vp_size.x - margin - center.x) / dir.x)
	elif dir.x < -0.001:
		t = min(t, (margin - center.x) / dir.x)
	if dir.y > 0.001:
		t = min(t, (vp_size.y - margin - center.y) / dir.y)
	elif dir.y < -0.001:
		t = min(t, (margin - center.y) / dir.y)
	return center + dir * t

func _draw_arrow(pos: Vector2, dir: Vector2) -> void:
	var size := 22.0
	var perp := dir.rotated(PI * 0.5)
	var tip := pos + dir * size
	var base_l := pos - perp * size * 0.65
	var base_r := pos + perp * size * 0.65
	var pts := PackedVector2Array([tip, base_l, base_r])
	draw_colored_polygon(pts, Color(1.0, 0.9, 0.15, 0.92))
	draw_polyline(PackedVector2Array([tip, base_l, base_r, tip]), Color(0.05, 0.05, 0.05, 0.7), 1.5)
