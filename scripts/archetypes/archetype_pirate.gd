class_name ArchetypePirate
extends ArchetypeBase

const CANNONBALL_SCENE = preload("res://scenes/archetypes/pirate/cannonball.tscn")
const TURRET_SCENE = preload("res://scenes/archetypes/pirate/turret_cannon.tscn")
const BARREL_SCENE = preload("res://scenes/archetypes/pirate/barrel.tscn")

const DATA = preload("res://data/archetypes/pirate.tres")
const BARREL_PLACE_COOLDOWN = 0.5

var _turret: Node2D = null
var _visual_turret: Node2D = null
var _barrel_node: Node2D = null
var _visual_barrel: Node2D = null

func get_data_resource() -> ArchetypeData:
	return DATA

func use_skill1() -> void:
	_player.skill1_cooldown = get_skill1_max_cooldown()
	var shot_count: int = 1 + _player.skill1_level
	for i in range(shot_count):
		var angle_offset := deg_to_rad((i - _player.skill1_level * 0.5) * 10.0)
		var dir: Vector2 = _player.last_facing.rotated(angle_offset)
		var cannonball = CANNONBALL_SCENE.instantiate()
		cannonball.direction = dir
		cannonball.global_position = _player.global_position + dir * (_player.radius + 12.0)
		cannonball.player_ref = _player
		_player.get_parent().add_child(cannonball)
		_player.net_sync.broadcast_cannonball(cannonball.global_position, dir, true)

func use_skill2() -> void:
	_player.skill2_cooldown = get_skill2_max_cooldown()
	if _turret and is_instance_valid(_turret):
		_turret.global_position = _player.global_position
		_turret.facing = _player.last_facing
		_turret.skill_level = _player.skill2_level
		_turret.reset_fire_timer()
	else:
		_turret = TURRET_SCENE.instantiate()
		_turret.facing = _player.last_facing
		_turret.skill_level = _player.skill2_level
		_turret.player_ref = _player
		_player.get_parent().add_child(_turret)
		_turret.global_position = _player.global_position
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.net_sync.rpc_place_turret.rpc(_player.global_position, _player.last_facing)

func use_skill3() -> void:
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if is_instance_valid(_barrel_node):
		_barrel_node.detonate()
		_barrel_node = null
		_player.shake_camera(0.45, 14.0)
		_player.skill3_cooldown = get_skill3_max_cooldown()
		if networked:
			_player.net_sync.rpc_detonate_pirate_barrel.rpc()
	else:
		_player.skill3_cooldown = BARREL_PLACE_COOLDOWN
		var pos: Vector2 = _player.global_position
		spawn_barrel_local(pos, false)
		if networked:
			_player.net_sync.rpc_place_pirate_barrel.rpc(pos)

func spawn_barrel_local(pos: Vector2, visual_only: bool) -> void:
	var b := BARREL_SCENE.instantiate()
	b.player_ref = _player
	b.visual_only = visual_only
	b.skill_level = _player.skill3_level
	_player.get_parent().add_child(b)
	b.global_position = pos
	if not visual_only:
		_barrel_node = b
	else:
		if is_instance_valid(_visual_barrel):
			_visual_barrel.queue_free()
		_visual_barrel = b

func detonate_visual_barrel() -> void:
	if is_instance_valid(_visual_barrel):
		_visual_barrel.detonate()
		_visual_barrel = null

func on_skill3_client_predict() -> void:
	if is_instance_valid(_visual_barrel):
		detonate_visual_barrel()
	else:
		spawn_barrel_local(_player.global_position, true)
		_player.skill3_cooldown = BARREL_PLACE_COOLDOWN

func place_visual_turret(pos: Vector2, fac: Vector2) -> void:
	if _visual_turret and is_instance_valid(_visual_turret):
		_visual_turret.global_position = pos
		_visual_turret.facing = fac
	else:
		_visual_turret = TURRET_SCENE.instantiate()
		_visual_turret.facing = fac
		_visual_turret.visual_only = true
		_visual_turret.player_ref = _player
		_player.get_parent().add_child(_visual_turret)
		_visual_turret.global_position = pos

func spawn_visual_cannonball(pos: Vector2, dir: Vector2, homing: bool) -> void:
	var ball := CANNONBALL_SCENE.instantiate()
	ball.direction = dir
	ball.homing = homing
	ball.visual_only = true
	ball.player_ref = _player
	_player.get_parent().add_child(ball)
	ball.global_position = pos
