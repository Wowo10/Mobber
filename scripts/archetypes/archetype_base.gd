class_name ArchetypeBase
extends RefCounted

var _player: Node

func setup(player: Node) -> void:
	_player = player

func get_color() -> Color:
	return Color.WHITE

func get_skill1_max_cooldown() -> float:
	return 1.0

func get_skill2_max_cooldown() -> float:
	return 1.0

func use_skill1() -> void:
	pass

func use_skill2() -> void:
	pass

func physics_process(_delta: float) -> void:
	pass
