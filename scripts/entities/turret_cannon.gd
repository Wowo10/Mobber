extends Node2D

const CANNONBALL_SCENE = preload("res://scenes/entities/cannonball.tscn")

var facing := Vector2.RIGHT
var player_ref: Node = null
var visual_only := false
var _fire_timer := 0.0

func _ready() -> void:
	_fire_timer = 0.0

func reset_fire_timer() -> void:
	_fire_timer = 0.0

func _process(delta: float) -> void:
	if not visual_only:
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire_timer = Constants.SKILL_TURRET_FIRE_INTERVAL
			_fire_cone()
	queue_redraw()

func _fire_cone() -> void:
	var spread := deg_to_rad(Constants.SKILL_TURRET_SPREAD)
	for i in range(3):
		var angle_offset := (i - 1) * spread  # -spread, 0, +spread
		var dir := facing.rotated(angle_offset)
		var ball := CANNONBALL_SCENE.instantiate()
		ball.direction = dir
		ball.homing = false
		ball.global_position = global_position + dir * 22.0
		ball.player_ref = player_ref
		get_parent().add_child(ball)
		if player_ref and is_instance_valid(player_ref):
			player_ref.broadcast_cannonball(ball.global_position, dir, false)

func _draw() -> void:
	draw_circle(Vector2.ZERO, 14.0, Color(0.3, 0.25, 0.15))
	var barrel_end := facing * 24.0
	draw_line(Vector2.ZERO, barrel_end, Color(0.2, 0.15, 0.08), 10.0)
	draw_circle(barrel_end, 5.0, Color(0.12, 0.1, 0.06))
