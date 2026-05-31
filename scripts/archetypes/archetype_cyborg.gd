class_name ArchetypeCyborg
extends ArchetypeBase

const BULLET_SCENE = preload("res://scenes/archetypes/cyborg/cyber_bullet.tscn")
const RAY_SCENE = preload("res://scenes/archetypes/cyborg/cyber_ray.tscn")

const BULLET_COOLDOWN = 0.45
const TARGETING_COOLDOWN = 9.0
const RAY_COOLDOWN = 10.0

var _ranged_mode := false

func get_color() -> Color:
	return Color(0.05, 0.65, 0.8)

func get_skill1_color() -> Color:
	return Color(0.1, 0.85, 1.0)

func get_skill2_color() -> Color:
	return Color(0.0, 0.5, 0.8)

func get_skill1_max_cooldown() -> float:
	return TARGETING_COOLDOWN

func get_skill2_max_cooldown() -> float:
	return RAY_COOLDOWN

func can_attack() -> bool:
	if _ranged_mode:
		return _player.attack_cooldown <= 0.0
	return not _player.get_node("Sword").swinging and not _player.spinning

func use_attack() -> void:
	if _ranged_mode:
		_player.attack_cooldown = BULLET_COOLDOWN
		var pos: Vector2 = _player.global_position + _player.last_facing * (_player.radius + 10.0)
		spawn_bullet_local(pos, _player.last_facing, false)
	else:
		super.use_attack()

func broadcast_attack() -> void:
	if _ranged_mode:
		_player.rpc_spawn_cyber_bullet.rpc(
			_player.global_position + _player.last_facing * (_player.radius + 10.0),
			_player.last_facing)
	else:
		super.broadcast_attack()

func use_attack_visual() -> void:
	if _ranged_mode:
		_player.attack_cooldown = BULLET_COOLDOWN
		var pos: Vector2 = _player.global_position + _player.last_facing * (_player.radius + 10.0)
		spawn_bullet_local(pos, _player.last_facing, true)
	else:
		super.use_attack_visual()

func use_skill1() -> void:
	_player.skill1_cooldown = TARGETING_COOLDOWN
	set_ranged_mode(not _ranged_mode)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_set_cyborg_ranged_mode.rpc(_ranged_mode)

func use_skill2() -> void:
	_player.skill2_cooldown = RAY_COOLDOWN
	spawn_ray_local(_player.global_position, _player.last_facing, false)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_spawn_cyber_ray.rpc(_player.global_position, _player.last_facing)

func on_skill1_client_predict() -> void:
	set_ranged_mode(not _ranged_mode)

func set_ranged_mode(active: bool) -> void:
	_ranged_mode = active
	_player.color = Color(0.2, 0.95, 1.0) if active else get_color()
	_player.queue_redraw()

func spawn_bullet_local(pos: Vector2, dir: Vector2, visual_only: bool) -> void:
	var bullet := BULLET_SCENE.instantiate()
	bullet.direction = dir
	bullet.player_ref = _player
	bullet.visual_only = visual_only
	_player.get_parent().add_child(bullet)
	bullet.global_position = pos

func spawn_ray_local(pos: Vector2, facing: Vector2, visual_only: bool) -> void:
	var ray := RAY_SCENE.instantiate()
	ray.player_ref = _player
	ray.visual_only = visual_only
	ray.facing = facing
	_player.get_parent().add_child(ray)
	ray.global_position = pos
