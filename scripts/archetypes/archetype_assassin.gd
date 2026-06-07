class_name ArchetypeAssassin
extends ArchetypeBase

const FAN_KNIFE_SCENE = preload("res://scenes/archetypes/assassin/fan_knife.tscn")
const TRAP_SCENE = preload("res://scenes/archetypes/assassin/trap.tscn")

const FAN_COOLDOWN = 7.0
const FAN_COUNT = 5
const FAN_SPREAD_DEG = 60.0  # total cone width

const DASH_CONE_HALF_DEG = 50.0
const DASH_TARGET_RANGE = 450.0

const SHADOWSTEP_COOLDOWN = 10.0
const SHADOWSTEP_DAMAGE = 35.0
const SHADOWSTEP_RANGE = 350.0
const TRAP_COOLDOWN = 1.0
const MAX_TRAPS = 15

var _trap_count := 0

func get_color() -> Color:
	return Color(0.45, 0.1, 0.6)

func get_skill3_color() -> Color:
	return Color(0.45, 0.1, 0.65)

func get_skill3_icon() -> Texture2D:
	return load("res://assets/icons/box-trap.png")

func get_skill1_name() -> String:
	return "Fan of Knives"

func get_skill2_name() -> String:
	return "Shadowstep"

func get_skill3_name() -> String:
	return "Trap"

func get_attack_description() -> String:
	return "Fast melee strike. Low damage."

func get_dash_description() -> String:
	return "Blinks toward the nearest mob in your front cone."

func get_skill1_description() -> String:
	return "Throws 5 knives in a 60-degree cone.\nCooldown: 7s"

func get_skill2_description() -> String:
	return "Teleports behind the nearest mob and deals damage.\nCooldown: 10s"

func get_skill3_description() -> String:
	return "Places a hidden trap at your feet. Max 15 active traps.\nCooldown: 1s"

func get_skill3_max_cooldown() -> float:
	return TRAP_COOLDOWN * (1.0 - Constants.SHOP_SKILL_CD_REDUCTION_PER_LEVEL * _player.skill3_level)

func get_skill1_color() -> Color:
	return Color(0.75, 0.85, 1.0)

func get_skill1_icon() -> Texture2D:
	return load("res://assets/icons/thrown-daggers.png")

func get_skill2_color() -> Color:
	return Color(0.3, 0.05, 0.45)

func get_skill2_icon() -> Texture2D:
	return load("res://assets/icons/shadow-grasp.png")

func get_sword_damage() -> float:
	return 7.0

func get_sword_swing_duration() -> float:
	return 0.15

func get_skill1_max_cooldown() -> float:
	return FAN_COOLDOWN * (1.0 - Constants.SHOP_SKILL_CD_REDUCTION_PER_LEVEL * _player.skill1_level)

func get_skill2_max_cooldown() -> float:
	return SHADOWSTEP_COOLDOWN * (1.0 - Constants.SHOP_SKILL_CD_REDUCTION_PER_LEVEL * _player.skill2_level)

func use_dash() -> bool:
	var target := _find_mob_in_cone(DASH_CONE_HALF_DEG, DASH_TARGET_RANGE)
	if target != null:
		_player.last_facing = _player.global_position.direction_to(target.global_position)
	return false  # let the default dash run with updated facing

func get_dash_duration() -> float:
	return 0.2

func on_skill1_client_predict() -> void:
	var base_angle: float = _player.last_facing.angle()
	spawn_fan_local(_player.global_position, base_angle, true)

func use_skill1() -> void:
	_player.skill1_cooldown = get_skill1_max_cooldown()
	var base_angle: float = _player.last_facing.angle()
	spawn_fan_local(_player.global_position, base_angle, false)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_spawn_fan_of_knives.rpc(_player.global_position, base_angle)

func on_skill2_client_predict() -> void:
	var nearest := _find_nearest_mob(SHADOWSTEP_RANGE)
	if nearest == null:
		return
	var to_mob: Vector2 = (nearest.global_position - _player.global_position).normalized()
	_player.position = nearest.global_position - to_mob * (nearest.radius + _player.radius + 5.0)
	_spawn_blink_burst(nearest.global_position)

func use_skill2() -> void:
	_player.skill2_cooldown = get_skill2_max_cooldown()
	var nearest := _find_nearest_mob(SHADOWSTEP_RANGE)
	if nearest == null:
		return
	var to_mob: Vector2 = (nearest.global_position - _player.global_position).normalized()
	_player.position = nearest.global_position - to_mob * (nearest.radius + _player.radius + 5.0)
	nearest.take_damage(SHADOWSTEP_DAMAGE + _player.skill2_level * 10.0, to_mob * 6000.0, _player)
	_spawn_blink_burst(nearest.global_position)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_shadowstep_visual.rpc(nearest.global_position)

func use_skill3() -> void:
	if _trap_count >= MAX_TRAPS:
		return
	_player.skill3_cooldown = get_skill3_max_cooldown()
	spawn_trap_local(_player.global_position, false)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_spawn_assassin_trap.rpc(_player.global_position)

func on_trap_triggered() -> void:
	_trap_count = max(0, _trap_count - 1)

func spawn_trap_local(pos: Vector2, visual_only: bool) -> void:
	if not visual_only:
		_trap_count += 1
	var trap := TRAP_SCENE.instantiate()
	trap.player_ref = _player
	trap.visual_only = visual_only
	_player.get_parent().add_child(trap)
	trap.global_position = pos

func spawn_fan_local(pos: Vector2, base_angle: float, visual_only: bool) -> void:
	for i in range(FAN_COUNT):
		var t := float(i) / float(FAN_COUNT - 1)
		var spread := deg_to_rad(lerp(-FAN_SPREAD_DEG * 0.5, FAN_SPREAD_DEG * 0.5, t))
		var dir := Vector2.from_angle(base_angle + spread)
		var knife := FAN_KNIFE_SCENE.instantiate()
		knife.direction = dir
		knife.player_ref = _player
		knife.visual_only = visual_only
		_player.get_parent().add_child(knife)
		knife.global_position = pos + dir * (_player.radius + 5.0)

func spawn_visual_at(pos: Vector2) -> void:
	_spawn_blink_burst(pos)

func _find_mob_in_cone(half_angle_deg: float, max_dist: float) -> Node2D:
	var half_rad := deg_to_rad(half_angle_deg)
	var facing: Vector2 = _player.last_facing
	var nearest: Node2D = null
	var nearest_dist := max_dist
	for mob in _player.get_tree().get_nodes_in_group("mobs"):
		var to_mob: Vector2 = mob.global_position - _player.global_position
		var dist := to_mob.length()
		if dist < 0.001 or dist > max_dist:
			continue
		if abs(facing.angle_to(to_mob / dist)) <= half_rad and dist < nearest_dist:
			nearest_dist = dist
			nearest = mob
	return nearest

func _find_nearest_mob(max_dist: float) -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := max_dist
	for mob in _player.get_tree().get_nodes_in_group("mobs"):
		var d: float = _player.global_position.distance_to(mob.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = mob
	return nearest

func _spawn_blink_burst(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.global_position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 18
	p.lifetime = 0.3
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 220.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	p.color = Color(0.75, 0.2, 1.0, 0.85)
	p.emitting = true
	_player.get_parent().add_child(p)
	_player.get_tree().create_timer(p.lifetime + 0.1).timeout.connect(p.queue_free)
