class_name ArchetypePirate
extends ArchetypeBase

const CANNONBALL_SCENE = preload("res://scenes/archetypes/pirate/cannonball.tscn")
const TURRET_SCENE = preload("res://scenes/archetypes/pirate/turret_cannon.tscn")
const BARREL_SCENE = preload("res://scenes/archetypes/pirate/barrel.tscn")

const CANNON_COOLDOWN = 3.5
const TURRET_COOLDOWN = 4.0
const BARREL_COOLDOWN = 12.0
const BARREL_PLACE_COOLDOWN = 0.5

var _turret: Node2D = null
var _visual_turret: Node2D = null
var _barrel_node: Node2D = null
var _visual_barrel: Node2D = null

func get_color() -> Color:
	return Color(0.8, 0.35, 0.1)

func get_skill1_color() -> Color:
	return Color(0.95, 0.7, 0.1)

func get_skill1_icon() -> Texture2D:
	return load("res://assets/icons/cannon-ball.png")

func get_skill2_color() -> Color:
	return Color(0.45, 0.3, 0.15)

func get_skill2_icon() -> Texture2D:
	return load("res://assets/icons/laser-turret.png")

func get_skill3_color() -> Color:
	return Color(0.75, 0.45, 0.1)

func get_skill3_icon() -> Texture2D:
	return load("res://assets/icons/barrel.png")

func get_skill1_name() -> String:
	return "Cannonball"

func get_skill2_name() -> String:
	return "Turret"

func get_skill3_name() -> String:
	return "Barrel"

func get_attack_description() -> String:
	return "Sword swing."

func get_dash_description() -> String:
	return "Standard dash."

func get_skill1_description() -> String:
	return "Fires a heavy cannonball that bounces off enemies.\nCooldown: 3.5s"

func get_skill2_description() -> String:
	return "Places a cannon turret that fires automatically.\nCooldown: 4s"

func get_skill3_description() -> String:
	return "First press: place a barrel (CD: 0.5s). Second press: detonate it (CD: 12s)."

func get_skill3_max_cooldown() -> float:
	return BARREL_COOLDOWN * (1.0 - Constants.SHOP_SKILL_CD_REDUCTION_PER_LEVEL * _player.skill3_level)

func get_skill1_max_cooldown() -> float:
	return CANNON_COOLDOWN * (1.0 - Constants.SHOP_SKILL_CD_REDUCTION_PER_LEVEL * _player.skill1_level)

func get_skill2_max_cooldown() -> float:
	return TURRET_COOLDOWN * (1.0 - Constants.SHOP_SKILL_CD_REDUCTION_PER_LEVEL * _player.skill2_level)

func use_skill1() -> void:
	_player.skill1_cooldown = get_skill1_max_cooldown()
	var cannonball = CANNONBALL_SCENE.instantiate()
	cannonball.direction = _player.last_facing
	cannonball.global_position = _player.global_position + _player.last_facing * (_player.radius + 12.0)
	cannonball.player_ref = _player
	_player.get_parent().add_child(cannonball)
	_player.broadcast_cannonball(cannonball.global_position, _player.last_facing, true)

func use_skill2() -> void:
	_player.skill2_cooldown = get_skill2_max_cooldown()
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

func use_skill3() -> void:
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if is_instance_valid(_barrel_node):
		_barrel_node.detonate()
		_barrel_node = null
		_player.skill3_cooldown = get_skill3_max_cooldown()
		if networked:
			_player.rpc_detonate_pirate_barrel.rpc()
	else:
		_player.skill3_cooldown = BARREL_PLACE_COOLDOWN
		var pos: Vector2 = _player.global_position
		spawn_barrel_local(pos, false)
		if networked:
			_player.rpc_place_pirate_barrel.rpc(pos)

func spawn_barrel_local(pos: Vector2, visual_only: bool) -> void:
	var b := BARREL_SCENE.instantiate()
	b.player_ref = _player
	b.visual_only = visual_only
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
