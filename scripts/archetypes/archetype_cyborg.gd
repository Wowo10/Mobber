class_name ArchetypeCyborg
extends ArchetypeBase

const BULLET_SCENE = preload("res://scenes/archetypes/cyborg/cyber_bullet.tscn")
const RAY_SCENE = preload("res://scenes/archetypes/cyborg/cyber_ray.tscn")

const _MELEE_ATTACK_ICON = preload("res://assets/icons/energy-sword.png")
const _RANGED_ATTACK_ICON = preload("res://assets/icons/cpu-shot.png")

const DATA = preload("res://data/archetypes/cyborg.tres")
const BULLET_COOLDOWN = 0.45
const OVERCLOCK_DURATION = 5.0

var _ranged_mode := false
var _overclock_active := false
var _overclock_timer := 0.0
var _extra_sword: Node = null

func get_attack_icon() -> Texture2D:
	return _RANGED_ATTACK_ICON if _ranged_mode else _MELEE_ATTACK_ICON

func get_attack_color() -> Color:
	return Color(0.1, 0.85, 1.0) if _ranged_mode else Color(0.3, 0.9, 0.6)

func get_data_resource() -> ArchetypeData:
	return DATA

func get_speed_mult() -> float:
	return 1.08 if _overclock_active else 0.8

func can_attack() -> bool:
	if _ranged_mode:
		return _player.attack_cooldown <= 0.0
	return not _player.get_node("Sword").swinging and not _player.spinning

func use_attack() -> void:
	if _ranged_mode:
		var cd := BULLET_COOLDOWN * (0.5 if _overclock_active else 1.0)
		_player.attack_cooldown = cd
		var pos: Vector2 = _player.global_position + _player.last_facing * (_player.radius + 10.0)
		spawn_bullet_local(pos, _player.last_facing, false)
	else:
		if _overclock_active:
			var sword = _player.get_node("Sword")
			sword.swing_duration = maxf(0.08, sword.base_swing_duration * 0.5)
			super.use_attack()
			if is_instance_valid(_extra_sword):
				_extra_sword.swing(_player.last_facing.angle() + deg_to_rad(50.0))
		else:
			super.use_attack()

func broadcast_attack() -> void:
	if _ranged_mode:
		_player.net_sync.rpc_spawn_cyber_bullet.rpc(
			_player.global_position + _player.last_facing * (_player.radius + 10.0),
			_player.last_facing)
	else:
		super.broadcast_attack()

func use_attack_visual() -> void:
	if _ranged_mode:
		var cd := BULLET_COOLDOWN * (0.5 if _overclock_active else 1.0)
		_player.attack_cooldown = cd
		var pos: Vector2 = _player.global_position + _player.last_facing * (_player.radius + 10.0)
		spawn_bullet_local(pos, _player.last_facing, true)
	else:
		super.use_attack_visual()

func use_skill1() -> void:
	_player.skill1_cooldown = get_skill1_max_cooldown()
	set_ranged_mode(not _ranged_mode)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.net_sync.rpc_set_cyborg_ranged_mode.rpc(_ranged_mode)

func use_skill2() -> void:
	_player.skill2_cooldown = get_skill2_max_cooldown()
	_player.shake_camera(0.25, 6.0)
	spawn_ray_local(_player.global_position, _player.last_facing, false)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.net_sync.rpc_spawn_cyber_ray.rpc(_player.global_position, _player.last_facing)

func use_skill3() -> void:
	_player.skill3_cooldown = get_skill3_max_cooldown()
	set_overclock(true)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.net_sync.rpc_set_cyborg_overclock.rpc(true)

func on_skill3_client_predict() -> void:
	set_overclock(true)

func on_skill1_client_predict() -> void:
	set_ranged_mode(not _ranged_mode)

func set_ranged_mode(active: bool) -> void:
	_ranged_mode = active
	_update_color()
	_player.queue_redraw()

func set_overclock(active: bool) -> void:
	_overclock_active = active
	if active:
		_overclock_timer = OVERCLOCK_DURATION + _player.skill3_level * 1.0
		_add_extra_sword()
	else:
		_remove_extra_sword()
		var sword = _player.get_node("Sword")
		sword.swing_duration = sword.base_swing_duration
	_update_color()
	_player.queue_redraw()

func _update_color() -> void:
	if _overclock_active and _ranged_mode:
		_player.color = Color(0.0, 1.0, 0.75)
	elif _overclock_active:
		_player.color = Color(0.05, 0.95, 0.65)
	elif _ranged_mode:
		_player.color = Color(0.2, 0.95, 1.0)
	else:
		_player.color = get_color()

func _add_extra_sword() -> void:
	if is_instance_valid(_extra_sword):
		return
	var existing_sword = _player.get_node("Sword")
	_extra_sword = existing_sword.duplicate()
	_extra_sword.name = "ExtraSword"
	_player.add_child(_extra_sword)
	_extra_sword.on_hit_callback = Callable()

func _remove_extra_sword() -> void:
	if is_instance_valid(_extra_sword):
		_extra_sword.queue_free()
		_extra_sword = null

func spawn_bullet_local(pos: Vector2, dir: Vector2, visual_only: bool) -> void:
	var bullet := BULLET_SCENE.instantiate()
	bullet.direction = dir
	bullet.player_ref = _player
	bullet.visual_only = visual_only
	bullet.mega_mode = _overclock_active
	_player.get_parent().add_child(bullet)
	bullet.global_position = pos

func spawn_ray_local(pos: Vector2, facing: Vector2, visual_only: bool) -> void:
	var ray := RAY_SCENE.instantiate()
	ray.player_ref = _player
	ray.visual_only = visual_only
	ray.facing = facing
	ray.thick = _overclock_active
	ray.skill_level = _player.skill2_level
	_player.get_parent().add_child(ray)
	ray.global_position = pos

func physics_process(delta: float) -> void:
	if not _overclock_active:
		return
	_overclock_timer -= delta
	if _overclock_timer <= 0.0:
		set_overclock(false)
		var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
		if networked and _player.multiplayer.is_server():
			_player.net_sync.rpc_set_cyborg_overclock.rpc(false)
