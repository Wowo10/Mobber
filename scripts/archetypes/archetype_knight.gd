class_name ArchetypeKnight
extends ArchetypeBase

const CONSECRATION_SCENE = preload("res://scenes/entities/consecration.tscn")

func get_color() -> Color:
	return Color(0.6, 0.65, 0.85)

func get_skill1_max_cooldown() -> float:
	return Constants.SKILL_SPIN_COOLDOWN

func get_skill2_max_cooldown() -> float:
	return Constants.SKILL_CONSECRATION_COOLDOWN

func use_skill1() -> void:
	_player.skill1_cooldown = Constants.SKILL_SPIN_COOLDOWN
	_player.spinning = true
	_player.spin_timer = Constants.SKILL_SPIN_DURATION
	_player.get_node("Sword").enter_spin()
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_trigger_spin_start.rpc()

func use_skill2() -> void:
	_player.skill2_cooldown = Constants.SKILL_CONSECRATION_COOLDOWN
	spawn_consecration_local(_player.global_position, false)
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_spawn_consecration.rpc(_player.global_position)

func spawn_consecration_local(pos: Vector2, visual_only: bool) -> void:
	var c := CONSECRATION_SCENE.instantiate()
	c.player_ref = _player
	c.visual_only = visual_only
	_player.get_parent().add_child(c)
	c.global_position = pos
