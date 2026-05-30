class_name ArchetypePirate
extends ArchetypeBase

const CANNONBALL_SCENE = preload("res://scenes/entities/cannonball.tscn")
const TURRET_SCENE = preload("res://scenes/entities/turret_cannon.tscn")

var _turret: Node2D = null
var _visual_turret: Node2D = null

func get_color() -> Color:
	return Color(0.8, 0.35, 0.1)

func get_skill1_max_cooldown() -> float:
	return Constants.SKILL_CANNON_COOLDOWN

func get_skill2_max_cooldown() -> float:
	return Constants.SKILL_TURRET_COOLDOWN

func use_skill1() -> void:
	_player.skill1_cooldown = Constants.SKILL_CANNON_COOLDOWN
	var cannonball = CANNONBALL_SCENE.instantiate()
	cannonball.direction = _player.last_facing
	cannonball.global_position = _player.global_position + _player.last_facing * (_player.radius + 12.0)
	cannonball.player_ref = _player
	_player.get_parent().add_child(cannonball)
	_player.broadcast_cannonball(cannonball.global_position, _player.last_facing, true)

func use_skill2() -> void:
	_player.skill2_cooldown = Constants.SKILL_TURRET_COOLDOWN
	if _turret and is_instance_valid(_turret):
		_turret.global_position = _player.global_position
		_turret.facing = _player.last_facing
		_turret.reset_fire_timer()
	else:
		_turret = TURRET_SCENE.instantiate()
		_turret.facing = _player.last_facing
		_turret.player_ref = _player
		_player.get_parent().add_child(_turret)
		_turret.global_position = _player.global_position
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_place_turret.rpc(_player.global_position, _player.last_facing)

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
