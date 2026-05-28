extends CharacterBody2D

const SPEED = 800.0
const CANNONBALL_SCENE = preload("res://scenes/entities/cannonball.tscn")
const CONSECRATION_SCENE = preload("res://scenes/entities/consecration.tscn")
const TURRET_SCENE = preload("res://scenes/entities/turret_cannon.tscn")

var radius = 20.0
var color = Color(0.33, 0.29, 0.87)
var move_direction = Vector2.ZERO
var _last_facing := Vector2.RIGHT
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
var _speed_boost_timer := 0.0
var _spinning := false
var _spin_timer := 0.0
var _turret: Node2D = null

func _ready() -> void:
	# MultiplayerSpawner doesn't sync authority — derive it from node name "Player_N"
	var parts := name.split("_")
	if parts.size() == 2 and parts[0] == "Player":
		set_multiplayer_authority(parts[1].to_int())

	_apply_archetype()
	add_to_group("players")
	_setup_particles()
	if not is_multiplayer_authority():
		set_physics_process(false)
		$Camera2D.enabled = false
		return
	_setup_camera()

func _apply_archetype() -> void:
	match archetype:
		Constants.ARCHETYPE_KNIGHT:
			color = Color(0.6, 0.65, 0.85)
			skill1_max_cooldown = Constants.SKILL_SPIN_COOLDOWN
			skill2_max_cooldown = Constants.SKILL_CONSECRATION_COOLDOWN
		Constants.ARCHETYPE_PIRATE:
			color = Color(0.8, 0.35, 0.1)
			skill1_max_cooldown = Constants.SKILL_CANNON_COOLDOWN
			skill2_max_cooldown = Constants.SKILL_TURRET_COOLDOWN

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
	var arena_x: float = 0.0 if multiplayer.get_unique_id() == 1 \
		else float(Constants.WORLD_SIZE_X + Constants.ARENA_GAP)
	var cam := $Camera2D
	cam.limit_left = int(arena_x)
	cam.limit_right = int(arena_x + Constants.WORLD_SIZE_X)
	cam.limit_top = 0
	cam.limit_bottom = int(Constants.WORLD_SIZE_Y)
	cam.make_current()

func _physics_process(delta: float) -> void:
	var direction := Vector2.ZERO

	if Input.is_action_pressed("move_left"):
		direction.x -= 1
	if Input.is_action_pressed("move_right"):
		direction.x += 1
	if Input.is_action_pressed("move_up"):
		direction.y -= 1
	if Input.is_action_pressed("move_down"):
		direction.y += 1

	move_direction = direction.normalized()
	if move_direction != Vector2.ZERO:
		_last_facing = move_direction
		$Sword.set_facing(_last_facing.angle())

	if attack_cooldown > 0.0:
		attack_cooldown -= delta
	if skill1_cooldown > 0.0:
		skill1_cooldown = max(0.0, skill1_cooldown - delta)
	if skill2_cooldown > 0.0:
		skill2_cooldown = max(0.0, skill2_cooldown - delta)
	if _spinning:
		_spin_timer -= delta
		$Sword.rotation += Constants.SKILL_SPIN_SPEED * delta
		if _spin_timer <= 0.0:
			_spinning = false
			$Sword.exit_spin()

	if _dashing:
		_dash_timer -= delta
		velocity = _last_facing * Constants.PLAYER_DASH_SPEED
		if _dash_timer <= 0.0:
			_dashing = false
			$DashParticles.emitting = false
	else:
		if dash_cooldown > 0.0:
			dash_cooldown -= delta
		velocity = move_direction * SPEED * (1.0 + Constants.SHOP_SPEED_MULT_PER_LEVEL * speed_level)
		if Input.is_action_just_pressed("dash") and dash_cooldown <= 0.0:
			_dashing = true
			_dash_timer = Constants.PLAYER_DASH_DURATION
			dash_cooldown = Constants.PLAYER_DASH_COOLDOWN
			$DashParticles.direction = -_last_facing
			$DashParticles.emitting = true

	move_and_slide()
	_push_mobs()
	if not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		_rpc_sync_pos.rpc(position)
	queue_redraw()

	if Input.is_action_just_pressed("attack") and not $Sword.swinging and not _spinning:
		$Sword.swing(_last_facing.angle())
		attack_cooldown = $Sword.swing_duration
	if Input.is_action_just_pressed("skill1") and skill1_cooldown <= 0.0:
		_use_skill1()
	if Input.is_action_just_pressed("skill2") and skill2_cooldown <= 0.0:
		_use_skill2()

func _use_skill1() -> void:
	match archetype:
		Constants.ARCHETYPE_KNIGHT: _skill_spin()
		Constants.ARCHETYPE_PIRATE: _skill_cannon()

func _use_skill2() -> void:
	match archetype:
		Constants.ARCHETYPE_KNIGHT: _skill_consecration()
		Constants.ARCHETYPE_PIRATE: _skill_turret()

func _skill_spin() -> void:
	skill1_cooldown = Constants.SKILL_SPIN_COOLDOWN
	_spinning = true
	_spin_timer = Constants.SKILL_SPIN_DURATION
	$Sword.enter_spin()

func _skill_cannon() -> void:
	skill1_cooldown = Constants.SKILL_CANNON_COOLDOWN
	var cannonball = CANNONBALL_SCENE.instantiate()
	cannonball.direction = _last_facing
	cannonball.global_position = global_position + _last_facing * (radius + 12.0)
	cannonball.player_ref = self
	get_parent().add_child(cannonball)

func _skill_consecration() -> void:
	skill2_cooldown = Constants.SKILL_CONSECRATION_COOLDOWN
	var c := CONSECRATION_SCENE.instantiate()
	c.player_ref = self
	get_parent().add_child(c)
	c.global_position = global_position

func _skill_turret() -> void:
	skill2_cooldown = Constants.SKILL_TURRET_COOLDOWN
	if _turret and is_instance_valid(_turret):
		_turret.global_position = global_position
		_turret.facing = _last_facing
		_turret.reset_fire_timer()
	else:
		_turret = TURRET_SCENE.instantiate()
		_turret.facing = _last_facing
		_turret.player_ref = self
		get_parent().add_child(_turret)
		_turret.global_position = global_position

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

@rpc("any_peer", "reliable")
func rpc_request_hit(mob_path: NodePath, damage: float, knockback: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var mob := get_node_or_null(mob_path)
	if mob and mob.has_method("take_damage"):
		mob.take_damage(damage, knockback)

func _push_mobs() -> void:
	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
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
		var impulse := dir.normalized() * Constants.MOB_PUSH_FORCE * (6.0 if _dashing else 1.0)
		if not networked or multiplayer.is_server():
			body.apply_push(impulse)
		else:
			var arena: Node = body.get_parent().get_parent()
			if arena.is_inside_tree():
				arena.rpc_push_mob.rpc_id(1, body.name, impulse)

@rpc("any_peer", "unreliable_ordered")
func _rpc_sync_pos(pos: Vector2) -> void:
	if not is_multiplayer_authority():
		position = pos
		queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)
	if move_direction == Vector2.ZERO:
		return
	var tip: Vector2 = move_direction * (radius + 14.0)
	var perp: Vector2 = move_direction.rotated(PI / 2.0)
	var base_center: Vector2 = move_direction * (radius + 2.0)
	draw_colored_polygon(PackedVector2Array([
		tip,
		base_center + perp * 7.0,
		base_center - perp * 7.0
	]), Color.WHITE)
