extends Node2D

const RAY_LENGTH = 550.0
const RAY_WIDTH = 14.0
const DURATION = 2.5
const TICK_RATE = 0.12
const DAMAGE_PER_TICK = 6.0

var player_ref: Node = null
var visual_only := false
var thick := false
var skill_level: int = 0

var _elapsed := 0.0
var _tick_timer := 0.0
var facing := Vector2.RIGHT

func _ready() -> void:
	$SfxAmbient.play()

func _process(delta: float) -> void:
	if not player_ref or not is_instance_valid(player_ref):
		queue_free()
		return

	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	$SfxAmbient.volume_db = linear_to_db(clamp(1.0 - _elapsed / DURATION, 0.0, 1.0))

	global_position = player_ref.global_position
	facing = player_ref.last_facing

	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = TICK_RATE
		_apply_damage()

	queue_redraw()

func _apply_damage() -> void:
	if visual_only:
		return
	var level_mult := 1.0 + 0.3 * skill_level
	var w := RAY_WIDTH * level_mult * (3.0 if thick else 1.0)
	var center := facing * (RAY_LENGTH * 0.5)
	var query := PhysicsShapeQueryParameters2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(RAY_LENGTH, w)
	query.shape = rect
	query.transform = Transform2D(facing.angle(), global_position + center)
	query.collision_mask = 1
	var dmg := DAMAGE_PER_TICK * level_mult * (2.0 if thick else 1.0)
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var body = hit["collider"]
		if body.has_method("take_damage"):
			body.take_damage(dmg, Vector2.ZERO, player_ref)

func _draw() -> void:
	var t := 1.0 - (_elapsed / DURATION)
	var end := facing * RAY_LENGTH
	var lm := 1.0 + 0.3 * skill_level
	if thick:
		draw_line(Vector2.ZERO, end, Color(0.1, 0.9, 1.0, 0.75 * t), 22.0 * lm)
		draw_line(Vector2.ZERO, end, Color(0.6, 1.0, 1.0, 0.9 * t), 10.0 * lm)
		draw_line(Vector2.ZERO, end, Color(1.0, 1.0, 1.0, 0.95 * t), 3.0)
		draw_circle(Vector2.ZERO, 16.0 * lm, Color(0.2, 0.95, 1.0, 0.7 * t))
	else:
		draw_line(Vector2.ZERO, end, Color(0.1, 0.9, 1.0, 0.85 * t), 6.0 * lm)
		draw_line(Vector2.ZERO, end, Color(0.8, 1.0, 1.0, 0.9 * t), 2.0 * lm)
		draw_circle(Vector2.ZERO, 8.0 * lm, Color(0.2, 0.95, 1.0, 0.6 * t))
