extends CharacterBody2D

const SPEED = 800.0

# Client-side prediction reconciliation thresholds
const CORRECTION_THRESHOLD := 4.0    # px — ignore errors smaller than this
const SNAP_THRESHOLD       := 250.0  # px — teleport instead of lerping (major desync)
const CORRECTION_SPEED     := 0.25   # fraction of error applied per physics tick

var radius = 20.0
var color = Color(0.33, 0.29, 0.87)
var player_name: String = ""
var move_direction = Vector2.ZERO
var last_facing := Vector2.RIGHT
var archetype: int = 0  # set by game.gd before add_child

var _dashing := false
var _dash_timer := 0.0
var dash_cooldown := 0.0
var attack_cooldown := 0.0
var skill1_cooldown := 0.0
var skill2_cooldown := 0.0
var skill1_max_cooldown := 1.0
var skill2_max_cooldown := 1.0
var speed_level: int = 0
var damage_level: int = 0
var sword_size_level: int = 0
var attack_speed_level: int = 0

# Public — accessed by archetype handlers and spin RPCs
var spinning := false
var spin_timer := 0.0

# Server-side input buffers — written by client RPCs, consumed each physics tick
var _received_direction := Vector2.ZERO
var _pending_attack := false
var _pending_dash := false
var _pending_skill1 := false
var _pending_skill2 := false

var _archetype_handler: ArchetypeBase

# Client-side prediction — pending position correction from server reconciliation
var _server_correction := Vector2.ZERO

func _ready() -> void:
	# MultiplayerSpawner doesn't sync authority — derive it from node name "Player_N"
	var parts := name.split("_")
	if parts.size() == 2 and parts[0] == "Player":
		set_multiplayer_authority(parts[1].to_int())

	_apply_archetype()
	add_to_group("players")
	_setup_particles()

	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		# Non-authority clients are pure observers — no simulation needed
		if not multiplayer.is_server() and not is_multiplayer_authority():
			set_physics_process(false)
		if is_multiplayer_authority():
			_setup_camera()
		else:
			$Camera2D.enabled = false
	else:
		if not is_multiplayer_authority():
			set_physics_process(false)
			$Camera2D.enabled = false
		else:
			_setup_camera()

func _apply_archetype() -> void:
	match archetype:
		Constants.ARCHETYPE_KNIGHT:
			_archetype_handler = ArchetypeKnight.new()
		Constants.ARCHETYPE_PIRATE:
			_archetype_handler = ArchetypePirate.new()
		Constants.ARCHETYPE_MAGE:
			_archetype_handler = ArchetypeMage.new()
		Constants.ARCHETYPE_CYBORG:
			_archetype_handler = ArchetypeCyborg.new()
		_:
			_archetype_handler = ArchetypeBase.new()
	_archetype_handler.setup(self)
	color = _archetype_handler.get_color()
	skill1_max_cooldown = _archetype_handler.get_skill1_max_cooldown()
	skill2_max_cooldown = _archetype_handler.get_skill2_max_cooldown()

func _setup_particles() -> void:
	var p := $DashParticles
	p.amount = 24
	p.lifetime = 0.35
	p.one_shot = false
	p.explosiveness = 0.3
	p.spread = 40.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 200.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 7.0
	p.color = Color(0.55, 0.50, 1.0, 0.75)

func _setup_camera() -> void:
	var my_id := multiplayer.get_unique_id()
	var team: int = PlayerPrefs.peer_teams.get(my_id, 0)
	var arena_x: float = 0.0 if team == 0 else float(Constants.WORLD_SIZE_X + Constants.ARENA_GAP)
	var cam := $Camera2D
	cam.limit_left = int(arena_x)
	cam.limit_right = int(arena_x + Constants.WORLD_SIZE_X)
	cam.limit_top = 0
	cam.limit_bottom = int(Constants.WORLD_SIZE_Y)
	cam.make_current()

# --- Observer: keep non-authority spinning swords rotating ---

func _process(delta: float) -> void:
	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked and not multiplayer.is_server() and not is_multiplayer_authority() and spinning:
		$Sword.rotation += ArchetypeKnight.SPIN_SPEED * delta

# --- Simulation ---

func _physics_process(delta: float) -> void:
	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)

	var direction: Vector2
	var do_attack: bool
	var do_dash: bool
	var do_skill1: bool
	var do_skill2: bool

	if not networked:
		# Path A — Offline: read keyboard, full simulation, no RPCs
		direction = _read_direction()
		do_attack = Input.is_action_just_pressed("attack") and _archetype_handler.can_attack()
		do_dash   = Input.is_action_just_pressed("dash") and dash_cooldown <= 0.0
		do_skill1 = Input.is_action_just_pressed("skill1") and skill1_cooldown <= 0.0
		do_skill2 = Input.is_action_just_pressed("skill2") and skill2_cooldown <= 0.0

	elif multiplayer.is_server():
		# Path B — Server: simulate all players authoritatively
		if is_multiplayer_authority():
			direction = _read_direction()
			do_attack = Input.is_action_just_pressed("attack") and _archetype_handler.can_attack()
			do_dash   = Input.is_action_just_pressed("dash") and dash_cooldown <= 0.0
			do_skill1 = Input.is_action_just_pressed("skill1") and skill1_cooldown <= 0.0
			do_skill2 = Input.is_action_just_pressed("skill2") and skill2_cooldown <= 0.0
		else:
			direction = _received_direction
			do_attack = _pending_attack and _archetype_handler.can_attack()
			do_dash   = _pending_dash and dash_cooldown <= 0.0
			do_skill1 = _pending_skill1 and skill1_cooldown <= 0.0
			do_skill2 = _pending_skill2 and skill2_cooldown <= 0.0
			_pending_attack = false
			_pending_dash   = false
			_pending_skill1 = false
			_pending_skill2 = false

	else:
		# Path C — Client own player: predict locally and send input to server
		direction = _read_direction()
		do_attack = Input.is_action_just_pressed("attack") and _archetype_handler.can_attack()
		do_dash   = Input.is_action_just_pressed("dash") and dash_cooldown <= 0.0
		do_skill1 = Input.is_action_just_pressed("skill1") and skill1_cooldown <= 0.0
		do_skill2 = Input.is_action_just_pressed("skill2") and skill2_cooldown <= 0.0
		_rpc_send_direction.rpc_id(1, direction)
		var action_mask := 0
		if do_attack: action_mask |= 1
		if do_dash:   action_mask |= 2
		if do_skill1: action_mask |= 4
		if do_skill2: action_mask |= 8
		if action_mask != 0:
			_rpc_send_action.rpc_id(1, action_mask)

	# --- Common simulation (all paths) ---

	move_direction = direction
	if move_direction != Vector2.ZERO:
		last_facing = move_direction
		$Sword.set_facing(last_facing.angle())

	# Cooldown ticks
	if attack_cooldown > 0.0:
		attack_cooldown -= delta
	if skill1_cooldown > 0.0:
		skill1_cooldown = max(0.0, skill1_cooldown - delta)
	if skill2_cooldown > 0.0:
		skill2_cooldown = max(0.0, skill2_cooldown - delta)

	# Spin tick
	if spinning:
		spin_timer -= delta
		$Sword.rotation += ArchetypeKnight.SPIN_SPEED * delta
		if spin_timer <= 0.0:
			spinning = false
			$Sword.exit_spin()
			if networked and multiplayer.is_server():
				_rpc_trigger_spin_stop.rpc()

	# Dash / movement
	if _dashing:
		_dash_timer -= delta
		velocity = last_facing * Constants.PLAYER_DASH_SPEED
		if _dash_timer <= 0.0:
			_dashing = false
			$DashParticles.emitting = false
			if networked and multiplayer.is_server():
				_rpc_set_dash_particles.rpc(Vector2.ZERO, false)
	else:
		if dash_cooldown > 0.0:
			dash_cooldown -= delta
		velocity = move_direction * SPEED * (1.0 + Constants.SHOP_SPEED_MULT_PER_LEVEL * speed_level)
		if do_dash:
			_dashing = true
			_dash_timer = Constants.PLAYER_DASH_DURATION
			dash_cooldown = Constants.PLAYER_DASH_COOLDOWN
			$DashParticles.direction = -last_facing
			$DashParticles.emitting = true
			if networked and multiplayer.is_server():
				_rpc_set_dash_particles.rpc(-last_facing, true)

	move_and_slide()

	# Apply server correction nudge (client prediction only)
	if networked and not multiplayer.is_server() and _server_correction != Vector2.ZERO:
		var step := _server_correction * CORRECTION_SPEED
		position += step
		_server_correction -= step
		if _server_correction.length() < 0.5:
			_server_correction = Vector2.ZERO

	# Mob pushing — server and offline only
	if not networked or multiplayer.is_server():
		_push_mobs()

	queue_redraw()

	if not networked or multiplayer.is_server():
		# Paths A & B: authoritative attack + skill spawning + position broadcast
		if do_attack:
			_archetype_handler.use_attack()
			if networked:
				_archetype_handler.broadcast_attack()
		if do_skill1:
			_use_skill1()
		if do_skill2:
			_use_skill2()
		_archetype_handler.physics_process(delta)
		if networked:
			_rpc_sync_pos.rpc(position, last_facing, move_direction)
	else:
		# Path C: local visual prediction — no server-authoritative spawning
		if do_attack:
			_archetype_handler.use_attack_visual()
		if do_skill1:
			if archetype == Constants.ARCHETYPE_KNIGHT:
				spinning = true
				spin_timer = ArchetypeKnight.SPIN_DURATION
				$Sword.enter_spin()
				skill1_cooldown = skill1_max_cooldown
			else:
				skill1_cooldown = skill1_max_cooldown
				_archetype_handler.on_skill1_client_predict()
		if do_skill2:
			skill2_cooldown = skill2_max_cooldown
		_archetype_handler.physics_process(delta)

# --- Input helper ---

func _read_direction() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_action_pressed("move_left"):  d.x -= 1
	if Input.is_action_pressed("move_right"): d.x += 1
	if Input.is_action_pressed("move_up"):    d.y -= 1
	if Input.is_action_pressed("move_down"):  d.y += 1
	return d.normalized()

# --- Input RPCs (client → server) ---

@rpc("any_peer", "unreliable_ordered")
func _rpc_send_direction(direction: Vector2) -> void:
	if not multiplayer.is_server():
		return
	_received_direction = direction

@rpc("any_peer", "reliable")
func _rpc_send_action(action_mask: int) -> void:
	if not multiplayer.is_server():
		return
	if action_mask & 1: _pending_attack = true
	if action_mask & 2: _pending_dash   = true
	if action_mask & 4: _pending_skill1 = true
	if action_mask & 8: _pending_skill2 = true

# --- Skills ---

func _use_skill1() -> void:
	_archetype_handler.use_skill1()

func _use_skill2() -> void:
	_archetype_handler.use_skill2()

# --- Upgrade RPCs ---

func apply_upgrades_to_sword() -> void:
	var dmg_bonus := damage_level * Constants.SHOP_DAMAGE_PER_LEVEL
	var sz_mult := 1.0 + sword_size_level * Constants.SHOP_SWORD_SIZE_PER_LEVEL
	var spd_mult := 1.0 - attack_speed_level * Constants.SHOP_ATTACK_SPEED_PER_LEVEL
	$Sword.apply_upgrades(dmg_bonus, sz_mult, spd_mult)

@rpc("any_peer", "reliable")
func rpc_apply_speed_level(level: int) -> void:
	speed_level = level

@rpc("any_peer", "reliable")
func rpc_apply_damage_level(level: int) -> void:
	damage_level = level
	apply_upgrades_to_sword()

@rpc("any_peer", "reliable")
func rpc_apply_sword_size_level(level: int) -> void:
	sword_size_level = level
	apply_upgrades_to_sword()

@rpc("any_peer", "reliable")
func rpc_apply_attack_speed_level(level: int) -> void:
	attack_speed_level = level
	apply_upgrades_to_sword()

# --- Mob pushing (server and offline only) ---

func _push_mobs() -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius + Constants.MOB_RADIUS
	query.shape = circle
	query.transform = global_transform
	query.collision_mask = 1
	query.exclude = [get_rid()]
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var body: Node2D = hit["collider"]
		if not body.has_method("apply_push"):
			continue
		var dir := body.global_position - global_position
		if dir.is_zero_approx():
			continue
		body.apply_push(dir.normalized() * Constants.MOB_PUSH_FORCE * (6.0 if _dashing else 1.0))

# --- Broadcast helpers (called by archetype handlers) ---

func broadcast_swing(angle: float) -> void:
	rpc_trigger_swing.rpc(angle)

func broadcast_cannonball(pos: Vector2, dir: Vector2, homing: bool) -> void:
	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked and multiplayer.is_server():
		rpc_spawn_cannonball.rpc(pos, dir, homing)

# --- Visual / sync RPCs ---

@rpc("any_peer", "reliable")
func rpc_spawn_cannonball(pos: Vector2, dir: Vector2, homing: bool) -> void:
	(_archetype_handler as ArchetypePirate).spawn_visual_cannonball(pos, dir, homing)

@rpc("any_peer", "reliable")
func rpc_place_turret(pos: Vector2, fac: Vector2) -> void:
	(_archetype_handler as ArchetypePirate).place_visual_turret(pos, fac)

@rpc("any_peer", "reliable")
func rpc_spawn_consecration(pos: Vector2) -> void:
	(_archetype_handler as ArchetypeKnight).spawn_consecration_local(pos, true)

@rpc("any_peer", "reliable")
func rpc_spawn_mage_bolt(pos: Vector2, dir: Vector2) -> void:
	if is_multiplayer_authority():
		return
	(_archetype_handler as ArchetypeMage).spawn_bolt_local(pos, dir, true)

@rpc("any_peer", "reliable")
func rpc_spawn_rain(pos: Vector2) -> void:
	(_archetype_handler as ArchetypeMage).spawn_rain_local(pos, true)

@rpc("any_peer", "reliable")
func rpc_spawn_fireball(pos: Vector2, dir: Vector2) -> void:
	(_archetype_handler as ArchetypeMage).spawn_fireball_local(pos, dir, true)

@rpc("any_peer", "reliable")
func rpc_spawn_cyber_bullet(pos: Vector2, dir: Vector2) -> void:
	if is_multiplayer_authority():
		return
	(_archetype_handler as ArchetypeCyborg).spawn_bullet_local(pos, dir, true)

@rpc("any_peer", "reliable")
func rpc_spawn_cyber_ray(pos: Vector2, facing: Vector2) -> void:
	(_archetype_handler as ArchetypeCyborg).spawn_ray_local(pos, facing, true)

@rpc("any_peer", "reliable")
func rpc_set_cyborg_ranged_mode(active: bool) -> void:
	(_archetype_handler as ArchetypeCyborg).set_ranged_mode(active)

@rpc("any_peer", "unreliable_ordered")
func _rpc_set_dash_particles(dir: Vector2, emitting: bool) -> void:
	$DashParticles.direction = dir
	$DashParticles.emitting = emitting

@rpc("any_peer", "reliable")
func rpc_trigger_swing(facing_angle: float) -> void:
	$Sword.swing(facing_angle)

@rpc("any_peer", "reliable")
func rpc_trigger_spin_start() -> void:
	spinning = true
	spin_timer = ArchetypeKnight.SPIN_DURATION
	$Sword.enter_spin()

@rpc("any_peer", "reliable")
func _rpc_trigger_spin_stop() -> void:
	spinning = false
	$Sword.exit_spin()

# --- Position sync (server → all clients) ---

@rpc("any_peer", "unreliable_ordered")
func _rpc_sync_pos(pos: Vector2, facing: Vector2, move_dir: Vector2) -> void:
	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked and not multiplayer.is_server() and is_multiplayer_authority():
		# Own player — reconcile predicted position with server's authoritative one
		var error := pos - position
		if error.length() > SNAP_THRESHOLD:
			position = pos
			_server_correction = Vector2.ZERO
		elif error.length() > CORRECTION_THRESHOLD:
			_server_correction = error
		# Small error: trust local prediction, do nothing
	else:
		# Observed player — apply server state directly
		position = pos
		last_facing = facing
		move_direction = move_dir
		$Sword.set_facing(facing.angle())
	queue_redraw()

# --- Drawing ---

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
	_draw_droplet(radius, color, last_facing)
	if not player_name.is_empty():
		var font := ThemeDB.fallback_font
		var font_size := 13
		var tw := font.get_string_size(player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(-tw * 0.5, -radius - 4.0), player_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 1.0, 1.0, 0.9))
