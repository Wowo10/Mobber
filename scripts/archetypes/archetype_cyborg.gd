class_name ArchetypeCyborg
extends ArchetypeBase

const BULLET_SCENE = preload("res://scenes/archetypes/cyborg/cyber_bullet.tscn")
const RAY_SCENE = preload("res://scenes/archetypes/cyborg/cyber_ray.tscn")

const BULLET_COOLDOWN = 0.45
const TARGETING_COOLDOWN = 9.0
const RAY_COOLDOWN = 10.0
const OVERCLOCK_COOLDOWN = 12.0
const OVERCLOCK_DURATION = 5.0

var _ranged_mode := false
var _overclock_active := false
var _overclock_timer := 0.0
var _extra_sword: Node = null

func get_color() -> Color:
	return Color(0.05, 0.65, 0.8)

func get_skill1_color() -> Color:
	return Color(0.1, 0.85, 1.0)

func get_skill1_icon() -> Texture2D:
	return load("res://assets/icons/crosshair.png")

func get_skill2_color() -> Color:
	return Color(0.0, 0.5, 0.8)

func get_skill2_icon() -> Texture2D:
	return load("res://assets/icons/laser-burst.png")

func get_skill3_color() -> Color:
	return Color(0.0, 0.8, 0.55)

func get_skill3_icon() -> Texture2D:
	return load("res://assets/icons/cogsplosion.png")

func get_skill1_max_cooldown() -> float:
	return TARGETING_COOLDOWN

func get_skill2_max_cooldown() -> float:
	return RAY_COOLDOWN

func get_skill3_max_cooldown() -> float:
	return OVERCLOCK_COOLDOWN

func get_speed_mult() -> float:
	return 1.35 if _overclock_active else 1.0

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
		_player.rpc_spawn_cyber_bullet.rpc(
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

func use_skill3() -> void:
	_player.skill3_cooldown = OVERCLOCK_COOLDOWN
	set_overclock(true)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_set_cyborg_overclock.rpc(true)

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
		_overclock_timer = OVERCLOCK_DURATION
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
			_player.rpc_set_cyborg_overclock.rpc(false)
