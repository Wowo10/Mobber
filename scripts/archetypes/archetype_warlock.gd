class_name ArchetypeWarlock
extends ArchetypeBase

const BOLT_SCENE = preload("res://scenes/archetypes/warlock/warlock_bolt.tscn")
const DRAIN_SCENE = preload("res://scenes/archetypes/warlock/drain_life.tscn")
const RIFT_SCENE = preload("res://scenes/archetypes/warlock/void_rift.tscn")
const PORTAL_SCENE = preload("res://scenes/archetypes/warlock/warlock_portal.tscn")
const WISP_SCENE = preload("res://scenes/archetypes/warlock/wisp.tscn")

const BOLT_COOLDOWN = 0.7
const DRAIN_COOLDOWN = 8.0
const RIFT_COOLDOWN = 15.0
const WISP_COOLDOWN = 22.0

var _portal_active := false
var _portal_pos := Vector2.ZERO
var _portal_node: Node2D = null
var _visual_portal: Node2D = null
var _wisp_node: Node2D = null

func get_attack_icon() -> Texture2D:
	return load("res://assets/icons/shadow-grasp.png")

func get_attack_color() -> Color:
	return Color(0.35, 0.05, 0.8)

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
	
func get_skill3_color() -> Color:
	return Color(0.2, 0.4, 0.9)

func get_skill3_icon() -> Texture2D:
	return load("res://assets/icons/ghost-ally.png")

func get_skill1_name() -> String:
	return "Drain Life"

func get_skill2_name() -> String:
	return "Void Rift"

func get_skill3_name() -> String:
	return "Wisp"

func get_attack_description() -> String:
	return "Fires a shadow bolt toward the cursor.\nCooldown: 0.7s"

func get_dash_description() -> String:
	return "First press: place a portal. Second press: teleport to it."

func get_skill1_description() -> String:
	return "Siphons health from nearby enemies.\nCooldown: 8s"

func get_skill2_description() -> String:
	return "Creates a void rift that pulls enemies into a vortex.\nCooldown: 15s"

func get_skill3_description() -> String:
	return "Summons a wisp familiar that attacks nearby enemies.\nCooldown: 22s"

func get_skill1_max_cooldown() -> float:
	return DRAIN_COOLDOWN * (1.0 - Constants.SHOP_SKILL_CD_REDUCTION_PER_LEVEL * _player.skill1_level)

func get_skill2_max_cooldown() -> float:
	return RIFT_COOLDOWN * (1.0 - Constants.SHOP_SKILL_CD_REDUCTION_PER_LEVEL * _player.skill2_level)

func get_skill3_max_cooldown() -> float:
	return WISP_COOLDOWN * (1.0 - Constants.SHOP_SKILL_CD_REDUCTION_PER_LEVEL * _player.skill3_level)

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
				_player.net_sync.rpc_place_warlock_portal.rpc(_portal_pos)
		else:
			var prev_pos: Vector2 = _player.global_position
			var jump_dir: Vector2 = ((_portal_pos - prev_pos).normalized() if _portal_pos != prev_pos else Vector2.RIGHT)
			_spawn_teleport_burst(prev_pos, jump_dir)
			_player.position = _portal_pos
			_spawn_teleport_burst(_player.global_position, -jump_dir)
			if is_instance_valid(_portal_node):
				_portal_node.queue_free()
			_portal_pos = prev_pos
			_portal_node = PORTAL_SCENE.instantiate()
			_player.get_parent().add_child(_portal_node)
			_portal_node.global_position = _portal_pos
			if networked:
				_player.net_sync.rpc_consume_warlock_portal.rpc()
				_player.net_sync.rpc_place_warlock_portal.rpc(_portal_pos)
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
	_player.net_sync.rpc_spawn_warlock_bolt.rpc(
		_player.global_position + _player.last_facing * (_player.radius + 10.0),
		_player.last_facing)

func use_attack_visual() -> void:
	_player.attack_cooldown = BOLT_COOLDOWN
	var pos: Vector2 = _player.global_position + _player.last_facing * (_player.radius + 10.0)
	spawn_bolt_local(pos, _player.last_facing, true)

func use_skill1() -> void:
	_player.skill1_cooldown = get_skill1_max_cooldown()
	spawn_drain_local(false)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.net_sync.rpc_spawn_drain_life.rpc()

func use_skill2() -> void:
	_player.skill2_cooldown = get_skill2_max_cooldown()
	_player.shake_camera(0.35, 10.0)
	spawn_rift_local(_player.global_position, false)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.net_sync.rpc_spawn_void_rift.rpc(_player.global_position)

func spawn_bolt_local(pos: Vector2, dir: Vector2, visual_only: bool) -> void:
	var bolt := BOLT_SCENE.instantiate()
	bolt.direction = dir
	bolt.player_ref = _player
	bolt.visual_only = visual_only
	_player.get_parent().add_child(bolt)
	bolt.global_position = pos

func spawn_wisp_bolt_visual(pos: Vector2, dir: Vector2) -> void:
	var bolt := BOLT_SCENE.instantiate()
	bolt.set("direction", dir)
	bolt.set("player_ref", _player)
	bolt.set("visual_only", true)
	bolt.set("color_outer", Color(0.1, 0.55, 0.85, 0.8))
	bolt.set("color_inner", Color(0.75, 0.97, 1.0))
	_player.get_parent().add_child(bolt)
	bolt.global_position = pos

func spawn_drain_local(visual_only: bool) -> void:
	var drain := DRAIN_SCENE.instantiate()
	drain.player_ref = _player
	drain.visual_only = visual_only
	drain.skill_level = _player.skill1_level
	_player.get_parent().add_child(drain)
	drain.global_position = _player.global_position

func use_skill3() -> void:
	if is_instance_valid(_wisp_node):
		return
	_player.skill3_cooldown = get_skill3_max_cooldown()
	spawn_wisp_local(false)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.net_sync.rpc_spawn_warlock_wisp.rpc()

func spawn_wisp_local(visual_only: bool) -> void:
	if not visual_only:
		if is_instance_valid(_wisp_node):
			_wisp_node.queue_free()
		_wisp_node = WISP_SCENE.instantiate()
		_wisp_node.player_ref = _player
		_wisp_node.visual_only = false
		_wisp_node.lifetime = get_skill3_max_cooldown() * 0.5 + 3.0 * _player.skill3_level
		_player.get_parent().add_child(_wisp_node)
		_wisp_node.global_position = _player.global_position
	else:
		var v := WISP_SCENE.instantiate()
		v.player_ref = _player
		v.visual_only = true
		v.lifetime = WISP_COOLDOWN * 0.5 + 3.0 * _player.skill3_level
		_player.get_parent().add_child(v)
		v.global_position = _player.global_position

func _spawn_teleport_burst(pos: Vector2, dir: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.global_position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 18
	p.lifetime = 0.35
	p.gravity = Vector2.ZERO
	p.direction = dir
	p.spread = 55.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 260.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	p.color = Color(0.35, 0.1, 0.9, 0.9)
	ParticleUtils.polish(p)
	p.emitting = true
	_player.get_parent().add_child(p)
	_player.get_tree().create_timer(p.lifetime + 0.1).timeout.connect(p.queue_free)

func spawn_rift_local(pos: Vector2, visual_only: bool) -> void:
	var rift := RIFT_SCENE.instantiate()
	rift.player_ref = _player
	rift.visual_only = visual_only
	rift.skill_level = _player.skill2_level
	_player.get_parent().add_child(rift)
	rift.global_position = pos
