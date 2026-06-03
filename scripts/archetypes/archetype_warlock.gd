class_name ArchetypeWarlock
extends ArchetypeBase

const BOLT_SCENE = preload("res://scenes/archetypes/warlock/warlock_bolt.tscn")
const DRAIN_SCENE = preload("res://scenes/archetypes/warlock/drain_life.tscn")
const RIFT_SCENE = preload("res://scenes/archetypes/warlock/void_rift.tscn")
const PORTAL_SCENE = preload("res://scenes/archetypes/warlock/warlock_portal.tscn")

const BOLT_COOLDOWN = 0.7
const DRAIN_COOLDOWN = 8.0
const RIFT_COOLDOWN = 15.0

var _portal_active := false
var _portal_pos := Vector2.ZERO
var _portal_node: Node2D = null
var _visual_portal: Node2D = null

func get_color() -> Color:
	return Color(0.1, 0.2, 0.55)

func get_skill1_color() -> Color:
	return Color(0.15, 0.55, 0.8)

func get_skill1_icon() -> Texture2D:
	return load("res://assets/icons/marrow-drain.png")

func get_skill2_color() -> Color:
	return Color(0.05, 0.05, 0.4)

func get_skill2_icon() -> Texture2D:
	return load("res://assets/icons/vortex.png")

func get_dash_icon() -> Texture2D:
	return load("res://assets/icons/magic-portal.png")

func get_dash_color() -> Color:
	return Color(0.4, 0.1, 0.8)

func get_skill1_max_cooldown() -> float:
	return DRAIN_COOLDOWN

func get_skill2_max_cooldown() -> float:
	return RIFT_COOLDOWN

func use_dash() -> bool:
	_player.dash_cooldown = Constants.PLAYER_DASH_COOLDOWN
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if not networked or _player.multiplayer.is_server():
		if _portal_active and not is_instance_valid(_portal_node):
			_portal_active = false
		if not _portal_active:
			_portal_pos = _player.global_position
			_portal_active = true
			_portal_node = PORTAL_SCENE.instantiate()
			_player.get_parent().add_child(_portal_node)
			_portal_node.global_position = _portal_pos
			if networked:
				_player.rpc_place_warlock_portal.rpc(_portal_pos)
		else:
			var prev_pos: Vector2 = _player.global_position
			_player.position = _portal_pos
			if is_instance_valid(_portal_node):
				_portal_node.queue_free()
			_portal_pos = prev_pos
			_portal_node = PORTAL_SCENE.instantiate()
			_player.get_parent().add_child(_portal_node)
			_portal_node.global_position = _portal_pos
			if networked:
				_player.rpc_consume_warlock_portal.rpc()
				_player.rpc_place_warlock_portal.rpc(_portal_pos)
	return true

func place_visual_portal(pos: Vector2) -> void:
	if is_instance_valid(_visual_portal):
		_visual_portal.queue_free()
	_visual_portal = PORTAL_SCENE.instantiate()
	_player.get_parent().add_child(_visual_portal)
	_visual_portal.global_position = pos

func consume_visual_portal() -> void:
	if is_instance_valid(_visual_portal):
		_visual_portal.queue_free()
	_visual_portal = null

func can_attack() -> bool:
	return _player.attack_cooldown <= 0.0

func use_attack() -> void:
	_player.attack_cooldown = BOLT_COOLDOWN
	var pos: Vector2 = _player.global_position + _player.last_facing * (_player.radius + 10.0)
	spawn_bolt_local(pos, _player.last_facing, false)

func broadcast_attack() -> void:
	_player.rpc_spawn_warlock_bolt.rpc(
		_player.global_position + _player.last_facing * (_player.radius + 10.0),
		_player.last_facing)

func use_attack_visual() -> void:
	_player.attack_cooldown = BOLT_COOLDOWN
	var pos: Vector2 = _player.global_position + _player.last_facing * (_player.radius + 10.0)
	spawn_bolt_local(pos, _player.last_facing, true)

func use_skill1() -> void:
	_player.skill1_cooldown = DRAIN_COOLDOWN
	spawn_drain_local(false)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_spawn_drain_life.rpc()

func use_skill2() -> void:
	_player.skill2_cooldown = RIFT_COOLDOWN
	spawn_rift_local(_player.global_position, false)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_spawn_void_rift.rpc(_player.global_position)

func spawn_bolt_local(pos: Vector2, dir: Vector2, visual_only: bool) -> void:
	var bolt := BOLT_SCENE.instantiate()
	bolt.direction = dir
	bolt.player_ref = _player
	bolt.visual_only = visual_only
	_player.get_parent().add_child(bolt)
	bolt.global_position = pos

func spawn_drain_local(visual_only: bool) -> void:
	var drain := DRAIN_SCENE.instantiate()
	drain.player_ref = _player
	drain.visual_only = visual_only
	_player.get_parent().add_child(drain)
	drain.global_position = _player.global_position

func spawn_rift_local(pos: Vector2, visual_only: bool) -> void:
	var rift := RIFT_SCENE.instantiate()
	rift.player_ref = _player
	rift.visual_only = visual_only
	_player.get_parent().add_child(rift)
	rift.global_position = pos
