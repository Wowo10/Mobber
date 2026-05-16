extends Area2D

var _swinging := false

func _ready() -> void:
	monitoring = false
	visible = false
	body_entered.connect(_on_body_entered)

func _process(_delta: float) -> void:
	queue_redraw()

func set_facing(angle: float) -> void:
	if not _swinging:
		rotation = angle

func swing(facing_angle: float) -> void:
	if _swinging:
		return
	_swinging = true
	monitoring = true
	visible = true
	var arc := deg_to_rad(Constants.SWORD_ARC_HALF)
	rotation = facing_angle - arc
	var tween := create_tween()
	tween.tween_property(self, "rotation", facing_angle + arc, Constants.SWORD_SWING_DURATION)
	tween.tween_callback(_end_swing)

func _end_swing() -> void:
	monitoring = false
	_swinging = false
	visible = false

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(Constants.SWORD_DAMAGE)

func _draw() -> void:
	var r := Constants.PLAYER_START_RADIUS
	var sw := Constants.SWORD_WIDTH
	var sl := Constants.SWORD_LENGTH
	draw_rect(Rect2(r, -sw * 0.5, sl, sw), Color(0.78, 0.78, 0.82))
