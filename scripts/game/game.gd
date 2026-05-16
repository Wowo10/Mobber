extends Node2D

const GRID_SIZE = 100
const MOB_SCENE = preload("res://scenes/entities/mob.tscn")

func _ready() -> void:
	_spawn_mobs()

func _process(_delta: float) -> void:
	pass

func _draw() -> void:
	for x in range(0, Constants.WORLD_SIZE_X + 1, GRID_SIZE):
		draw_line(
			Vector2(x, 0),
			Vector2(x, Constants.WORLD_SIZE_Y),
			Color(0.5, 0.5, 0.5, 0.40),
			1.0
		)
	for y in range(0, Constants.WORLD_SIZE_Y + 1, GRID_SIZE):
		draw_line(
			Vector2(0, y),
			Vector2(Constants.WORLD_SIZE_X, y),
			Color(0.5, 0.5, 0.5, 0.40),
			1.0
		)

	draw_rect(
		Rect2(0, 0, Constants.WORLD_SIZE_X, Constants.WORLD_SIZE_Y),
		Color(0.8, 0.2, 0.2, 0.8),
		false,
		8.0
	)

func _spawn_mobs() -> void:
	var container := $MobContainer
	var margin: float = Constants.MOB_RADIUS + 10.0
	for i in Constants.MOB_COUNT:
		var mob := MOB_SCENE.instantiate()
		mob.position = Vector2(
			randf_range(margin, Constants.WORLD_SIZE_X - margin),
			randf_range(margin, Constants.WORLD_SIZE_Y - margin)
		)
		container.add_child(mob)
