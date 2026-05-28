extends Area2D

var swinging := false
var spin_mode := false
var _spin_cooldowns := {}
var damage_bonus: float = 0.0
var size_mult: float = 1.0
var swing_duration: float = Constants.SWORD_SWING_DURATION

func _ready() -> void:
	monitoring = false
	visible = false
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	queue_redraw()
	if spin_mode:
		for key in _spin_cooldowns.keys():
			_spin_cooldowns[key] -= delta
			if _spin_cooldowns[key] <= 0.0:
				_spin_cooldowns.erase(key)

func set_facing(angle: float) -> void:
	if not swinging and not spin_mode:
		rotation = angle

func swing(facing_angle: float) -> void:
	if swinging or spin_mode:
		return

	swinging = true
	monitoring = true
	visible = true
	var arc := deg_to_rad(Constants.SWORD_ARC_HALF)
	rotation = facing_angle - arc
	var tween := create_tween()
	tween.tween_property(self, "rotation", facing_angle + arc, swing_duration)
	tween.tween_callback(_end_swing)

func _end_swing() -> void:
	monitoring = false
	swinging = false
	visible = false

func enter_spin() -> void:
	spin_mode = true
	monitoring = true
	visible = true
	_spin_cooldowns.clear()

func exit_spin() -> void:
	spin_mode = false
	monitoring = false
	visible = false
	_spin_cooldowns.clear()

func _on_body_entered(body: Node2D) -> void:
	if not body.has_method("take_damage"):
		return
	var networked: bool = not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	var damage: float
	var knockback_force: float
	if spin_mode:
		var rid = body.get_rid()
		if _spin_cooldowns.has(rid):
			return
		_spin_cooldowns[rid] = Constants.SKILL_SPIN_HIT_INTERVAL
		damage = Constants.SKILL_SPIN_DAMAGE + damage_bonus
		knockback_force = Constants.SKILL_SPIN_KNOCKBACK
	else:
		damage = Constants.SWORD_DAMAGE + damage_bonus
		knockback_force = Constants.MOB_KNOCKBACK
	var knockback: Vector2 = (body.global_position - get_parent().global_position).normalized() \
		* knockback_force
	if not networked or multiplayer.is_server():
		body.take_damage(damage, knockback)
	else:
		_request_hit.rpc_id(1, body.get_path(), damage, knockback)

@rpc("any_peer", "reliable")
func _request_hit(mob_path: NodePath, damage: float, knockback: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var mob := get_node_or_null(mob_path)
	if mob and mob.has_method("take_damage"):
		mob.take_damage(damage, knockback)

func apply_upgrades(dmg_bonus: float, sz_mult: float, spd_mult: float) -> void:
	damage_bonus = dmg_bonus
	size_mult = sz_mult
	swing_duration = maxf(0.08, Constants.SWORD_SWING_DURATION * spd_mult)
	var col_shape := $CollisionShape2D.shape as RectangleShape2D
	col_shape.size = Vector2(Constants.SWORD_LENGTH * sz_mult, Constants.SWORD_WIDTH * sz_mult)
	$CollisionShape2D.position.x = Constants.PLAYER_START_RADIUS + Constants.SWORD_LENGTH * sz_mult * 0.5

func _draw() -> void:
	var r := Constants.PLAYER_START_RADIUS
	var sw := Constants.SWORD_WIDTH * size_mult
	var sl := Constants.SWORD_LENGTH * size_mult
	draw_rect(Rect2(r, -sw * 0.5, sl, sw), Color(0.78, 0.78, 0.82))
