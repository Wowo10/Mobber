class_name ArchetypeBerserker
extends ArchetypeBase

const GROUND_SLAM_SCENE = preload("res://scenes/archetypes/berserker/ground_slam.tscn")

const RAGE_COOLDOWN = 10.0
const RAGE_DURATION = 3.0
const SLAM_COOLDOWN = 8.0
const BASE_SLAM_RADIUS = 150.0
const BASE_SLAM_DAMAGE = 45.0

var _rage_active := false
var _rage_timer := 0.0
var _hit_count := 0

func setup(player: Node) -> void:
	super.setup(player)
	player.get_node("Sword").on_hit_callback = _on_sword_hit

func get_mini_smash_threshold() -> int:
	return max(1, 4 - _player.skill3_level)

func _on_sword_hit(mob: Node, _damage: float) -> void:
	_hit_count += 1
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_berserker_set_hit_count.rpc(_hit_count)
	if _hit_count % get_mini_smash_threshold() == 0:
		spawn_mini_smash_local(mob.global_position, false)
		if networked:
			_player.rpc_spawn_berserker_mini_smash.rpc(mob.global_position)

func get_hit_count() -> int:
	return _hit_count

func set_hit_count(count: int) -> void:
	_hit_count = count

func get_color() -> Color:
	return Color(0.85, 0.2, 0.1)

func get_skill3_color() -> Color:
	return Color(0.9, 0.4, 0.05)

func get_skill3_icon() -> Texture2D:
	return load("res://assets/icons/anvil-impact.png")

func get_skill1_name() -> String:
	return "Enrage"

func get_skill2_name() -> String:
	return "Ground Slam"

func get_skill3_name() -> String:
	return "Mini Smash"

func get_attack_description() -> String:
	return "Heavy sword swing. High damage."

func get_dash_description() -> String:
	return "Short dash that triggers a ground slam on landing."

func get_skill1_description() -> String:
	return "Boosts movement speed and attack speed for 3s.\nCooldown: 10s"

func get_skill2_description() -> String:
	return "Smashes the ground in a wide radius.\nCooldown: 8s"

func get_skill3_description() -> String:
	return "Passive — every 4th sword hit triggers a shockwave."

func get_skill3_max_cooldown() -> float:
	return 0.0

func get_skill1_color() -> Color:
	return Color(1.0, 0.3, 0.05)

func get_skill1_icon() -> Texture2D:
	return load("res://assets/icons/enrage.png")

func get_skill2_color() -> Color:
	return Color(0.6, 0.15, 0.05)

func get_skill2_icon() -> Texture2D:
	return load("res://assets/icons/crush.png")

func get_sword_damage() -> float:
	return 18.0

func get_sword_width() -> float:
	return 13.0

func get_sword_length() -> float:
	return 55.0

func get_sword_swing_duration() -> float:
	return 0.38

func get_skill1_max_cooldown() -> float:
	return RAGE_COOLDOWN * (1.0 - Constants.SHOP_SKILL_CD_REDUCTION_PER_LEVEL * _player.skill1_level)

func get_skill2_max_cooldown() -> float:
	return SLAM_COOLDOWN * (1.0 - Constants.SHOP_SKILL_CD_REDUCTION_PER_LEVEL * _player.skill2_level)

func get_speed_mult() -> float:
	return 1.3 if _rage_active else 1.0

func get_dash_duration() -> float:
	return 0.06

func on_dash_end() -> void:
	_player.shake_camera(0.4, 14.0)
	spawn_slam_local(_player.global_position, false, 20.0, 55.0)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_spawn_ground_slam.rpc(_player.global_position, 55.0)

func on_skill1_client_predict() -> void:
	set_rage(true)
	_rage_timer = RAGE_DURATION + _player.skill1_level * 0.5

func use_skill1() -> void:
	_player.skill1_cooldown = get_skill1_max_cooldown()
	set_rage(true)
	_rage_timer = RAGE_DURATION + _player.skill1_level * 0.5
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_set_berserker_rage.rpc(true)

func use_skill2() -> void:
	_player.skill2_cooldown = get_skill2_max_cooldown()
	_player.shake_camera(0.4, 14.0)
	var scale: float = 1.0 + 0.25 * _player.skill2_level
	var r: float = BASE_SLAM_RADIUS * scale
	var d: float = BASE_SLAM_DAMAGE * scale
	spawn_slam_local(_player.global_position, false, d, r)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_spawn_ground_slam.rpc(_player.global_position, r)

func spawn_mini_smash_local(pos: Vector2, visual_only: bool) -> void:
	if not visual_only:
		var query := PhysicsShapeQueryParameters2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 80.0
		query.shape = circle
		query.transform = Transform2D(0.0, pos)
		query.collision_mask = 1
		var sword = _player.get_node("Sword")
		var smash_damage: float = (sword.base_damage + sword.damage_bonus) * 2.0
		for hit in _player.get_world_2d().direct_space_state.intersect_shape(query, 8):
			var body = hit["collider"]
			if body.has_method("take_damage"):
				var dir: Vector2 = (body.global_position - pos).normalized()
				body.take_damage(smash_damage, dir * 6000.0, _player)
	_spawn_mini_smash_visual(pos)

func _spawn_mini_smash_visual(pos: Vector2) -> void:
	var v := Node2D.new()
	v.global_position = pos
	_player.get_parent().add_child(v)
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 20
	p.lifetime = 0.35
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 220.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 7.0
	p.color = Color(1.0, 0.5, 0.1, 1.0)
	ParticleUtils.polish(p)
	p.emitting = true
	v.add_child(p)
	_player.get_tree().create_timer(0.5).timeout.connect(v.queue_free)

func spawn_slam_local(pos: Vector2, visual_only: bool, damage := -1.0, radius := -1.0) -> void:
	var slam := GROUND_SLAM_SCENE.instantiate()
	slam.player_ref = _player
	slam.visual_only = visual_only
	slam.damage_override = damage
	slam.radius_override = radius
	_player.get_parent().add_child(slam)
	slam.global_position = pos

func set_rage(active: bool) -> void:
	_rage_active = active
	var sword = _player.get_node("Sword")
	if active:
		sword.swing_duration = maxf(0.08, sword.base_swing_duration * 0.5)
		_player.color = Color(1.0, 0.38, 0.12)
	else:
		sword.swing_duration = sword.base_swing_duration
		_player.color = get_color()
	_player.queue_redraw()

func physics_process(delta: float) -> void:
	if not _rage_active:
		return
	_rage_timer -= delta
	if _rage_timer <= 0.0:
		set_rage(false)
		var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
		if networked and _player.multiplayer.is_server():
			_player.rpc_set_berserker_rage.rpc(false)
