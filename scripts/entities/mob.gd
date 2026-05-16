extends CharacterBody2D

enum State { WANDER, FLEE, CHASE }

var state: State = State.WANDER
var radius: float = Constants.MOB_RADIUS
var color := Color(0.85, 0.25, 0.25)

var max_health: float = Constants.MOB_MAX_HEALTH
var health: float = Constants.MOB_MAX_HEALTH

var _wander_dir := Vector2.ZERO
var _wander_timer := 0.0

func _ready() -> void:
	_pick_wander_dir()
	# Only the server runs mob physics/AI
	var networked: bool = multiplayer.multiplayer_peer is ENetMultiplayerPeer
	if networked and not multiplayer.is_server():
		set_physics_process(false)

func _process(_delta: float) -> void:
	queue_redraw()

func _physics_process(delta: float) -> void:
	match state:
		State.WANDER:
			_process_wander(delta)
		State.FLEE:
			pass  # future: _process_flee(delta, target)
		State.CHASE:
			pass  # future: _process_chase(delta, target)
	move_and_slide()

func _process_wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_wander_dir()
	velocity = _wander_dir * Constants.MOB_SPEED

func _pick_wander_dir() -> void:
	var angle := randf_range(0.0, TAU)
	_wander_dir = Vector2(cos(angle), sin(angle))
	_wander_timer = Constants.MOB_WANDER_INTERVAL + randf_range(-0.5, 0.5)

func take_damage(amount: float) -> void:
	var networked: bool = multiplayer.multiplayer_peer is ENetMultiplayerPeer
	if networked and not multiplayer.is_server():
		return
	health = max(0.0, health - amount)
	if health <= 0.0:
		die()

func die() -> void:
	var networked: bool = multiplayer.multiplayer_peer is ENetMultiplayerPeer
	if networked and multiplayer.is_server():
		var game := get_tree().root.get_node_or_null("Game")
		if game and game.has_method("notify_mob_killed"):
			game.notify_mob_killed(get_parent().get_parent())
	queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)
	if health < max_health:
		var bar_w := radius * 2.0
		var bar_h := 5.0
		var bar_y := -(radius + 12.0)
		var hp_ratio := health / max_health
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.15, 0.15, 0.15, 0.85))
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * hp_ratio, bar_h), Color(0.2, 0.8, 0.2))
