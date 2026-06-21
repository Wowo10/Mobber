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
var _last_attacker: Node = null
var _panicking: bool = false
var _arena: Node = null
var _slow_timer := 0.0
var _slow_mult := 1.0

# Client-side position reconciliation
const MOB_CORRECTION_PX_PER_SEC := 400.0
const MOB_SNAP_THRESHOLD        := 120.0
var _visual_dir          := Vector2.RIGHT  # facing dir (server velocity / push)
# Smoothed render facing — slerped toward _visual_dir so turns ease in over a few
# frames instead of snapping (which read as lag). Higher MOB_TURN_RATE = snappier.
const MOB_TURN_RATE      := 12.0
var _facing_dir          := Vector2.RIGHT  # used by _draw
var _is_client_observer  := false
var _screen_notifier: VisibleOnScreenNotifier2D = null

# Observer snapshot interpolation — render the mob slightly behind real-time and
# lerp between two received snapshots instead of extrapolating by velocity. This
# removes the overshoot/snap-back that extrapolation produces when a mob stops.
const MOB_INTERP_DELAY := 0.12    # s — render ~4 sync intervals behind real-time, so
                                  # a single dropped sync packet doesn't starve the buffer
const MOB_EXTRAP_CAP   := 0.1     # s — max time to extrapolate when buffer is starved
# Exp-smoothing rate for the rendered base. Higher = snappier (less added latency);
# this only softens the jump when a starved buffer recovers, it doesn't replace interp.
const MOB_BASE_SMOOTH_RATE := 22.0
var _snap_buffer: Array = []      # [{t, pos, vel}] ordered by arrival
var _predict_offset := Vector2.ZERO  # local client-push prediction, layered over the interpolated base
var _smoothed_base := Vector2.ZERO   # eased interp base; tracks _sample_snapshot_buffer over a few frames
var _smoothed_base_init := false     # false until the first sample seeds _smoothed_base

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
	_arena = get_parent().get_parent()
	# Only the mob's _draw is gated by this — physics/AI keep running off-screen so
	# the server stays authoritative for both arenas. Rect covers the largest mob
	# (boss) plus health bar, with margin so redraws resume just before it pops in.
	_screen_notifier = VisibleOnScreenNotifier2D.new()
	_screen_notifier.rect = Rect2(-110, -110, 220, 220)
	add_child(_screen_notifier)
	var networked: bool = not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked and not multiplayer.is_server():
		set_physics_process(false)
		_is_client_observer = true


func receive_server_state(pos: Vector2, vel: Vector2) -> void:
	velocity = vel
	var now := Time.get_ticks_msec() / 1000.0
	var snap := {"t": now, "pos": pos, "vel": vel}
	# First snapshot, or a teleport-sized jump — drop history and snap so
	# interpolation doesn't slide across the gap.
	if _snap_buffer.is_empty() or pos.distance_to(position) > MOB_SNAP_THRESHOLD:
		_snap_buffer = [snap]
		position = pos
		# Reseed the smoothed base so it doesn't glide across the teleport gap.
		_smoothed_base = pos
		_smoothed_base_init = true
	else:
		_snap_buffer.append(snap)
		while _snap_buffer.size() > 12:
			_snap_buffer.pop_front()

func _process(delta: float) -> void:
	if _is_client_observer:
		var base := _sample_snapshot_buffer()
		# Ease the rendered base toward the interpolated target so a starve→recover
		# gap reads as a quick glide instead of a hard jump. Frame-rate independent;
		# smooth the BASE only, then add _predict_offset so local push stays responsive.
		if _smoothed_base_init:
			_smoothed_base = _smoothed_base.lerp(base, 1.0 - exp(-MOB_BASE_SMOOTH_RATE * delta))
		else:
			_smoothed_base = base
			_smoothed_base_init = true
		# Local client-push prediction is layered on top and decays as the server's
		# snapshots catch up to reflect the same push.
		if _predict_offset != Vector2.ZERO:
			_predict_offset = _predict_offset.move_toward(
				Vector2.ZERO, MOB_CORRECTION_PX_PER_SEC * delta)
		position = _smoothed_base + _predict_offset
		# Face the authoritative server velocity — the same source the server draws
		# from. Reconstructing facing from interpolated position deltas was fragile:
		# reconciliation micro-steps could dominate and flip the droplet ~180 degrees.
		if velocity.length_squared() > 1.0:
			_visual_dir = velocity.normalized()
	# Ease the rendered facing toward the target direction. Runs every frame (even
	# off-screen) so facing stays continuous when the mob pops back in.
	var target_dir: Vector2
	if _is_client_observer:
		target_dir = _visual_dir
	else:
		target_dir = velocity.normalized() if velocity.length_squared() > 1.0 else _wander_dir
		if target_dir.is_zero_approx():
			target_dir = _facing_dir
	_facing_dir = _facing_dir.slerp(target_dir, clamp(MOB_TURN_RATE * delta, 0.0, 1.0)).normalized()
	# Position interpolation above keeps running so the notifier tracks the mob,
	# but skip the (relatively expensive) _draw rebuild while it's off-screen.
	if _screen_notifier.is_on_screen():
		queue_redraw()

# Position derived from the snapshot buffer at a render time held behind real-time.
# Interpolating between two known positions never overshoots, so a stopping mob
# settles exactly instead of drifting past and snapping back.
func _sample_snapshot_buffer() -> Vector2:
	var count := _snap_buffer.size()
	if count == 0:
		return position
	var newest: Dictionary = _snap_buffer[count - 1]
	if count == 1:
		return newest["pos"]
	var render_t := Time.get_ticks_msec() / 1000.0 - MOB_INTERP_DELAY
	# Render point past the newest snapshot — buffer starved (mobs stop syncing
	# once at rest); extrapolate by last velocity for a capped window only.
	if render_t >= newest["t"]:
		var ahead: float = min(render_t - newest["t"], MOB_EXTRAP_CAP)
		return newest["pos"] + newest["vel"] * ahead
	# Find the pair of snapshots bracketing the render time and lerp between them.
	for i in range(count - 1, 0, -1):
		var s1: Dictionary = _snap_buffer[i]
		var s0: Dictionary = _snap_buffer[i - 1]
		if s0["t"] <= render_t and render_t <= s1["t"]:
			var span: float = s1["t"] - s0["t"]
			var f: float = 0.0 if span <= 0.0 else (render_t - s0["t"]) / span
			return (s0["pos"] as Vector2).lerp(s1["pos"], f)
	# Render point older than the whole buffer (just snapped) — hold at oldest.
	return _snap_buffer[0]["pos"]

func _physics_process(delta: float) -> void:
	if _slow_timer > 0.0:
		_slow_timer = max(0.0, _slow_timer - delta)
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
	var base_spd: float = Constants.MOB_BOSS_SPEED if mob_type == MobType.BOSS else Constants.MOB_SPEED
	var spd_mult: float = _arena.mob_speed_multiplier if _arena != null else 1.0
	var slow: float = _slow_mult if _slow_timer > 0.0 else 1.0
	velocity = _wander_dir * base_spd * spd_mult * slow

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
	if dist < Constants.MOB_FLEE_PANIC_RADIUS:
		_panicking = true
	elif dist > Constants.MOB_FLEE_PANIC_RADIUS + 30.0:
		_panicking = false
	var away := (global_position - target.global_position).normalized()
	if away == Vector2.ZERO:
		away = Vector2(randf() - 0.5, randf() - 0.5).normalized()
	var steer := (away + _wall_avoidance_force()).normalized()
	var flee_speed: float
	if mob_type == MobType.FLEEING:
		flee_speed = Constants.MOB_FLEE_PANIC_SPEED if _panicking else Constants.MOB_FLEE_SPEED
	else:
		flee_speed = Constants.MOB_FLEE_BASIC_SPEED
	var spd_mult: float = _arena.mob_speed_multiplier if _arena != null else 1.0
	var slow: float = _slow_mult if _slow_timer > 0.0 else 1.0
	velocity = steer * flee_speed * spd_mult * slow

func _wall_avoidance_force() -> Vector2:
	var pos := position
	var m := Constants.MOB_WALL_AVOID_MARGIN
	var force := Vector2.ZERO
	var lx := pos.x / m
	var rx := (Constants.WORLD_SIZE_X - pos.x) / m
	var ty := pos.y / m
	var by := (Constants.WORLD_SIZE_Y - pos.y) / m
	if lx < 1.0: force.x += (1.0 - lx)
	if rx < 1.0: force.x -= (1.0 - rx)
	if ty < 1.0: force.y += (1.0 - ty)
	if by < 1.0: force.y -= (1.0 - by)
	return force * Constants.MOB_WALL_AVOID_STRENGTH

# All mobs in an arena run their AI in the same physics frame and each needs the
# player list. Cache it once per physics frame (shared across every mob instance)
# instead of hitting get_nodes_in_group ~100 times per frame.
static var _players_frame: int = -1
static var _players_cache: Array = []

static func _players_in_tree(tree: SceneTree) -> Array:
	var f := Engine.get_physics_frames()
	if f != _players_frame:
		_players_frame = f
		_players_cache = tree.get_nodes_in_group("players")
	return _players_cache

func _get_nearest_player() -> Node2D:
	var players := _players_in_tree(get_tree())
	var nearest_dist := INF
	var nearest: Node2D = null
	for p in players:
		var d := global_position.distance_to(p.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = p
	return nearest

func _get_nearest_player_within(max_dist: float) -> Node2D:
	var players := _players_in_tree(get_tree())
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

func apply_slow(mult: float, duration: float) -> void:
	_slow_mult = mult
	_slow_timer = max(_slow_timer, duration)

func apply_push(impulse: Vector2) -> void:
	_external_velocity = (_external_velocity + impulse).limit_length(Constants.MOB_MAX_EXTERNAL_SPEED)

# Client-side visual prediction — nudge an observer mob immediately when the
# local player walks into it. Server stays authoritative; receive_server_state
# reconciles any over/under-prediction smoothly.
func apply_client_push(displacement: Vector2) -> void:
	if not _is_client_observer:
		return
	var step := displacement.limit_length(MOB_CORRECTION_PX_PER_SEC * 0.033)
	_predict_offset += step
	if step.length_squared() > 0.25:
		_visual_dir = step.normalized()

func apply_burst(impulse: Vector2) -> void:
	_external_velocity = impulse

func take_damage(amount: float, knockback: Vector2 = Vector2.ZERO, attacker: Node = null) -> void:
	var networked: bool = not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked and not multiplayer.is_server():
		return
	if attacker:
		_last_attacker = attacker
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
			var arena: Node = get_parent().get_parent()
			game.call_deferred("notify_mob_killed", arena, _last_attacker)
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
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(1, 1, 1, 0.5), 1.0, true)

func _draw() -> void:
	_draw_droplet(radius, color, _facing_dir)
	if _panicking:
		var t := Time.get_ticks_msec() * 0.001 * Constants.MOB_FLEE_PANIC_PULSE_FREQ
		var pulse := sin(t) * 0.5 + 0.5
		var ring_r := radius + 4.0 + pulse * 5.0
		draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 24, Color(1.0, 0.9, 0.2, 0.6 + pulse * 0.4), 2.0)
	if health < max_health:
		var bar_w := radius * 2.0
		var bar_h := 5.0
		var bar_y := -(radius + 12.0)
		var hp_ratio := health / max_health
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h), Color(0.15, 0.15, 0.15, 0.85))
		draw_rect(Rect2(-bar_w * 0.5, bar_y, bar_w * hp_ratio, bar_h), Color(0.2, 0.8, 0.2))
