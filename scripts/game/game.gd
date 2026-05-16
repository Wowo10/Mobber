extends Node

const PLAYER_SCENE = preload("res://scenes/entities/player.tscn")

var _peer_to_arena: Dictionary = {}
var _peer_to_player: Dictionary = {}
var _networked: bool = false

func _ready() -> void:
	_networked = multiplayer.multiplayer_peer is ENetMultiplayerPeer

	if not _networked:
		_peer_to_arena[1] = $Arena1
		_spawn_player(1)
		for _i in Constants.MOB_COUNT:
			$Arena1.spawn_mob()
		return

	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		_peer_to_arena[1] = $Arena1
		for _i in Constants.MOB_COUNT:
			$Arena1.spawn_mob()
	else:
		# Signal server that our scene is loaded and we're ready for spawn data
		_rpc_client_ready.rpc_id(1)

# Client → Server: "I'm ready, send me spawn data"
@rpc("any_peer", "reliable")
func _rpc_client_ready() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	_peer_to_arena[id] = $Arena2
	for _i in Constants.MOB_COUNT:
		$Arena2.spawn_mob()
	_spawn_player(1)
	_spawn_player(id)
	# Tell client to create both player nodes on its side
	_rpc_spawn_players.rpc(id)

# Server → All clients: "create these two players"
@rpc("authority", "reliable")
func _rpc_spawn_players(client_id: int) -> void:
	_peer_to_arena[1] = $Arena1
	_peer_to_arena[client_id] = $Arena2
	_spawn_player(1)
	_spawn_player(client_id)

func _on_peer_disconnected(id: int) -> void:
	if _peer_to_player.has(id):
		_peer_to_player[id].queue_free()
	_peer_to_player.erase(id)
	_peer_to_arena.erase(id)

func _spawn_player(peer_id: int) -> void:
	if _peer_to_player.has(peer_id):
		return
	var arena: Node2D = _peer_to_arena[peer_id]
	var player := PLAYER_SCENE.instantiate()
	player.name = "Player_%d" % peer_id
	player.position = arena.position + Vector2(Constants.WORLD_SIZE_X * 0.5, Constants.WORLD_SIZE_Y * 0.5)
	$PlayerContainer.add_child(player, true)
	player.set_multiplayer_authority(peer_id)
	_peer_to_player[peer_id] = player

func notify_mob_killed(arena: Node2D) -> void:
	if not multiplayer.is_server():
		return
	var opponent: Node2D = $Arena2 if arena == $Arena1 else $Arena1
	opponent.spawn_mob()
	opponent.spawn_mob()
	_check_win()

func _check_win() -> void:
	if $Arena1.get_mob_count() >= 100:
		_rpc_game_over.rpc(1)
	elif $Arena2.get_mob_count() >= 100:
		_rpc_game_over.rpc(2)

@rpc("authority", "reliable")
func _rpc_game_over(losing_arena_id: int) -> void:
	print("Arena %d loses! Game over." % losing_arena_id)
