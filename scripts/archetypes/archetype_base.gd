class_name ArchetypeBase
extends RefCounted

var _player: Node
var _data: ArchetypeData

# _data is resolved at construction (not in setup) so the data getters work even
# when an archetype is built only to query its icons/names — e.g. match_manager's
# _make_archetype for the skill bar, which never calls setup().
func _init() -> void:
	_data = get_data_resource()

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

# Override in concrete archetypes to return a preloaded ArchetypeData .tres.
# The base builds a default from Constants so the fallback archetype still works.
func get_data_resource() -> ArchetypeData:
	var d := ArchetypeData.new()
	d.sword_damage = Constants.SWORD_DAMAGE
	d.sword_length = Constants.SWORD_LENGTH
	d.sword_width = Constants.SWORD_WIDTH
	d.sword_swing_duration = Constants.SWORD_SWING_DURATION
	d.dash_duration = Constants.PLAYER_DASH_DURATION
	return d

func get_color() -> Color:
	return _data.color

func get_skill1_color() -> Color:
	return _data.skill1_color

func get_skill1_icon() -> Texture2D:
	return _data.skill1_icon

func get_skill2_color() -> Color:
	return _data.skill2_color

func get_skill2_icon() -> Texture2D:
	return _data.skill2_icon

func get_sword_damage() -> float:
	return _data.sword_damage

func get_sword_length() -> float:
	return _data.sword_length

func get_sword_width() -> float:
	return _data.sword_width

func get_sword_swing_duration() -> float:
	return _data.sword_swing_duration

func get_skill1_name() -> String:
	return _data.skill1_name

func get_skill2_name() -> String:
	return _data.skill2_name

func get_skill3_name() -> String:
	return _data.skill3_name

func get_attack_description() -> String:
	return _data.attack_description

func get_dash_description() -> String:
	return _data.dash_description

func get_skill1_description() -> String:
	return _data.skill1_description

func get_skill2_description() -> String:
	return _data.skill2_description

func get_skill3_description() -> String:
	return _data.skill3_description

# Uniform level-scaled cooldown: base * (1 - reduction * level). Archetypes set the
# base value in their .tres; the formula lives here.
func get_skill1_max_cooldown() -> float:
	return _data.skill1_cooldown * (1.0 - Constants.SHOP_SKILL_CD_REDUCTION_PER_LEVEL * _player.skill1_level)

func get_skill2_max_cooldown() -> float:
	return _data.skill2_cooldown * (1.0 - Constants.SHOP_SKILL_CD_REDUCTION_PER_LEVEL * _player.skill2_level)

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
	_player.net_sync.broadcast_swing(_player.last_facing.angle())

func get_speed_mult() -> float:
	return _data.speed_mult

func use_dash() -> bool:
	return false  # false = use default dash behavior

func get_dash_duration() -> float:
	return _data.dash_duration

func get_dash_icon() -> Texture2D:
	return _data.dash_icon

func get_attack_icon() -> Texture2D:
	return _data.attack_icon

func get_attack_color() -> Color:
	return _data.attack_color

func get_dash_color() -> Color:
	return _data.dash_color

func on_dash_end() -> void:
	pass

func on_skill1_client_predict() -> void:
	pass

func on_skill2_client_predict() -> void:
	pass

func get_skill3_color() -> Color:
	return _data.skill3_color

func get_skill3_icon() -> Texture2D:
	return _data.skill3_icon

func get_skill3_max_cooldown() -> float:
	return _data.skill3_cooldown * (1.0 - Constants.SHOP_SKILL_CD_REDUCTION_PER_LEVEL * _player.skill3_level)

func use_skill1() -> void:
	pass

func use_skill2() -> void:
	pass

func use_skill3() -> void:
	pass

func on_skill3_client_predict() -> void:
	pass

func physics_process(_delta: float) -> void:
	pass
