class_name ArchetypeBerserker
extends ArchetypeBase

const GROUND_SLAM_SCENE = preload("res://scenes/archetypes/berserker/ground_slam.tscn")

const RAGE_COOLDOWN = 10.0
const RAGE_DURATION = 3.0
const SLAM_COOLDOWN = 8.0

var _rage_active := false
var _rage_timer := 0.0

func get_color() -> Color:
	return Color(0.85, 0.2, 0.1)

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
	return RAGE_COOLDOWN

func get_skill2_max_cooldown() -> float:
	return SLAM_COOLDOWN

func get_speed_mult() -> float:
	return 1.3 if _rage_active else 1.0

func get_dash_duration() -> float:
	return 0.06

func on_dash_end() -> void:
	spawn_slam_local(_player.global_position, false)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_spawn_ground_slam.rpc(_player.global_position)

func on_skill1_client_predict() -> void:
	set_rage(true)
	_rage_timer = RAGE_DURATION

func use_skill1() -> void:
	_player.skill1_cooldown = RAGE_COOLDOWN
	set_rage(true)
	_rage_timer = RAGE_DURATION
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_set_berserker_rage.rpc(true)

func use_skill2() -> void:
	_player.skill2_cooldown = SLAM_COOLDOWN
	spawn_slam_local(_player.global_position, false)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_spawn_ground_slam.rpc(_player.global_position)

func spawn_slam_local(pos: Vector2, visual_only: bool) -> void:
	var slam := GROUND_SLAM_SCENE.instantiate()
	slam.player_ref = _player
	slam.visual_only = visual_only
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
