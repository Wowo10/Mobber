extends CharacterBody2D

const SPEED = 800.0
const PAD_DEADZONE := 0.15

# Client-side prediction reconciliation thresholds
const CORRECTION_THRESHOLD   := 4.0    # px — ignore errors smaller than this
const SNAP_THRESHOLD         := 250.0  # px — teleport instead of lerping (major desync)
const CORRECTION_PX_PER_SEC  := 400.0  # drift correction speed — fast enough to feel responsive, still smooth

# Observed (remote) player dead-reckoning — same shape as mob.gd's reconciliation
const OBSERVED_SNAP_THRESHOLD        := 250.0

# Observed (remote) player snapshot interpolation — render other players slightly
# in the past and lerp between two known snapshots instead of extrapolating by
# velocity. This removes the overshoot/snap-back that pure extrapolation produces
# when a remote player stops. Cost is a small constant visual delay on others;
# hits stay server-authoritative so fairness is unaffected.
const OBSERVED_INTERP_DELAY := 0.066   # s — render ~2 sync intervals behind real-time
const OBSERVED_EXTRAP_CAP   := 0.1     # s — max time to extrapolate when buffer is starved

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
var skill3_cooldown := 0.0
var skill1_max_cooldown := 1.0
var skill2_max_cooldown := 1.0
var skill3_max_cooldown := 1.0
var speed_level: int = 0
var damage_level: int = 0
var sword_size_level: int = 0
var attack_speed_level: int = 0
var skill1_level: int = 0
var skill2_level: int = 0
var skill3_level: int = 0
var skills_unlocked: Array = [false, false, false]

var debuff_no_dash_timer := 0.0
var debuff_silence_timer := 0.0
var debuff_invert_timer  := 0.0

var _shake_duration := 0.0
var _shake_intensity := 0.0
var _shake_max_duration := 1.0

# Public — accessed by archetype handlers and spin RPCs
var spinning := false
var spin_timer := 0.0
var _spin_loop_timer := 0.0

var _archetype_handler: ArchetypeBase

# RPC message-passing layer — input RPCs + buffers, visual/broadcast RPCs, and the
# upgrade/debuff/skill-unlock appliers. Archetype handlers reach it via _player.net_sync.
@onready var net_sync: Node = $NetSync

# Client-side prediction — pending position correction from server reconciliation
var _server_correction      := Vector2.ZERO
var _cam_correction_offset  := Vector2.ZERO  # counteracts correction on camera so it doesn't jump
var _mouse_attack_pressed := false
var _mouse_dash_pressed := false

# Observed (remote) player snapshot buffer — [{t, pos, vel, facing, move_dir}] ordered by arrival.
# Only populated for non-authority players we merely display; used for interpolation.
var _snap_buffer: Array = []

# Position sync rate-limit (server) and input change-detection (client)
const POS_SYNC_INTERVAL   := 0.033   # every physics tick (60 Hz)
var _pos_sync_timer        := 0.0
var _last_sent_direction   := Vector2.ZERO
var _last_sent_facing      := Vector2.RIGHT

func _ready() -> void:
	# MultiplayerSpawner doesn't sync authority — derive it from node name "Player_N".
	# The NetSync child does NOT inherit authority, so set it there too or its RPC
	# authority guards (input RPCs, sender-id checks) break.
	var parts := name.split("_")
	if parts.size() == 2 and parts[0] == "Player":
		var peer_id := parts[1].to_int()
		set_multiplayer_authority(peer_id)
		$NetSync.set_multiplayer_authority(peer_id)

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
		Constants.ARCHETYPE_PALADIN:
			_archetype_handler = ArchetypePaladin.new()
		Constants.ARCHETYPE_PIRATE:
			_archetype_handler = ArchetypePirate.new()
		Constants.ARCHETYPE_MAGE:
			_archetype_handler = ArchetypeMage.new()
		Constants.ARCHETYPE_CYBORG:
			_archetype_handler = ArchetypeCyborg.new()
		Constants.ARCHETYPE_ASSASSIN:
			_archetype_handler = ArchetypeAssassin.new()
		Constants.ARCHETYPE_BERSERKER:
			_archetype_handler = ArchetypeBerserker.new()
		Constants.ARCHETYPE_WARLOCK:
			_archetype_handler = ArchetypeWarlock.new()
		_:
			_archetype_handler = ArchetypeBase.new()
	_archetype_handler.setup(self)
	color = _archetype_handler.get_color()
	skill1_max_cooldown = _archetype_handler.get_skill1_max_cooldown()
	skill2_max_cooldown = _archetype_handler.get_skill2_max_cooldown()
	skill3_max_cooldown = _archetype_handler.get_skill3_max_cooldown()

func _setup_particles() -> void:
	var p := $DashParticles
	p.amount = 14
	p.lifetime = 0.3
	p.one_shot = false
	p.explosiveness = 0.3
	p.spread = 40.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 200.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	p.color = Color(0.55, 0.50, 1.0, 0.75)
	ParticleUtils.polish(p)

func _setup_camera() -> void:
	var my_id := multiplayer.get_unique_id()
	var team: int = PlayerPrefs.peer_teams.get(my_id, 0)
	var arena_x: float = 0.0 if team == 0 else float(Constants.WORLD_SIZE_X + Constants.ARENA_GAP)
	var cam := $Camera2D
	cam.limit_left = int(arena_x)
	cam.limit_right = int(arena_x + Constants.WORLD_SIZE_X)
	cam.limit_top = 0
	cam.limit_bottom = int(Constants.WORLD_SIZE_Y)
	# cam.zoom = Vector2(0.4, 0.4)
	cam.make_current()

# --- Observer: keep non-authority spinning swords rotating ---

func shake_camera(duration: float, intensity: float) -> void:
	_shake_duration = duration
	_shake_max_duration = duration
	_shake_intensity = intensity
	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked and multiplayer.is_server() and not is_multiplayer_authority():
		_rpc_shake_camera.rpc_id(
				get_multiplayer_authority(), duration, intensity)

@rpc("authority", "reliable")
func _rpc_shake_camera(duration: float, intensity: float) -> void:
	_shake_duration = duration
	_shake_max_duration = duration
	_shake_intensity = intensity

func _process(delta: float) -> void:
	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked and not multiplayer.is_server() and (not is_multiplayer_authority() or not Constants.CLIENT_PREDICTION):
		if spinning and not is_multiplayer_authority():
			$Sword.rotation += ArchetypePaladin.SPIN_SPEED * delta
		if not is_multiplayer_authority():
			# Genuinely remote player — interpolate between buffered snapshots.
			_sample_snapshot_buffer()
		else:
			# Own player with prediction OFF — interpolate buffered snapshots too, so
			# the camera (parented here) shares the mobs' past-time timeline instead of
			# extrapolating into the future and yanking the whole scene backward each
			# snapshot. Facing stays local (set in _physics_process) for crisp aim.
			_sample_snapshot_buffer(false)
		queue_redraw()
	if _cam_correction_offset != Vector2.ZERO:
		_cam_correction_offset = _cam_correction_offset.move_toward(
				Vector2.ZERO, CORRECTION_PX_PER_SEC * delta)
	if _shake_duration > 0.0:
		_shake_duration -= delta
		var strength := _shake_intensity * (_shake_duration / _shake_max_duration)
		var shake := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		if _shake_duration <= 0.0:
			shake = Vector2.ZERO
		$Camera2D.offset = shake + _cam_correction_offset
	else:
		$Camera2D.offset = _cam_correction_offset
	if spinning and is_multiplayer_authority():
		_spin_loop_timer -= delta
		if _spin_loop_timer <= 0.0:
			_spin_loop_timer = 0.25
			$SfxSpinLoop.pitch_scale = randf_range(0.9, 1.1)
			$SfxSpinLoop.play()

# Position a genuinely-remote player by interpolating buffered snapshots at a
# render time held slightly behind real-time. Interpolating between two known
# positions never overshoots, so stopping is exact (no rubber-band).
# apply_facing: false for our own player (prediction off) — position is interpolated
# from the buffer but facing/move_dir stay locally driven so aim stays crisp.
func _sample_snapshot_buffer(apply_facing: bool = true) -> void:
	var count := _snap_buffer.size()
	if count == 0:
		return
	var newest: Dictionary = _snap_buffer[count - 1]
	if count == 1:
		position = newest["pos"]
		if apply_facing:
			_apply_snapshot_facing(newest)
		return
	var render_t := Time.get_ticks_msec() / 1000.0 - OBSERVED_INTERP_DELAY
	# Render point is past the newest snapshot — buffer starved; extrapolate by the
	# last known velocity, but only for a capped window so a dropped stop-packet
	# can't fling the player away.
	if render_t >= newest["t"]:
		var ahead: float = min(render_t - newest["t"], OBSERVED_EXTRAP_CAP)
		position = newest["pos"] + newest["vel"] * ahead
		if apply_facing:
			_apply_snapshot_facing(newest)
		return
	# Find the pair of snapshots that bracket the render time and lerp between them.
	for i in range(count - 1, 0, -1):
		var s1: Dictionary = _snap_buffer[i]
		var s0: Dictionary = _snap_buffer[i - 1]
		if s0["t"] <= render_t and render_t <= s1["t"]:
			var span: float = s1["t"] - s0["t"]
			var f: float = 0.0 if span <= 0.0 else (render_t - s0["t"]) / span
			position = (s0["pos"] as Vector2).lerp(s1["pos"], f)
			if apply_facing:
				_apply_snapshot_facing(s1)
			return
	# Render point is older than the whole buffer (just snapped) — hold at oldest.
	var oldest: Dictionary = _snap_buffer[0]
	position = oldest["pos"]
	if apply_facing:
		_apply_snapshot_facing(oldest)

func _apply_snapshot_facing(snap: Dictionary) -> void:
	last_facing = snap["facing"]
	move_direction = snap["move_dir"]
	$Sword.set_facing(last_facing.angle())

func _input(event: InputEvent) -> void:
	if PlayerPrefs.control_scheme != PlayerPrefs.SCHEME_MOUSE:
		return
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("attack"):
		_mouse_attack_pressed = true
	elif event.is_action_pressed("dash"):
		_mouse_dash_pressed = true

# --- Simulation ---

func _physics_process(delta: float) -> void:
	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	# Own client player predicts movement only when prediction is enabled.
	var predict_movement := (not networked) or multiplayer.is_server() or Constants.CLIENT_PREDICTION

	var direction: Vector2
	var facing: Vector2
	var do_attack: bool
	var do_dash: bool
	var do_skill1: bool
	var do_skill2: bool
	var do_skill3: bool

	if not networked:
		# Path A — Offline: read keyboard, full simulation, no RPCs
		direction = _read_direction()
		facing = _read_facing(direction)
		if PlayerPrefs.control_scheme == PlayerPrefs.SCHEME_MOUSE:
			do_attack = _mouse_attack_pressed and _archetype_handler.can_attack()
			do_dash   = _mouse_dash_pressed and dash_cooldown <= 0.0
			_mouse_attack_pressed = false
			_mouse_dash_pressed   = false
		else:
			do_attack = Input.is_action_just_pressed("attack") and _archetype_handler.can_attack()
			do_dash   = Input.is_action_just_pressed("dash") and dash_cooldown <= 0.0
		var _ctrl := Input.is_key_pressed(KEY_CTRL)
		do_skill1 = (
			Input.is_action_just_pressed("skill1") 
			and skill1_cooldown <= 0.0 
			and skills_unlocked[0] 
			and not _ctrl
		)
		do_skill2 = (
			Input.is_action_just_pressed("skill2") 
			and skill2_cooldown <= 0.0 
			and skills_unlocked[1] 
			and not _ctrl
		)
		do_skill3 = (
			Input.is_action_just_pressed("skill3") 
			and skill3_cooldown <= 0.0 
			and skills_unlocked[2] 
			and not _ctrl
		)

	elif multiplayer.is_server():
		# Path B — Server: simulate all players authoritatively
		if is_multiplayer_authority():
			direction = _read_direction()
			facing = _read_facing(direction)
			if PlayerPrefs.control_scheme == PlayerPrefs.SCHEME_MOUSE:
				do_attack = _mouse_attack_pressed and _archetype_handler.can_attack()
				do_dash   = _mouse_dash_pressed and dash_cooldown <= 0.0
				_mouse_attack_pressed = false
				_mouse_dash_pressed   = false
			else:
				do_attack = Input.is_action_just_pressed("attack") and _archetype_handler.can_attack()
				do_dash   = Input.is_action_just_pressed("dash") and dash_cooldown <= 0.0
			var _ctrl2 := Input.is_key_pressed(KEY_CTRL)
			do_skill1 = (
				Input.is_action_just_pressed("skill1") 
				and skill1_cooldown <= 0.0 
				and skills_unlocked[0] 
				and not _ctrl2
				)
			do_skill2 = (
				Input.is_action_just_pressed("skill2") 
				and skill2_cooldown <= 0.0
				and skills_unlocked[1]
				and not _ctrl2
			)
			do_skill3 = (
				Input.is_action_just_pressed("skill3") 
				and skill3_cooldown <= 0.0 
				and skills_unlocked[2] 
				and not _ctrl2
			)

		else:
			direction = net_sync._received_direction
			facing = net_sync._received_facing
			do_attack = net_sync._pending_attack and _archetype_handler.can_attack()
			do_dash   = net_sync._pending_dash and dash_cooldown <= 0.0
			do_skill1 = net_sync._pending_skill1 and skill1_cooldown <= 0.0 and skills_unlocked[0]
			do_skill2 = net_sync._pending_skill2 and skill2_cooldown <= 0.0 and skills_unlocked[1]
			do_skill3 = net_sync._pending_skill3 and skill3_cooldown <= 0.0 and skills_unlocked[2]
			net_sync._pending_attack = false
			net_sync._pending_dash   = false
			net_sync._pending_skill1 = false
			net_sync._pending_skill2 = false
			net_sync._pending_skill3 = false

	else:
		# Path C — Client own player: predict locally and send input to server
		direction = _read_direction()
		facing = _read_facing(direction)
		if PlayerPrefs.control_scheme == PlayerPrefs.SCHEME_MOUSE:
			do_attack = _mouse_attack_pressed and _archetype_handler.can_attack()
			do_dash   = _mouse_dash_pressed and dash_cooldown <= 0.0
			_mouse_attack_pressed = false
			_mouse_dash_pressed   = false
		else:
			do_attack = Input.is_action_just_pressed("attack") and _archetype_handler.can_attack()
			do_dash   = Input.is_action_just_pressed("dash") and dash_cooldown <= 0.0
		var _ctrl := Input.is_key_pressed(KEY_CTRL)
		do_skill1 = (
			Input.is_action_just_pressed("skill1") 
			and skill1_cooldown <= 0.0 
			and skills_unlocked[0] 
			and not _ctrl
		)
		do_skill2 = (
			Input.is_action_just_pressed("skill2") 
			and skill2_cooldown <= 0.0 
			and skills_unlocked[1] 
			and not _ctrl
		)
		do_skill3 = (
			Input.is_action_just_pressed("skill3") 
			and skill3_cooldown <= 0.0 
			and skills_unlocked[2] 
			and not _ctrl
		)

		if debuff_no_dash_timer > 0.0:
			do_dash = false
		if debuff_silence_timer > 0.0:
			do_skill1 = false
			do_skill2 = false
			do_skill3 = false
		if direction != _last_sent_direction:
			net_sync._rpc_send_direction.rpc_id(1, direction)
			_last_sent_direction = direction
		if facing != _last_sent_facing:
			net_sync._rpc_send_facing.rpc_id(1, facing)
			_last_sent_facing = facing
		var action_mask := 0
		if do_attack: action_mask |= 1
		if do_dash:   action_mask |= 2
		if do_skill1: action_mask |= 4
		if do_skill2: action_mask |= 8
		if do_skill3: action_mask |= 16
		if action_mask != 0:
			net_sync._rpc_send_action.rpc_id(1, action_mask)

	# --- Debuff timers + enforcement ---

	if debuff_no_dash_timer > 0.0:
		debuff_no_dash_timer = max(0.0, debuff_no_dash_timer - delta)
		do_dash = false
	if debuff_silence_timer > 0.0:
		debuff_silence_timer = max(0.0, debuff_silence_timer - delta)
		do_skill1 = false
		do_skill2 = false
		do_skill3 = false
	if debuff_invert_timer > 0.0:
		debuff_invert_timer = max(0.0, debuff_invert_timer - delta)
		var tmp := do_attack
		do_attack = do_dash
		do_dash = tmp

	# --- Common simulation (all paths) ---

	move_direction = direction
	last_facing = facing
	$Sword.set_facing(last_facing.angle())

	# Cooldown ticks
	if attack_cooldown > 0.0:
		attack_cooldown = max(0.0, attack_cooldown - delta)
	if skill1_cooldown > 0.0:
		skill1_cooldown = max(0.0, skill1_cooldown - delta)
	if skill2_cooldown > 0.0:
		skill2_cooldown = max(0.0, skill2_cooldown - delta)
	if skill3_cooldown > 0.0:
		skill3_cooldown = max(0.0, skill3_cooldown - delta)

	# Spin tick
	if spinning:
		spin_timer -= delta
		$Sword.rotation += ArchetypePaladin.SPIN_SPEED * delta
		if spin_timer <= 0.0:
			spinning = false
			$Sword.exit_spin()
			if is_multiplayer_authority():
				$SfxSpin.stop()
				$SfxSpinLoop.stop()
				_spin_loop_timer = 0.0
			if networked and multiplayer.is_server():
				net_sync._rpc_trigger_spin_stop.rpc()

	# Dash / movement
	if predict_movement:
		if _dashing:
			_dash_timer -= delta
			velocity = last_facing * Constants.PLAYER_DASH_SPEED
			if _dash_timer <= 0.0:
				_dashing = false
				$DashParticles.emitting = false
				if networked and multiplayer.is_server():
					net_sync._rpc_set_dash_particles.rpc(Vector2.ZERO, false)
				if not networked or multiplayer.is_server():
					_archetype_handler.on_dash_end()
		else:
			if dash_cooldown > 0.0:
				dash_cooldown -= delta
			var speed_mult := (
				1.0 +
				Constants.SHOP_SPEED_MULT_PER_LEVEL *
				speed_level
			) * _archetype_handler.get_speed_mult()
			velocity = move_direction * SPEED * speed_mult
			if do_dash:
				if _archetype_handler.use_dash():
					pass  # archetype owns dash entirely (sets dash_cooldown internally)
				else:
					_dashing = true
					_dash_timer = _archetype_handler.get_dash_duration()
					dash_cooldown = Constants.PLAYER_DASH_COOLDOWN
					$DashParticles.direction = -last_facing
					$DashParticles.emitting = true
					if is_multiplayer_authority():
						$SfxDash.play()
					if networked and multiplayer.is_server():
						net_sync._rpc_set_dash_particles.rpc(-last_facing, true)

		move_and_slide()

		# Apply server correction nudge (client prediction only)
		if networked and not multiplayer.is_server() and _server_correction != Vector2.ZERO:
			var step := _server_correction.limit_length(CORRECTION_PX_PER_SEC * delta)
			position += step
			_server_correction -= step
			if _server_correction.length() < 0.5:
				_server_correction = Vector2.ZERO
			_cam_correction_offset -= step  # camera stays still; _process bleeds this back

		# Mob pushing — server and offline only
		if not networked or multiplayer.is_server():
			_push_mobs()
		elif is_multiplayer_authority():
			# Client own player: predict the push locally on observer mobs so they
			# scatter immediately instead of after a server round-trip.
			_push_mobs_client_predict(delta)

	queue_redraw()

	if not networked or multiplayer.is_server():
		# Paths A & B: authoritative attack + skill spawning + position broadcast
		if do_attack:
			_archetype_handler.use_attack()
			if is_multiplayer_authority():
				$SfxSwing.play()
			if networked:
				_archetype_handler.broadcast_attack()
		if do_skill1:
			_use_skill1()
			if is_multiplayer_authority():
				if archetype == Constants.ARCHETYPE_PALADIN:
					$SfxSpin.play()
				else:
					$SfxSkill1.play()
		if do_skill2:
			_use_skill2()
			if is_multiplayer_authority():
				$SfxSkill2.play()
		if do_skill3:
			_use_skill3()
			if is_multiplayer_authority():
				$SfxSkill3.play()
		_archetype_handler.physics_process(delta)
		if networked:
			_pos_sync_timer += delta
			if _pos_sync_timer >= POS_SYNC_INTERVAL:
				_pos_sync_timer = 0.0
				_rpc_sync_pos.rpc(position, velocity, last_facing, move_direction,
					skill1_cooldown, skill2_cooldown, skill3_cooldown, dash_cooldown)
	else:
		# Path C: local visual prediction — no server-authoritative spawning
		if do_attack:
			_archetype_handler.use_attack_visual()
			$SfxSwing.play()
		if do_skill1:
			skill1_cooldown = skill1_max_cooldown
			if archetype != Constants.ARCHETYPE_PALADIN:
				$SfxSkill1.play()
			_archetype_handler.on_skill1_client_predict()
		if do_skill2:
			skill2_cooldown = skill2_max_cooldown
			$SfxSkill2.play()
			_archetype_handler.on_skill2_client_predict()
		if do_skill3:
			skill3_cooldown = skill3_max_cooldown
			$SfxSkill3.play()
			_archetype_handler.on_skill3_client_predict()
		_archetype_handler.physics_process(delta)

# --- Input helper ---

func _read_direction() -> Vector2:
	var d := Vector2.ZERO
	if PlayerPrefs.control_scheme == PlayerPrefs.SCHEME_PAD:
		d = Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
		if d.length() < PAD_DEADZONE:
			d = Vector2.ZERO
	else:
		if Input.is_action_pressed("move_left"):  d.x -= 1
		if Input.is_action_pressed("move_right"): d.x += 1
		if Input.is_action_pressed("move_up"):    d.y -= 1
		if Input.is_action_pressed("move_down"):  d.y += 1
	if debuff_invert_timer > 0.0:
		d = -d
	return d.normalized()

func _read_facing(move_dir: Vector2) -> Vector2:
	if PlayerPrefs.control_scheme == PlayerPrefs.SCHEME_MOUSE:
		var d := get_global_mouse_position() - global_position
		if not d.is_zero_approx():
			return d.normalized()
	elif PlayerPrefs.control_scheme == PlayerPrefs.SCHEME_PAD:
		var d := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
		if d.length() >= PAD_DEADZONE:
			return d.normalized()
	elif move_dir != Vector2.ZERO:
		return move_dir
	return last_facing

# --- Skills ---

func _use_skill1() -> void:
	_archetype_handler.use_skill1()

func _use_skill2() -> void:
	_archetype_handler.use_skill2()

func _use_skill3() -> void:
	_archetype_handler.use_skill3()

func notify_trap_triggered() -> void:
	if _archetype_handler.has_method("on_trap_triggered"):
		_archetype_handler.on_trap_triggered()

func get_passive_counter() -> int:
	if _archetype_handler.has_method("get_hit_count"):
		return _archetype_handler.get_hit_count()
	return -1

func get_archetype_handler() -> ArchetypeBase:
	return _archetype_handler

# --- Upgrades (applied locally; the RPC entry points live on NetSync) ---

func apply_skill_upgrades() -> void:
	skill1_max_cooldown = _archetype_handler.get_skill1_max_cooldown()
	skill2_max_cooldown = _archetype_handler.get_skill2_max_cooldown()
	skill3_max_cooldown = _archetype_handler.get_skill3_max_cooldown()

func get_skill_name(n: int) -> String:
	match n:
		1: return _archetype_handler.get_skill1_name()
		2: return _archetype_handler.get_skill2_name()
		3: return _archetype_handler.get_skill3_name()
	return "Skill %d" % n

func apply_upgrades_to_sword() -> void:
	var dmg_bonus := damage_level * Constants.SHOP_DAMAGE_PER_LEVEL
	var sz_mult := 1.0 + sword_size_level * Constants.SHOP_SWORD_SIZE_PER_LEVEL
	var spd_mult := 1.0 - attack_speed_level * Constants.SHOP_ATTACK_SPEED_PER_LEVEL
	$Sword.apply_upgrades(dmg_bonus, sz_mult, spd_mult)

# --- Mob pushing (server and offline only) ---

func _push_mobs() -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius + Constants.MOB_RADIUS
	query.shape = circle
	query.transform = global_transform
	query.collision_mask = Constants.MOB_COLLISION_LAYER
	query.exclude = [get_rid()]
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var body: Node2D = hit["collider"]
		if not body.has_method("apply_push"):
			continue
		var dir := body.global_position - global_position
		if dir.is_zero_approx():
			continue
		body.apply_push(dir.normalized() * Constants.MOB_PUSH_FORCE * (6.0 if _dashing else 1.0))

func _push_mobs_client_predict(delta: float) -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius + Constants.MOB_RADIUS
	query.shape = circle
	query.transform = global_transform
	query.collision_mask = Constants.MOB_COLLISION_LAYER
	query.exclude = [get_rid()]
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var body: Node2D = hit["collider"]
		if not body.has_method("apply_client_push"):
			continue
		var dir := body.global_position - global_position
		if dir.is_zero_approx():
			continue
		body.apply_client_push(
				dir.normalized() * Constants.MOB_PUSH_FORCE * (6.0 if _dashing else 1.0) * delta)

# --- Position sync (server → all clients) ---

@rpc("any_peer", "unreliable_ordered")
func _rpc_sync_pos(pos: Vector2, vel: Vector2, facing: Vector2, move_dir: Vector2,
		s_sk1: float, s_sk2: float, s_sk3: float, s_dash: float) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked and not multiplayer.is_server() and is_multiplayer_authority() and Constants.CLIENT_PREDICTION:
		# Own player — trust local prediction entirely; no rubber-banding.
		# Server and client run the same physics with at most 1-frame input lag,
		# so they stay naturally in sync. Only snap on extreme divergence (bug/reconnect).
		var error := pos - position
		if error.length() > SNAP_THRESHOLD:
			# Large instantaneous jump (e.g. warlock teleport) — snap the camera
			# with the player. Preserving it here would leave the camera behind,
			# bleeding back only at the slow drift rate (~50 px/s) and lagging.
			position = pos
			_server_correction = Vector2.ZERO
			_cam_correction_offset = Vector2.ZERO
		elif error.length() > CORRECTION_THRESHOLD:
			_server_correction = error  # bleed toward server at 50 px/s — invisible but prevents drift
		# Always accept server cooldowns — they're discrete events, not continuous state
		skill1_cooldown = s_sk1
		skill2_cooldown = s_sk2
		skill3_cooldown = s_sk3
		dash_cooldown   = s_dash
	elif networked and not multiplayer.is_server() and is_multiplayer_authority():
		# Own player, prediction OFF — buffer + interpolate exactly like a remote
		# player so the camera shares the mobs' past-time timeline (no backward
		# sawtooth). Facing stays local for crisp aim; accept server cooldowns.
		var now := Time.get_ticks_msec() / 1000.0
		var snap := {
			"t": now, "pos": pos, "vel": vel,
			"facing": facing, "move_dir": move_dir,
		}
		if _snap_buffer.is_empty() or pos.distance_to(position) > OBSERVED_SNAP_THRESHOLD:
			_snap_buffer = [snap]
			position = pos
		else:
			_snap_buffer.append(snap)
			while _snap_buffer.size() > 8:
				_snap_buffer.pop_front()
		skill1_cooldown = s_sk1
		skill2_cooldown = s_sk2
		skill3_cooldown = s_sk3
		dash_cooldown   = s_dash
	else:
		# Observed player — buffer the snapshot and interpolate in _process (no
		# extrapolation, so there is no overshoot/snap-back when the player stops).
		var now := Time.get_ticks_msec() / 1000.0
		var snap := {
			"t": now, "pos": pos, "vel": vel,
			"facing": facing, "move_dir": move_dir,
		}
		# First snapshot, or a teleport-sized jump — drop history and snap so
		# interpolation doesn't slide across the gap.
		if _snap_buffer.is_empty() or pos.distance_to(position) > OBSERVED_SNAP_THRESHOLD:
			_snap_buffer = [snap]
			position = pos
			last_facing = facing
			move_direction = move_dir
			$Sword.set_facing(facing.angle())
		else:
			_snap_buffer.append(snap)
			# Keep a little history behind the render point plus the newest sample.
			while _snap_buffer.size() > 8:
				_snap_buffer.pop_front()
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
