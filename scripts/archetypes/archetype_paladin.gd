class_name ArchetypePaladin
extends ArchetypeBase

const CONSECRATION_SCENE = preload("res://scenes/archetypes/knight/consecration.tscn")

const SPIN_COOLDOWN = 7.0
const SPIN_DURATION = 2.5
const SPIN_SPEED = TAU * 3.0
const CONSECRATION_COOLDOWN = 8.0
const BASH_COOLDOWN = 7.0
const BASH_RANGE = 130.0
const BASH_HALF_WIDTH = 55.0
const BASH_DAMAGE = 6.0
const BASH_KNOCKBACK = 4500.0
const BASH_SLOW_MULT = 0.35
const BASH_SLOW_DURATION = 3.0

func get_color() -> Color:
	return Color(0.6, 0.65, 0.85)

func get_skill1_color() -> Color:
	return Color(0.15, 0.4, 1.0)

func get_skill1_icon() -> Texture2D:
	return load("res://assets/icons/spinning-sword.png")

func get_skill2_color() -> Color:
	return Color(1.0, 0.85, 0.2)

func get_skill2_icon() -> Texture2D:
	return load("res://assets/icons/holy-symbol.png")

func get_skill1_name() -> String:
	return "Spin"

func get_skill2_name() -> String:
	return "Consecration"

func get_skill3_name() -> String:
	return "Shield Bash"

func get_attack_description() -> String:
	return "Broad sword swing."

func get_dash_description() -> String:
	return "Standard dash."

func get_skill1_description() -> String:
	return "Spins your sword continuously for 2.5s.\nCooldown: 7s"

func get_skill2_description() -> String:
	return "Creates a holy zone that damages enemies over time.\nCooldown: 8s"

func get_skill3_description() -> String:
	return "Slams your shield forward, dealing damage and slowing enemies.\nCooldown: 7s"

func get_skill1_max_cooldown() -> float:
	return SPIN_COOLDOWN * (1.0 - Constants.SHOP_SKILL_CD_REDUCTION_PER_LEVEL * _player.skill1_level)

func get_skill2_max_cooldown() -> float:
	return CONSECRATION_COOLDOWN * (1.0 - Constants.SHOP_SKILL_CD_REDUCTION_PER_LEVEL * _player.skill2_level)

func get_skill3_color() -> Color:
	return Color(0.2, 0.55, 1.0)

func get_skill3_icon() -> Texture2D:
	return load("res://assets/icons/shield-bash.png")

func get_skill3_max_cooldown() -> float:
	return BASH_COOLDOWN * (1.0 - Constants.SHOP_SKILL_CD_REDUCTION_PER_LEVEL * _player.skill3_level)

func use_skill1() -> void:
	_player.skill1_cooldown = get_skill1_max_cooldown()
	_player.spinning = true
	_player.spin_timer = SPIN_DURATION + _player.skill1_level * 0.5
	_player.get_node("Sword").enter_spin()
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_trigger_spin_start.rpc()

func use_skill2() -> void:
	_player.skill2_cooldown = get_skill2_max_cooldown()
	spawn_consecration_local(_player.global_position, false)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_spawn_consecration.rpc(_player.global_position)

func use_skill3() -> void:
	_player.skill3_cooldown = get_skill3_max_cooldown()
	_player.shake_camera(0.3, 8.0)
	var pos: Vector2 = _player.global_position
	var dir: Vector2 = _player.last_facing
	_do_bash(pos, dir)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_knight_shield_bash.rpc(pos, dir)

func _do_bash(pos: Vector2, dir: Vector2) -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(BASH_RANGE, BASH_HALF_WIDTH * 2.0)
	query.shape = box
	query.transform = Transform2D(dir.angle(), pos + dir * (_player.radius + BASH_RANGE * 0.5))
	query.collision_mask = 1
	for hit in _player.get_world_2d().direct_space_state.intersect_shape(query, 16):
		var body = hit["collider"]
		if body.has_method("take_damage"):
			body.take_damage(BASH_DAMAGE + _player.skill3_level * 3.0, dir * BASH_KNOCKBACK * (1.0 + 0.3 * _player.skill3_level), _player)
			if body.has_method("apply_slow"):
				body.apply_slow(BASH_SLOW_MULT, BASH_SLOW_DURATION)
	spawn_bash_visual(pos, dir)

func spawn_bash_visual(pos: Vector2, dir: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.global_position = pos + dir * _player.radius
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 28
	p.lifetime = 0.35
	p.direction = Vector2(dir.x, dir.y)
	p.spread = 40.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 200.0
	p.initial_velocity_max = 520.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 9.0
	p.color = Color(0.88, 0.93, 1.0, 0.95)
	p.emitting = true
	_player.get_parent().add_child(p)
	_player.get_tree().create_timer(p.lifetime + 0.1).timeout.connect(p.queue_free)

func on_skill3_client_predict() -> void:
	spawn_bash_visual(_player.global_position, _player.last_facing)

func spawn_consecration_local(pos: Vector2, visual_only: bool) -> void:
	var c := CONSECRATION_SCENE.instantiate()
	c.player_ref = _player
	c.visual_only = visual_only
	c.skill_level = _player.skill2_level
	_player.get_parent().add_child(c)
	c.global_position = pos
