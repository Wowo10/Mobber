extends Area2D

var swinging := false

func _ready() -> void:
	monitoring = false
	visible = false
	body_entered.connect(_on_body_entered)

func _process(_delta: float) -> void:
	queue_redraw()

func set_facing(angle: float) -> void:
	if not swinging:
		rotation = angle

func swing(facing_angle: float) -> void:
	if swinging:
		return
		
	swinging = true
	monitoring = true
	visible = true
	var arc := deg_to_rad(Constants.SWORD_ARC_HALF)
	rotation = facing_angle - arc
	var tween := create_tween()
	tween.tween_property(self, "rotation", facing_angle + arc, Constants.SWORD_SWING_DURATION)
	tween.tween_callback(_end_swing)

func _end_swing() -> void:
	monitoring = false
	swinging = false
	visible = false

func _on_body_entered(body: Node2D) -> void:
	if not body.has_method("take_damage"):
		return
	var networked: bool = multiplayer.multiplayer_peer is ENetMultiplayerPeer
	if not networked or multiplayer.is_server():
		body.take_damage(Constants.SWORD_DAMAGE)
	else:
		_request_hit.rpc_id(1, body.get_path())

@rpc("any_peer", "reliable")
func _request_hit(mob_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var mob := get_node_or_null(mob_path)
	if mob and mob.has_method("take_damage"):
		mob.take_damage(Constants.SWORD_DAMAGE)

func _draw() -> void:
	var r := Constants.PLAYER_START_RADIUS
	var sw := Constants.SWORD_WIDTH
	var sl := Constants.SWORD_LENGTH
	draw_rect(Rect2(r, -sw * 0.5, sl, sw), Color(0.78, 0.78, 0.82))
