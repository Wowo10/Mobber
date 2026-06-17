extends Node2D

signal player_entered_shop
signal player_exited_shop
signal player_entered_arena_master
signal player_exited_arena_master

const GRID_SIZE = 100
const FLOOR_TILE_SIZE = 256.0
const MOB_SCENE = preload("res://scenes/entities/mob.tscn")
const SHOP_ZONE_RECT := Rect2(100, 1650, 300, 300)
const ARENA_MASTER_ZONE_RECT := Rect2(2267, 1650, 300, 300)
const MOB_SYNC_INTERVAL := 0.1   # 10 Hz
const MOVE_THRESHOLD_SQ := 225.0  # 15 px — skip mobs that haven't moved
const FLOOR_TEXTURES := [
	preload("res://assets/textures/StoneFloorTexture1.png"),
	preload("res://assets/textures/StoneFloorTexture2.png"),
	preload("res://assets/textures/StoneFloorTexture3.png"),
	preload("res://assets/textures/StoneFloorTexture4.png"),
	preload("res://assets/textures/grass.jpg"),
	preload("res://assets/textures/grass2.jpg"),
	preload("res://assets/textures/grass3.jpg"),
]

var _sync_timer := 0.0
var _last_sync_positions: Dictionary = {}  # instance_id → Vector2
var _mob_by_id: Dictionary = {}            # net_id → node
var _mob_net_id: Dictionary = {}           # instance_id → net_id
var _next_mob_id: int = 0
var _floor_texture: Texture2D
var mob_speed_multiplier: float = 1.0
var mob_frenzy_timer: float = 0.0

func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_floor_texture = FLOOR_TEXTURES[randi() % FLOOR_TEXTURES.size()]
	_build_walls()
	_build_shop_zone()
	_build_arena_master_zone()
	$MobSpawner.spawn_path = $MobContainer.get_path()
	$MobSpawner.add_spawnable_scene("res://scenes/entities/mob.tscn")
	$MobContainer.child_entered_tree.connect(_on_mob_entered)
	$MobContainer.child_exiting_tree.connect(_on_mob_exiting)

func _on_mob_entered(mob: Node) -> void:
	var iid := mob.get_instance_id()
	_mob_by_id[_next_mob_id] = mob
	_mob_net_id[iid] = _next_mob_id
	_next_mob_id += 1

func _on_mob_exiting(mob: Node) -> void:
	var iid := mob.get_instance_id()
	var id: int = _mob_net_id.get(iid, -1)
	if id >= 0:
		_mob_by_id.erase(id)
		_mob_net_id.erase(iid)
	_last_sync_positions.erase(iid)

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

func _build_arena_master_zone() -> void:
	var area := Area2D.new()
	area.name = "ArenaMasterZone"
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = ARENA_MASTER_ZONE_RECT.size
	cs.position = ARENA_MASTER_ZONE_RECT.get_center()
	cs.shape = rect
	area.add_child(cs)
	area.body_entered.connect(_on_arena_master_body_entered)
	area.body_exited.connect(_on_arena_master_body_exited)
	add_child(area)

func _on_arena_master_body_entered(body: Node2D) -> void:
	if body.is_in_group("players") and body.is_multiplayer_authority():
		player_entered_arena_master.emit()

func _on_arena_master_body_exited(body: Node2D) -> void:
	if body.is_in_group("players") and body.is_multiplayer_authority():
		player_exited_arena_master.emit()

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

func _physics_process(delta: float) -> void:
	var networked: bool = not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked and not multiplayer.is_server():
		return
	if mob_frenzy_timer > 0.0:
		mob_frenzy_timer = max(0.0, mob_frenzy_timer - delta)
		if mob_frenzy_timer <= 0.0:
			mob_speed_multiplier = 1.0
	if not networked:
		return
	_sync_timer += delta
	if _sync_timer < MOB_SYNC_INTERVAL:
		return
	_sync_timer = 0.0
	var mobs := $MobContainer.get_children()
	if mobs.is_empty():
		return
	var ids := PackedInt32Array()
	var positions := PackedVector2Array()
	var velocities := PackedVector2Array()
	for mob in mobs:
		var iid := mob.get_instance_id()
		var last_pos: Vector2 = _last_sync_positions.get(iid, Vector2(-1e9, -1e9))
		if mob.position.distance_squared_to(last_pos) < MOVE_THRESHOLD_SQ:
			continue
		_last_sync_positions[iid] = mob.position
		ids.append(_mob_net_id.get(iid, -1))
		positions.append(mob.position)
		velocities.append(mob.velocity)
	if ids.is_empty():
		return
	_rpc_sync_mob_states.rpc(ids, positions, velocities)

@rpc("authority", "unreliable_ordered")
func _rpc_sync_mob_states(
	ids: PackedInt32Array,
	positions: PackedVector2Array,
	velocities: PackedVector2Array
) -> void:
	for i in ids.size():
		var mob = _mob_by_id.get(ids[i])
		if mob == null:
			continue
		mob.receive_server_state(positions[i], velocities[i])

@rpc("authority", "reliable")
func rpc_set_frenzy(speed_mult: float, duration: float) -> void:
	mob_speed_multiplier = speed_mult
	mob_frenzy_timer = duration

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


func _draw() -> void:
	var tex_size := _floor_texture.get_size()
	var src := Rect2(0, 0,
		Constants.WORLD_SIZE_X * tex_size.x / FLOOR_TILE_SIZE,
		Constants.WORLD_SIZE_Y * tex_size.y / FLOOR_TILE_SIZE)
	draw_texture_rect_region(_floor_texture, Rect2(0, 0, Constants.WORLD_SIZE_X, Constants.WORLD_SIZE_Y), src)
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
	var shop_center := SHOP_ZONE_RECT.get_center()
	draw_string(ThemeDB.fallback_font, Vector2(shop_center.x, shop_center.y + 14), "UPGRADES",
		HORIZONTAL_ALIGNMENT_CENTER, SHOP_ZONE_RECT.size.x, 28, Color(1.0, 0.9, 0.3))
	draw_rect(ARENA_MASTER_ZONE_RECT, Color(0.6, 0.1, 0.8, 0.25), true)
	draw_rect(ARENA_MASTER_ZONE_RECT, Color(0.75, 0.2, 0.95, 0.9), false, 3.0)
	var am_left := Vector2(ARENA_MASTER_ZONE_RECT.position.x, ARENA_MASTER_ZONE_RECT.get_center().y)
	draw_set_transform(am_left + Vector2(18, 0), -PI * 0.5, Vector2.ONE)
	draw_string(ThemeDB.fallback_font, Vector2(-ARENA_MASTER_ZONE_RECT.size.y * 0.5, 0), "ARENA MASTER",
		HORIZONTAL_ALIGNMENT_CENTER, ARENA_MASTER_ZONE_RECT.size.y, 22, Color(0.85, 0.5, 1.0))
	draw_set_transform(Vector2.ZERO)
