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

const PULL_RADIUS = 350.0
const PULL_FORCE = 1500.0

func get_dash_icon() -> Texture2D:
	return load("res://assets/icons/pull.png")

func get_dash_color() -> Color:
	return Color(0.55, 0.15, 0.9)

func use_dash() -> bool:
	_player.dash_cooldown = Constants.PLAYER_DASH_COOLDOWN
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if not networked or _player.multiplayer.is_server():
		var query := PhysicsShapeQueryParameters2D.new()
		var circle := CircleShape2D.new()
		circle.radius = PULL_RADIUS
		query.shape = circle
		query.transform = Transform2D(0.0, _player.global_position)
		query.collision_mask = 1
		for hit in _player.get_world_2d().direct_space_state.intersect_shape(query, 32):
			var body = hit["collider"]
			if body.has_method("apply_burst"):
				var dir: Vector2 = (_player.global_position - body.global_position).normalized()
				body.apply_burst(dir * PULL_FORCE)
		spawn_pull_visual(_player.global_position)
		if networked:
			_player.rpc_mage_force_pull.rpc(_player.global_position)
	else:
		spawn_pull_visual(_player.global_position)
	return true

func spawn_pull_visual(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.global_position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 48
	p.lifetime = 0.5
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 100.0
	p.initial_velocity_max = 380.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 9.0
	p.color = Color(0.75, 0.2, 1.0, 0.9)
	p.emitting = true
	_player.get_parent().add_child(p)
	_player.get_tree().create_timer(p.lifetime + 0.1).timeout.connect(p.queue_free)

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
