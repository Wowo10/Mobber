class_name ArchetypeBase
extends RefCounted

var _player: Node

func setup(player: Node) -> void:
	_player = player
	var sword = player.get_node("Sword")
	sword.base_damage = get_sword_damage()
	sword.base_length = get_sword_length()
	sword.base_width = get_sword_width()
	sword.base_swing_duration = get_sword_swing_duration()
	sword.swing_duration = sword.base_swing_duration
	var col_shape := sword.get_node("CollisionShape2D").shape as RectangleShape2D
	col_shape.size = Vector2(sword.base_length, sword.base_width)
	sword.get_node("CollisionShape2D").position.x = Constants.PLAYER_START_RADIUS + sword.base_length * 0.5

func get_color() -> Color:
	return Color.WHITE

func get_skill1_color() -> Color:
	return Color.WHITE

func get_skill1_icon() -> Texture2D:
	return null

func get_skill2_color() -> Color:
	return Color.WHITE

func get_skill2_icon() -> Texture2D:
	return null

func get_sword_damage() -> float:
	return Constants.SWORD_DAMAGE

func get_sword_length() -> float:
	return Constants.SWORD_LENGTH

func get_sword_width() -> float:
	return Constants.SWORD_WIDTH

func get_sword_swing_duration() -> float:
	return Constants.SWORD_SWING_DURATION

func get_skill1_max_cooldown() -> float:
	return 1.0

func get_skill2_max_cooldown() -> float:
	return 1.0

func can_attack() -> bool:
	return not _player.get_node("Sword").swinging and not _player.spinning

func use_attack() -> void:
	var sword = _player.get_node("Sword")
	sword.swing(_player.last_facing.angle())
	_player.attack_cooldown = sword.swing_duration

func use_attack_visual() -> void:
	var sword = _player.get_node("Sword")
	sword.swing(_player.last_facing.angle())
	_player.attack_cooldown = sword.swing_duration

func broadcast_attack() -> void:
	_player.broadcast_swing(_player.last_facing.angle())

func on_skill1_client_predict() -> void:
	pass

func use_skill1() -> void:
	pass

func use_skill2() -> void:
	pass

func physics_process(_delta: float) -> void:
	pass
