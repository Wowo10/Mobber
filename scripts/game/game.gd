extends Node2D

const GRID_SIZE = 100

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
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