class_name ArchetypePaladin
extends ArchetypeBase

const DATA = preload("res://data/archetypes/paladin.tres")
const CONSECRATION_SCENE = preload("res://scenes/archetypes/knight/consecration.tscn")

# Behavior constants (tuning/visuals live in DATA). SPIN_DURATION/SPIN_SPEED are
# also read by player.gd and player_net_sync.gd for the spin animation.
const SPIN_DURATION = 2.5
const SPIN_SPEED = TAU * 3.0
const BASH_RANGE = 130.0
const BASH_HALF_WIDTH = 55.0
const BASH_DAMAGE = 6.0
const BASH_KNOCKBACK = 4500.0
const BASH_SLOW_MULT = 0.35
const BASH_SLOW_DURATION = 3.0

func get_data_resource() -> ArchetypeData:
	return DATA

func use_skill1() -> void:
	_player.skill1_cooldown = get_skill1_max_cooldown()
	_player.spinning = true
	_player.spin_timer = SPIN_DURATION + _player.skill1_level * 0.5
	_player.get_node("Sword").enter_spin()
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.net_sync.rpc_trigger_spin_start.rpc()

func use_skill2() -> void:
	_player.skill2_cooldown = get_skill2_max_cooldown()
	spawn_consecration_local(_player.global_position, false)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.net_sync.rpc_spawn_consecration.rpc(_player.global_position)

func use_skill3() -> void:
	_player.skill3_cooldown = get_skill3_max_cooldown()
	_player.shake_camera(0.3, 8.0)
	var pos: Vector2 = _player.global_position
	var dir: Vector2 = _player.last_facing
	_do_bash(pos, dir)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.net_sync.rpc_knight_shield_bash.rpc(pos, dir)

func _do_bash(pos: Vector2, dir: Vector2) -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(BASH_RANGE, BASH_HALF_WIDTH * 2.0)
	query.shape = box
	query.transform = Transform2D(dir.angle(), pos + dir * (_player.radius + BASH_RANGE * 0.5))
	query.collision_mask = 1 | Constants.MOB_COLLISION_LAYER
	for hit in _player.get_world_2d().direct_space_state.intersect_shape(query, 16):
		var body = hit["collider"]
		if body.has_method("take_damage"):
			body.take_damage(BASH_DAMAGE + _player.skill3_level * 3.0, dir * BASH_KNOCKBACK * (1.0 + 0.3 * _player.skill3_level), _player)
			if body.has_method("apply_slow"):
				body.apply_slow(BASH_SLOW_MULT, BASH_SLOW_DURATION)
	spawn_bash_visual(pos, dir)

func spawn_bash_visual(pos: Vector2, dir: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.global_position = pos + dir * _player.radius
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 16
	p.lifetime = 0.3
	p.direction = Vector2(dir.x, dir.y)
	p.spread = 40.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 200.0
	p.initial_velocity_max = 520.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 4.5
	p.color = Color(0.88, 0.93, 1.0, 0.95)
	ParticleUtils.polish(p)
	p.emitting = true
	_player.get_parent().add_child(p)
	_player.get_tree().create_timer(p.lifetime + 0.1).timeout.connect(p.queue_free)

func on_skill3_client_predict() -> void:
	spawn_bash_visual(_player.global_position, _player.last_facing)

func spawn_consecration_local(pos: Vector2, visual_only: bool) -> void:
	var c := CONSECRATION_SCENE.instantiate()
	c.player_ref = _player
	c.visual_only = visual_only
	c.skill_level = _player.skill2_level
	_player.get_parent().add_child(c)
	c.global_position = pos
