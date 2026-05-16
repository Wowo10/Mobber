extends CharacterBody2D

const SPEED = 800.0
var radius = 30.0
var color = Color(0.33, 0.29, 0.87)
var move_direction = Vector2.ZERO
var _last_facing := Vector2.RIGHT

var _dashing := false
var _dash_timer := 0.0
var _dash_cooldown := 0.0
var _attack_cooldown := 0.0

func _ready() -> void:
	# MultiplayerSpawner doesn't sync authority — derive it from node name "Player_N"
	var parts := name.split("_")
	if parts.size() == 2 and parts[0] == "Player":
		set_multiplayer_authority(parts[1].to_int())

	_setup_particles()
	if not is_multiplayer_authority():
		set_physics_process(false)
		$Camera2D.enabled = false
		return
	_setup_camera()

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

	if _dashing:
		_dash_timer -= delta
		velocity = _last_facing * Constants.PLAYER_DASH_SPEED
		if _dash_timer <= 0.0:
			_dashing = false
			$DashParticles.emitting = false
	else:
		if _dash_cooldown > 0.0:
			_dash_cooldown -= delta
		velocity = move_direction * SPEED
		if Input.is_action_just_pressed("dash") and _dash_cooldown <= 0.0:
			_dashing = true
			_dash_timer = Constants.PLAYER_DASH_DURATION
			_dash_cooldown = Constants.PLAYER_DASH_COOLDOWN
			$DashParticles.direction = -_last_facing
			$DashParticles.emitting = true

	move_and_slide()
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_rpc_sync_pos.rpc(position)
	queue_redraw()

	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	if Input.is_action_just_pressed("attack") and not $Sword.swinging:
		$Sword.swing(_last_facing.angle())
		_attack_cooldown = Constants.SWORD_SWING_DURATION

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
