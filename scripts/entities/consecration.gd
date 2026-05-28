extends Area2D

var player_ref: Node = null
var _duration_left: float = Constants.SKILL_CONSECRATION_DURATION
var _tick_timer := 0.0
var _bodies_inside := []

func _ready() -> void:
	monitoring = true
	($CollisionShape2D.shape as CircleShape2D).radius = Constants.SKILL_CONSECRATION_RADIUS
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(delta: float) -> void:
	_duration_left -= delta
	if _duration_left <= 0.0:
		queue_free()
		return
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = Constants.SKILL_CONSECRATION_TICK_RATE
		_apply_damage()
	queue_redraw()

func _apply_damage() -> void:
	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	for body in _bodies_inside.duplicate():
		if not is_instance_valid(body) or not body.has_method("take_damage"):
			_bodies_inside.erase(body)
			continue
		if not networked or multiplayer.is_server():
			body.take_damage(Constants.SKILL_CONSECRATION_DAMAGE)
		elif player_ref and is_instance_valid(player_ref):
			player_ref.rpc_request_hit.rpc_id(1, body.get_path(), Constants.SKILL_CONSECRATION_DAMAGE, Vector2.ZERO)

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage") and not _bodies_inside.has(body):
		_bodies_inside.append(body)

func _on_body_exited(body: Node2D) -> void:
	_bodies_inside.erase(body)

func _draw() -> void:
	var t: float = clamp(_duration_left / Constants.SKILL_CONSECRATION_DURATION, 0.0, 1.0)
	draw_circle(Vector2.ZERO, Constants.SKILL_CONSECRATION_RADIUS, Color(1.0, 0.85, 0.2, 0.18 * t))
	draw_arc(Vector2.ZERO, Constants.SKILL_CONSECRATION_RADIUS, 0.0, TAU, 64, Color(1.0, 0.9, 0.3, 0.9 * t), 3.0)
	# Inner ring
	draw_arc(Vector2.ZERO, Constants.SKILL_CONSECRATION_RADIUS * 0.6, 0.0, TAU, 48, Color(1.0, 0.95, 0.5, 0.5 * t), 1.5)
