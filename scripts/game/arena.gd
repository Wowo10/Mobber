extends Node2D

signal player_entered_shop
signal player_exited_shop

const GRID_SIZE = 100
const MOB_SCENE = preload("res://scenes/entities/mob.tscn")
const SHOP_ZONE_RECT := Rect2(100, 1650, 300, 300)

func _ready() -> void:
	_build_walls()
	_build_shop_zone()
	$MobSpawner.spawn_path = $MobContainer.get_path()
	$MobSpawner.add_spawnable_scene("res://scenes/entities/mob.tscn")

func _build_shop_zone() -> void:
	var area := Area2D.new()
	area.name = "ShopZone"
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = SHOP_ZONE_RECT.size
	cs.position = SHOP_ZONE_RECT.get_center()
	cs.shape = rect
	area.add_child(cs)
	area.body_entered.connect(_on_shop_body_entered)
	area.body_exited.connect(_on_shop_body_exited)
	add_child(area)

func _on_shop_body_entered(body: Node2D) -> void:
	if body.is_in_group("players") and body.is_multiplayer_authority():
		player_entered_shop.emit()

func _on_shop_body_exited(body: Node2D) -> void:
	if body.is_in_group("players") and body.is_multiplayer_authority():
		player_exited_shop.emit()

func _build_walls() -> void:
	var body := StaticBody2D.new()
	add_child(body)
	var wx: float = Constants.WORLD_SIZE_X
	var wy: float = Constants.WORLD_SIZE_Y
	var t := 40.0
	var walls := [
		[Vector2(wx * 0.5, -t * 0.5),      Vector2(wx + t * 2, t)],
		[Vector2(wx * 0.5, wy + t * 0.5),  Vector2(wx + t * 2, t)],
		[Vector2(-t * 0.5, wy * 0.5),      Vector2(t, wy)],
		[Vector2(wx + t * 0.5, wy * 0.5),  Vector2(t, wy)],
	]
	for w in walls:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = w[1]
		cs.position = w[0]
		cs.shape = shape
		body.add_child(cs)

func spawn_mob(type: int = -1, near_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if not multiplayer.is_server():
		return
	var margin: float = Constants.MOB_RADIUS + 10.0
	var mob := MOB_SCENE.instantiate()
	if type == -1:
		mob.mob_type = mob.MobType.FLEEING if randf() < 0.35 else mob.MobType.BASIC
	else:
		mob.mob_type = type
	if near_pos.x >= 0.0:
		var angle := randf_range(0.0, TAU)
		var dist := randf_range(100.0, 220.0)
		mob.position = Vector2(
			clampf(near_pos.x + cos(angle) * dist, margin, Constants.WORLD_SIZE_X - margin),
			clampf(near_pos.y + sin(angle) * dist, margin, Constants.WORLD_SIZE_Y - margin)
		)
	else:
		mob.position = Vector2(
			randf_range(margin, Constants.WORLD_SIZE_X - margin),
			randf_range(margin, Constants.WORLD_SIZE_Y - margin)
		)
	$MobContainer.add_child(mob, true)

func get_mob_count() -> int:
	var total := 0
	for mob in $MobContainer.get_children():
		total += mob.mob_worth
	return total

@rpc("any_peer", "unreliable_ordered")
func rpc_push_mob(mob_name: StringName, impulse: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var mob := $MobContainer.get_node_or_null(NodePath(mob_name))
	if mob:
		mob.apply_push(impulse)


func _draw() -> void:
	var i := 0
	for x in range(0, Constants.WORLD_SIZE_X + 1, GRID_SIZE):
		var col := Color(0.2, 0.4, 0.8, 0.55) if i % 3 == 0 else Color(0.5, 0.5, 0.5, 0.4)
		draw_line(Vector2(x, 0), Vector2(x, Constants.WORLD_SIZE_Y), col, 1.0)
		i += 1
	i = 0
	for y in range(0, Constants.WORLD_SIZE_Y + 1, GRID_SIZE):
		var col := Color(0.2, 0.4, 0.8, 0.55) if i % 3 == 0 else Color(0.5, 0.5, 0.5, 0.4)
		draw_line(Vector2(0, y), Vector2(Constants.WORLD_SIZE_X, y), col, 1.0)
		i += 1
	draw_rect(Rect2(0, 0, Constants.WORLD_SIZE_X, Constants.WORLD_SIZE_Y), Color(0.8, 0.2, 0.2, 0.8), false, 8.0)
	draw_rect(SHOP_ZONE_RECT, Color(0.85, 0.7, 0.1, 0.25), true)
	draw_rect(SHOP_ZONE_RECT, Color(0.95, 0.8, 0.15, 0.9), false, 3.0)
	var center := SHOP_ZONE_RECT.get_center()
	draw_string(ThemeDB.fallback_font, Vector2(center.x, center.y + 14), "SHOP",
		HORIZONTAL_ALIGNMENT_CENTER, SHOP_ZONE_RECT.size.x, 28, Color(1.0, 0.9, 0.3))
