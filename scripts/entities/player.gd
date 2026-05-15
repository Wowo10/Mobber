extends CharacterBody2D

const SPEED = 800.0
var radius = 30.0
var color = Color(0.33, 0.29, 0.87)  # your purple
var move_direction = Vector2.ZERO

func _physics_process(_delta):
	var direction = Vector2.ZERO

	if Input.is_action_pressed("ui_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_right"):
		direction.x += 1
	if Input.is_action_pressed("ui_up"):
		direction.y -= 1
	if Input.is_action_pressed("ui_down"):
		direction.y += 1

	move_direction = direction.normalized()
	velocity = move_direction * SPEED
	move_and_slide()
	queue_redraw()

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