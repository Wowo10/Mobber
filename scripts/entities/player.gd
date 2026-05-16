extends CharacterBody2D

const SPEED = 800.0
var radius = 30.0
var color = Color(0.33, 0.29, 0.87)
var move_direction = Vector2.ZERO
var _last_facing := Vector2.RIGHT

var _dashing := false
var _dash_timer := 0.0
var _dash_cooldown := 0.0

func _ready() -> void:
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

func _physics_process(delta):
	var direction = Vector2.ZERO

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
	queue_redraw()

	if Input.is_action_just_pressed("attack"):
		$Sword.swing(_last_facing.angle())

func _draw():
	draw_circle(Vector2.ZERO, radius, color)
	if move_direction == Vector2.ZERO:
		return

	# Triangle tip sits just beyond the circle edge
	var tip = move_direction * (radius + 14.0)
	var perp = move_direction.rotated(PI / 2.0)
	var base_center = move_direction * (radius + 2.0)
	var p1 = tip
	var p2 = base_center + perp * 7.0
	var p3 = base_center - perp * 7.0
	draw_colored_polygon(PackedVector2Array([p1, p2, p3]), Color.WHITE)
