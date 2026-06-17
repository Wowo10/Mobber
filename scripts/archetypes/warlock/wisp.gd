extends Node2D

const BOLT_SCENE = preload("res://scenes/archetypes/warlock/warlock_bolt.tscn")
const SHOOT_INTERVAL = 2.5
const SEARCH_RADIUS = 300.0
const FOLLOW_SPEED = 4.0
const ORBIT_OFFSET := Vector2(40.0, -30.0)

var player_ref: Node = null
var visual_only := false
var lifetime := -1.0

var _shoot_timer := SHOOT_INTERVAL * 0.5
var _elapsed := 0.0

func _ready() -> void:
	$SfxAmbient.play()

func _process(delta: float) -> void:
	if not player_ref or not is_instance_valid(player_ref):
		queue_free()
		return

	_elapsed += delta
	if lifetime > 0.0:
		lifetime -= delta
		if lifetime <= 0.0:
			queue_free()
			return
	var target_pos: Vector2 = player_ref.global_position + ORBIT_OFFSET
	global_position = global_position.lerp(target_pos, FOLLOW_SPEED * delta)
	queue_redraw()

	if visual_only:
		return
	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked and not multiplayer.is_server():
		return

	_shoot_timer -= delta
	if _shoot_timer <= 0.0:
		_shoot_timer = SHOOT_INTERVAL
		_try_shoot()

func _try_shoot() -> void:
	var nearest: Node2D = null
	var nearest_dist := SEARCH_RADIUS
	for mob in get_tree().get_nodes_in_group("mobs"):
		var d: float = global_position.distance_to(mob.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = mob
	if nearest == null:
		return
	var dir: Vector2 = (nearest.global_position - global_position).normalized()
	_spawn_bolt(global_position, dir)
	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked:
		player_ref.rpc_spawn_wisp_bolt.rpc(global_position, dir)

func _spawn_bolt(pos: Vector2, dir: Vector2) -> void:
	var bolt := BOLT_SCENE.instantiate()
	bolt.set("direction", dir)
	bolt.set("player_ref", player_ref)
	bolt.set("visual_only", false)
	bolt.set("color_outer", Color(0.1, 0.55, 0.85, 0.8))
	bolt.set("color_inner", Color(0.75, 0.97, 1.0))
	get_parent().add_child(bolt)
	bolt.global_position = pos

func _draw() -> void:
	var pulse := sin(_elapsed * 3.5) * 0.3 + 0.7
	draw_circle(Vector2.ZERO, 8.0 * pulse, Color(0.2, 0.5, 1.0, 0.85))
	draw_circle(Vector2.ZERO, 4.0 * pulse, Color(0.7, 0.85, 1.0, 0.95))
	draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 24,
		Color(0.15, 0.4, 0.9, 0.35 * pulse), 1.5)
