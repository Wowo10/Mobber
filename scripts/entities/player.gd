extends CharacterBody2D

const SPEED = 800.0
const PAD_DEADZONE := 0.15

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

# Server-side input buffers — written by client RPCs, consumed each physics tick
var _received_direction := Vector2.ZERO
var _pending_attack := false
var _pending_dash := false
var _pending_skill1 := false
var _pending_skill2 := false
var _pending_skill3 := false

var _archetype_handler: ArchetypeBase

# Client-side prediction — pending position correction from server reconciliation
var _server_correction := Vector2.ZERO
var _received_facing := Vector2.RIGHT
var _mouse_attack_pressed := false
var _mouse_dash_pressed := false

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

func shake_camera(duration: float, intensity: float) -> void:
	_shake_duration = duration
	_shake_max_duration = duration
	_shake_intensity = intensity

func _process(delta: float) -> void:
	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked and not multiplayer.is_server() and not is_multiplayer_authority() and spinning:
		$Sword.rotation += ArchetypePaladin.SPIN_SPEED * delta
	if _shake_duration > 0.0:
		_shake_duration -= delta
		var strength := _shake_intensity * (_shake_duration / _shake_max_duration)
		$Camera2D.offset = Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		if _shake_duration <= 0.0:
			$Camera2D.offset = Vector2.ZERO

func _input(event: InputEvent) -> void:
	if PlayerPrefs.control_scheme != PlayerPrefs.SCHEME_MOUSE:
		return
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_mouse_attack_pressed = true
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_dash_pressed = true

# --- Simulation ---

func _physics_process(delta: float) -> void:
	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)

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
		do_skill1 = Input.is_action_just_pressed("skill1") and skill1_cooldown <= 0.0 and skills_unlocked[0]
		do_skill2 = Input.is_action_just_pressed("skill2") and skill2_cooldown <= 0.0 and skills_unlocked[1]
		do_skill3 = Input.is_action_just_pressed("skill3") and skill3_cooldown <= 0.0 and skills_unlocked[2]

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
			do_skill1 = Input.is_action_just_pressed("skill1") and skill1_cooldown <= 0.0 and skills_unlocked[0]
			do_skill2 = Input.is_action_just_pressed("skill2") and skill2_cooldown <= 0.0 and skills_unlocked[1]
			do_skill3 = Input.is_action_just_pressed("skill3") and skill3_cooldown <= 0.0 and skills_unlocked[2]
		else:
			direction = _received_direction
			facing = _received_facing
			do_attack = _pending_attack and _archetype_handler.can_attack()
			do_dash   = _pending_dash and dash_cooldown <= 0.0
			do_skill1 = _pending_skill1 and skill1_cooldown <= 0.0 and skills_unlocked[0]
			do_skill2 = _pending_skill2 and skill2_cooldown <= 0.0 and skills_unlocked[1]
			do_skill3 = _pending_skill3 and skill3_cooldown <= 0.0 and skills_unlocked[2]
			_pending_attack = false
			_pending_dash   = false
			_pending_skill1 = false
			_pending_skill2 = false
			_pending_skill3 = false

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
		do_skill1 = Input.is_action_just_pressed("skill1") and skill1_cooldown <= 0.0 and skills_unlocked[0]
		do_skill2 = Input.is_action_just_pressed("skill2") and skill2_cooldown <= 0.0 and skills_unlocked[1]
		do_skill3 = Input.is_action_just_pressed("skill3") and skill3_cooldown <= 0.0 and skills_unlocked[2]
		_rpc_send_direction.rpc_id(1, direction)
		_rpc_send_facing.rpc_id(1, facing)
		var action_mask := 0
		if do_attack: action_mask |= 1
		if do_dash:   action_mask |= 2
		if do_skill1: action_mask |= 4
		if do_skill2: action_mask |= 8
		if do_skill3: action_mask |= 16
		if action_mask != 0:
			_rpc_send_action.rpc_id(1, action_mask)

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
		attack_cooldown -= delta
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
			if not networked or multiplayer.is_server():
				_archetype_handler.on_dash_end()
	else:
		if dash_cooldown > 0.0:
			dash_cooldown -= delta
		var speed_mult := (1.0 + Constants.SHOP_SPEED_MULT_PER_LEVEL * speed_level) * _archetype_handler.get_speed_mult()
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
			if is_multiplayer_authority():
				$SfxSwing.play()
			if networked:
				_archetype_handler.broadcast_attack()
		if do_skill1:
			_use_skill1()
			if is_multiplayer_authority() and archetype == Constants.ARCHETYPE_PALADIN:
				$SfxSpin.play()
		if do_skill2:
			_use_skill2()
			if is_multiplayer_authority():
				$SfxSkill.play()
		if do_skill3:
			_use_skill3()
			if is_multiplayer_authority():
				$SfxSkill.play()
		_archetype_handler.physics_process(delta)
		if networked:
			_rpc_sync_pos.rpc(position, last_facing, move_direction,
				skill1_cooldown, skill2_cooldown, skill3_cooldown, dash_cooldown)
	else:
		# Path C: local visual prediction — no server-authoritative spawning
		if do_attack:
			_archetype_handler.use_attack_visual()
			$SfxSwing.play()
		if do_skill1:
			skill1_cooldown = skill1_max_cooldown
			_archetype_handler.on_skill1_client_predict()
		if do_skill2:
			skill2_cooldown = skill2_max_cooldown
			$SfxSkill.play()
			_archetype_handler.on_skill2_client_predict()
		if do_skill3:
			skill3_cooldown = skill3_max_cooldown
			$SfxSkill.play()
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

# --- Input RPCs (client → server) ---

@rpc("any_peer", "unreliable_ordered")
func _rpc_send_direction(direction: Vector2) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	_received_direction = direction

@rpc("any_peer", "unreliable_ordered")
func _rpc_send_facing(f: Vector2) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	_received_facing = f

@rpc("any_peer", "reliable")
func _rpc_send_action(action_mask: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	if action_mask & 1: _pending_attack = true
	if action_mask & 2: _pending_dash   = true
	if action_mask & 4:  _pending_skill1 = true
	if action_mask & 8:  _pending_skill2 = true
	if action_mask & 16: _pending_skill3 = true

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

# --- Upgrade RPCs ---

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

@rpc("any_peer", "reliable")
func rpc_apply_speed_level(level: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	speed_level = level

@rpc("any_peer", "reliable")
func rpc_apply_damage_level(level: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	damage_level = level
	apply_upgrades_to_sword()

@rpc("any_peer", "reliable")
func rpc_apply_sword_size_level(level: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	sword_size_level = level
	apply_upgrades_to_sword()

@rpc("any_peer", "reliable")
func rpc_apply_attack_speed_level(level: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	attack_speed_level = level
	apply_upgrades_to_sword()

@rpc("any_peer", "reliable")
func rpc_apply_skill1_level(level: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	skill1_level = level
	apply_skill_upgrades()

@rpc("any_peer", "reliable")
func rpc_apply_skill2_level(level: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	skill2_level = level
	apply_skill_upgrades()

@rpc("any_peer", "reliable")
func rpc_apply_skill3_level(level: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	skill3_level = level
	apply_skill_upgrades()

@rpc("any_peer", "reliable")
func rpc_sync_skills_unlocked(unlocked: Array) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	skills_unlocked = unlocked

@rpc("any_peer", "reliable")
func rpc_apply_debuff(type: int, duration: float) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	match type:
		Constants.DEBUFF_NO_DASH: debuff_no_dash_timer = duration
		Constants.DEBUFF_SILENCE: debuff_silence_timer = duration
		Constants.DEBUFF_INVERT:  debuff_invert_timer  = duration

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
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypePirate).spawn_visual_cannonball(pos, dir, homing)

@rpc("any_peer", "reliable")
func rpc_place_turret(pos: Vector2, fac: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypePirate).place_visual_turret(pos, fac)

@rpc("any_peer", "reliable")
func rpc_place_pirate_barrel(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypePirate).spawn_barrel_local(pos, true)

@rpc("any_peer", "reliable")
func rpc_detonate_pirate_barrel() -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypePirate).detonate_visual_barrel()

@rpc("any_peer", "reliable")
func rpc_knight_shield_bash(pos: Vector2, dir: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypePaladin).spawn_bash_visual(pos, dir)

@rpc("any_peer", "reliable")
func rpc_spawn_consecration(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypePaladin).spawn_consecration_local(pos, true)

@rpc("any_peer", "reliable")
func rpc_spawn_mage_bolt(pos: Vector2, dir: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	if is_multiplayer_authority():
		return
	(_archetype_handler as ArchetypeMage).spawn_bolt_local(pos, dir, true)

@rpc("any_peer", "reliable")
func rpc_spawn_rain(pos: Vector2, rs: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeMage).spawn_rain_local(pos, true, rs)

@rpc("any_peer", "reliable")
func rpc_spawn_fireball(pos: Vector2, dir: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeMage).spawn_fireball_local(pos, dir, true)

@rpc("any_peer", "reliable")
func rpc_spawn_cyber_bullet(pos: Vector2, dir: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	if is_multiplayer_authority():
		return
	(_archetype_handler as ArchetypeCyborg).spawn_bullet_local(pos, dir, true)

@rpc("any_peer", "reliable")
func rpc_spawn_cyber_ray(pos: Vector2, facing: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeCyborg).spawn_ray_local(pos, facing, true)

@rpc("any_peer", "reliable")
func rpc_set_cyborg_ranged_mode(active: bool) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeCyborg).set_ranged_mode(active)

@rpc("any_peer", "reliable")
func rpc_shadowstep_visual(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeAssassin).spawn_visual_at(pos)

@rpc("any_peer", "reliable")
func rpc_set_berserker_rage(active: bool) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeBerserker).set_rage(active)

@rpc("any_peer", "reliable")
func rpc_spawn_ground_slam(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeBerserker).spawn_slam_local(pos, true)

@rpc("any_peer", "reliable")
func rpc_spawn_warlock_bolt(pos: Vector2, dir: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	if is_multiplayer_authority():
		return
	(_archetype_handler as ArchetypeWarlock).spawn_bolt_local(pos, dir, true)

@rpc("any_peer", "reliable")
func rpc_spawn_drain_life() -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeWarlock).spawn_drain_local(true)

@rpc("any_peer", "reliable")
func rpc_spawn_void_rift(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeWarlock).spawn_rift_local(pos, true)

@rpc("any_peer", "reliable")
func rpc_spawn_fan_of_knives(pos: Vector2, facing_angle: float) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	if is_multiplayer_authority():
		return
	(_archetype_handler as ArchetypeAssassin).spawn_fan_local(pos, facing_angle, true)

@rpc("any_peer", "reliable")
func rpc_place_warlock_portal(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeWarlock).place_visual_portal(pos)

@rpc("any_peer", "reliable")
func rpc_consume_warlock_portal() -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeWarlock).consume_visual_portal()

@rpc("any_peer", "reliable")
func rpc_mage_force_pull(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeMage).spawn_pull_visual(pos)

@rpc("any_peer", "reliable")
func rpc_spawn_arcane_implosion(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeMage).spawn_implosion_local(pos, true)

@rpc("any_peer", "reliable")
func rpc_set_cyborg_overclock(active: bool) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeCyborg).set_overclock(active)

@rpc("any_peer", "reliable")
func rpc_spawn_berserker_mini_smash(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeBerserker).spawn_mini_smash_local(pos, true)

@rpc("any_peer", "reliable")
func rpc_berserker_set_hit_count(count: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeBerserker).set_hit_count(count)

@rpc("any_peer", "reliable")
func rpc_spawn_assassin_trap(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeAssassin).spawn_trap_local(pos, true)

@rpc("any_peer", "reliable")
func rpc_spawn_warlock_wisp() -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(_archetype_handler as ArchetypeWarlock).spawn_wisp_local(true)

@rpc("any_peer", "unreliable_ordered")
func _rpc_set_dash_particles(dir: Vector2, emitting: bool) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	$DashParticles.direction = dir
	$DashParticles.emitting = emitting

@rpc("any_peer", "reliable")
func rpc_trigger_swing(facing_angle: float) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	$Sword.swing(facing_angle)

@rpc("any_peer", "reliable")
func rpc_trigger_spin_start() -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	spinning = true
	spin_timer = ArchetypePaladin.SPIN_DURATION
	$Sword.enter_spin()
	if is_multiplayer_authority():
		$SfxSpin.play()

@rpc("any_peer", "reliable")
func _rpc_trigger_spin_stop() -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	spinning = false
	$Sword.exit_spin()

# --- Position sync (server → all clients) ---

@rpc("any_peer", "unreliable_ordered")
func _rpc_sync_pos(pos: Vector2, facing: Vector2, move_dir: Vector2,
		s_sk1: float, s_sk2: float, s_sk3: float, s_dash: float) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked and not multiplayer.is_server() and is_multiplayer_authority():
		# Own player — reconcile predicted position and cooldowns with server's authoritative state
		var error := pos - position
		if error.length() > SNAP_THRESHOLD:
			position = pos
			_server_correction = Vector2.ZERO
		elif error.length() > CORRECTION_THRESHOLD:
			_server_correction = error
		# Always accept server cooldowns — they are authoritative
		skill1_cooldown = s_sk1
		skill2_cooldown = s_sk2
		skill3_cooldown = s_sk3
		dash_cooldown   = s_dash
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
