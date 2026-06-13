extends Area2D

const RADIUS = 120.0
const DURATION = 2.0
const TICK_RATE = 0.15
const DAMAGE_PER_TICK = 8.0

var player_ref: Node = null
var visual_only := false
var skill_level: int = 0
var _duration_left := DURATION
var _tick_timer := 0.0
var _bodies_inside := []
var _effective_radius: float
var _effective_damage: float

func _ready() -> void:
	_effective_radius = RADIUS * (1.0 + 0.25 * skill_level)
	_effective_damage = DAMAGE_PER_TICK * (1.0 + 0.2 * skill_level)
	monitoring = true
	collision_mask = 1 | Constants.MOB_COLLISION_LAYER
	($CollisionShape2D.shape as CircleShape2D).radius = _effective_radius
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	$SfxAmbient.play()

func _process(delta: float) -> void:
	if player_ref and is_instance_valid(player_ref):
		global_position = player_ref.global_position

	_duration_left -= delta
	if _duration_left <= 0.0:
		queue_free()
		return
	$SfxAmbient.volume_db = linear_to_db(clamp(_duration_left / DURATION, 0.0, 1.0))

	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = TICK_RATE
		_apply_damage()
	queue_redraw()

func _apply_damage() -> void:
	if visual_only:
		return
	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	for body in _bodies_inside.duplicate():
		if not is_instance_valid(body) or not body.has_method("take_damage"):
			_bodies_inside.erase(body)
			continue
		if not networked or multiplayer.is_server():
			body.take_damage(_effective_damage, Vector2.ZERO, player_ref)

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage") and not _bodies_inside.has(body):
		_bodies_inside.append(body)

func _on_body_exited(body: Node2D) -> void:
	_bodies_inside.erase(body)

func _draw() -> void:
	var t: float = clamp(_duration_left / DURATION, 0.0, 1.0)
	draw_circle(Vector2.ZERO, _effective_radius, Color(0.05, 0.3, 0.7, 0.2 * t))
	draw_arc(Vector2.ZERO, _effective_radius, 0.0, TAU, 48, Color(0.1, 0.5, 0.9, 0.85 * t), 3.0)
	var pulse := 0.5 + 0.5 * sin(_duration_left * 8.0)
	draw_arc(Vector2.ZERO, _effective_radius * 0.5, 0.0, TAU, 32, Color(0.2, 0.7, 1.0, 0.4 * t * pulse), 1.5)
