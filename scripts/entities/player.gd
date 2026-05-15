extends CharacterBody2D

const SPEED = 800.0
var radius = 30.0
var color = Color(0.33, 0.29, 0.87)  # your purple

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

	velocity = direction.normalized() * SPEED
	move_and_slide()
	print("pos: ", position)

	# position.x = clamp(position.x, 0, Constants.WORLD_SIZE)
	# position.y = clamp(position.y, 0, Constants.WORLD_SIZE)

func _draw():
	draw_circle(Vector2.ZERO, radius, color)