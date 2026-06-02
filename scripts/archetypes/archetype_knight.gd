class_name ArchetypeKnight
extends ArchetypeBase

const CONSECRATION_SCENE = preload("res://scenes/archetypes/knight/consecration.tscn")

const SPIN_COOLDOWN = 7.0
const SPIN_DURATION = 2.5
const SPIN_SPEED = TAU * 3.0
const CONSECRATION_COOLDOWN = 8.0

func get_color() -> Color:
	return Color(0.6, 0.65, 0.85)

func get_skill1_color() -> Color:
	return Color(0.75, 0.75, 0.9)

func get_skill1_icon() -> Texture2D:
	return load("res://assets/icons/spinning-sword.png")

func get_skill2_color() -> Color:
	return Color(1.0, 0.85, 0.2)

func get_skill2_icon() -> Texture2D:
	return load("res://assets/icons/holy-symbol.png")

func get_skill1_max_cooldown() -> float:
	return SPIN_COOLDOWN

func get_skill2_max_cooldown() -> float:
	return CONSECRATION_COOLDOWN

func use_skill1() -> void:
	_player.skill1_cooldown = SPIN_COOLDOWN
	_player.spinning = true
	_player.spin_timer = SPIN_DURATION
	_player.get_node("Sword").enter_spin()
	var networked := not (_player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		_player.rpc_trigger_spin_start.rpc()

func use_skill2() -> void:
	_player.skill2_cooldown = CONSECRATION_COOLDOWN
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
