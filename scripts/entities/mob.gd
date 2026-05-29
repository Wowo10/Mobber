extends CharacterBody2D

enum State { WANDER, FLEE, CHASE }
enum MobType { BASIC, FLEEING, BOSS }

var mob_type: MobType = MobType.BASIC:
	set(v):
		mob_type = v
		if is_inside_tree():
			_apply_mob_type()

var state: State = State.WANDER
var radius: float = Constants.MOB_RADIUS
var color := Color(0.85, 0.25, 0.25)
var mob_worth: int = 1

var max_health: float = Constants.MOB_MAX_HEALTH
var health: float = Constants.MOB_MAX_HEALTH

var _wander_dir := Vector2.ZERO
var _wander_timer := 0.0
var _external_velocity := Vector2.ZERO

func _apply_mob_type() -> void:
	if mob_type == MobType.FLEEING:
		max_health = Constants.MOB_FLEE_MAX_HEALTH
		health = Constants.MOB_FLEE_MAX_HEALTH
		radius = Constants.MOB_FLEE_RADIUS
		color = Color(0.2, 0.45, 1.0)
		state = State.FLEE
	elif mob_type == MobType.BOSS:
		max_health = Constants.MOB_BOSS_MAX_HEALTH
		health = Constants.MOB_BOSS_MAX_HEALTH
		radius = Constants.MOB_BOSS_RADIUS
		color = Color(0.6, 0.1, 0.75)
		mob_worth = Constants.MOB_BOSS_WORTH
		state = State.WANDER

func _ready() -> void:
	add_to_group("mobs")
	_apply_mob_type()
	_pick_wander_dir()
	var networked: bool = not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked and not multiplayer.is_server():
		set_physics_process(false)


func _process(_delta: float) -> void:
	queue_redraw()

func _physics_process(delta: float) -> void:
	_external_velocity = _external_velocity.move_toward(
		Vector2.ZERO, Constants.MOB_FRICTION * delta)
	match state:
		State.WANDER:
			_process_wander(delta)
		State.FLEE:
			_process_flee(delta)
		State.CHASE:
			pass
	velocity += _external_velocity
	move_and_slide()

func _process_wander(delta: float) -> void:
	if mob_type == MobType.BASIC:
		var target := _get_nearest_player_within(Constants.MOB_FLEE_DETECTION_RADIUS)
		if target != null:
			state = State.FLEE
			return
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_wander_dir()
	var spd: float = Constants.MOB_BOSS_SPEED if mob_type == MobType.BOSS else Constants.MOB_SPEED
	velocity = _wander_dir * spd

func _process_flee(delta: float) -> void:
	var target := _get_nearest_player()
	if target == null:
		if mob_type == MobType.BASIC:
			state = State.WANDER
		_process_wander(delta)
		return
	var dist := global_position.distance_to(target.global_position)
	if mob_type == MobType.BASIC and dist > Constants.MOB_FLEE_STOP_RADIUS:
		state = State.WANDER
		return
	var away := (global_position - target.global_position).normalized()
	if away == Vector2.ZERO:
		away = Vector2(randf() - 0.5, randf() - 0.5).normalized()
	var flee_speed: float = Constants.MOB_FLEE_SPEED if mob_type == MobType.FLEEING else Constants.MOB_FLEE_BASIC_SPEED
	velocity = away * flee_speed

func _get_nearest_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("players")
	var nearest_dist := INF
	var nearest: Node2D = null
	for p in players:
		var d := global_position.distance_to(p.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = p
	return nearest

func _get_nearest_player_within(max_dist: float) -> Node2D:
	var players := get_tree().get_nodes_in_group("players")
	var nearest_dist := max_dist
	var nearest: Node2D = null
	for p in players:
		var d := global_position.distance_to(p.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = p
	return nearest

func _pick_wander_dir() -> void:
	var angle := randf_range(0.0, TAU)
	_wander_dir = Vector2(cos(angle), sin(angle))
	_wander_timer = Constants.MOB_WANDER_INTERVAL + randf_range(-0.5, 0.5)

func apply_push(impulse: Vector2) -> void:
	_external_velocity = (_external_velocity + impulse).limit_length(Constants.MOB_MAX_EXTERNAL_SPEED)

func take_damage(amount: float, knockback: Vector2 = Vector2.ZERO) -> void:
	var networked: bool = not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked and not multiplayer.is_server():
		return
	if knockback != Vector2.ZERO:
		apply_push(knockback)
	health = max(0.0, health - amount)
	if health <= 0.0:
		die()

func die() -> void:
	if not is_inside_tree():
		return
	var networked: bool = not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if not networked or multiplayer.is_server():
		var game := get_tree().root.get_node_or_null("Game")
		if game and game.has_method("notify_mob_killed"):
			var arena := get_parent().get_parent()
			game.call_deferred("notify_mob_killed", arena)
	queue_free()

func _draw_droplet(r: float, col: Color, fwd: Vector2) -> void:
	var n := 20
	var shoulder_a := deg_to_rad(60.0)
	var back_cx := -r * 0.2
	var back_r := r * 0.9
	var rot := fwd.angle()
	var pts := PackedVector2Array()
	for i in range(n + 1):
		var a := shoulder_a + float(i) / float(n) * (TAU - 2.0 * shoulder_a)
		pts.append(Vector2(back_cx + back_r * cos(a), back_r * sin(a)).rotated(rot))
	pts.append(fwd * r * 1.35)
	draw_colored_polygon(pts, col)

func _draw() -> void:
	var fwd := velocity.normalized() if velocity.length_squared() > 1.0 else _wander_dir
	if fwd.is_zero_approx():
		fwd = Vector2.RIGHT
	_draw_droplet(radius, color, fwd)
	if health < max_health:
		var bar_w := radius * 2.0
		var bar_h := 5.0
		var bar_y := -(radius + 12.0)
		var hp_ratio := health / max_health
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.15, 0.15, 0.15, 0.85))
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * hp_ratio, bar_h), Color(0.2, 0.8, 0.2))
