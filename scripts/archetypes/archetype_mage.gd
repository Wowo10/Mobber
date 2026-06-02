class_name ArchetypeMage
extends ArchetypeBase

const BOLT_SCENE = preload("res://scenes/archetypes/mage/magic_bolt.tscn")
const RAIN_SCENE = preload("res://scenes/archetypes/mage/rain_of_fire.tscn")
const FIREBALL_SCENE = preload("res://scenes/archetypes/mage/fireball.tscn")

const BOLT_COOLDOWN = 0.6
const RAIN_COOLDOWN = 12.0
const FIREBALL_COOLDOWN = 8.0

func get_color() -> Color:
	return Color(0.55, 0.15, 0.9)

func get_skill1_color() -> Color:
	return Color(0.9, 0.2, 0.4)

func get_skill1_icon() -> Texture2D:
	return load("res://assets/icons/burning-meteor.png")

func get_skill2_color() -> Color:
	return Color(1.0, 0.45, 0.1)

func get_skill2_icon() -> Texture2D:
	return load("res://assets/icons/fireball.png")

func get_skill1_max_cooldown() -> float:
	return RAIN_COOLDOWN

func get_skill2_max_cooldown() -> float:
	return FIREBALL_COOLDOWN

func can_attack() -> bool:
	return _player.attack_cooldown <= 0.0

func use_attack() -> void:
	_player.attack_cooldown = BOLT_COOLDOWN
	var pos: Vector2 = _player.global_position + _player.last_facing * (_player.radius + 10.0)
	spawn_bolt_local(pos, _player.last_facing, false)

func broadcast_attack() -> void:
	_player.rpc_spawn_mage_bolt.rpc(
		_player.global_position + _player.last_facing * (_player.radius + 10.0),
		_player.last_facing)

func use_attack_visual() -> void:
	_player.attack_cooldown = BOLT_COOLDOWN
	var pos: Vector2 = _player.global_position + _player.last_facing * (_player.radius + 10.0)
	spawn_bolt_local(pos, _player.last_facing, true)

func use_skill1() -> void:
	_player.skill1_cooldown = RAIN_COOLDOWN
	spawn_rain_local(_player.global_position, false)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_spawn_rain.rpc(_player.global_position)

func use_skill2() -> void:
	_player.skill2_cooldown = FIREBALL_COOLDOWN
	var pos: Vector2 = _player.global_position + _player.last_facing * (_player.radius + 15.0)
	spawn_fireball_local(pos, _player.last_facing, false)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_spawn_fireball.rpc(pos, _player.last_facing)

func spawn_bolt_local(pos: Vector2, dir: Vector2, visual_only: bool) -> void:
	var bolt := BOLT_SCENE.instantiate()
	bolt.direction = dir
	bolt.player_ref = _player
	bolt.visual_only = visual_only
	_player.get_parent().add_child(bolt)
	bolt.global_position = pos

func spawn_rain_local(pos: Vector2, visual_only: bool) -> void:
	var rain := RAIN_SCENE.instantiate()
	rain.player_ref = _player
	rain.visual_only = visual_only
	_player.get_parent().add_child(rain)
	rain.global_position = pos

func spawn_fireball_local(pos: Vector2, dir: Vector2, visual_only: bool) -> void:
	var fb := FIREBALL_SCENE.instantiate()
	fb.direction = dir
	fb.player_ref = _player
	fb.visual_only = visual_only
	_player.get_parent().add_child(fb)
	fb.global_position = pos
