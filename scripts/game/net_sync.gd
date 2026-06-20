extends Node

# NetSync — the connection/liveness layer: client-ready handshake, host heartbeat
# + migration, peer-disconnect handling, ping, and disconnect/leave flows. All
# game state lives on game.gd (parent) and the Economy / MatchManager siblings;
# this node orchestrates the networking transitions over that state.

# Host-liveness watchdog. The signaling server closes its sockets shortly after
# the lobby is sealed, and WebRTCMultiplayerPeer does not reliably emit
# server_disconnected when the host vanishes mid-game (especially on a hard
# quit). So the host broadcasts a heartbeat and clients trigger migration if it
# stops arriving.
const HEARTBEAT_INTERVAL := 0.5
const SERVER_TIMEOUT := 2.5

var game: Node

var _host_gone: bool = false
var _scrubbed: bool = false
var _heartbeat_timer: float = 0.0
var _server_silence: float = 0.0
var _clients_ready_count: int = 0
var _expected_client_count: int = 0
var _ping_timer: float = 0.0
var _ping_send_time: float = 0.0

@onready var _ping_label: Label = get_parent().get_node("HUD/PingLabel")

func _ready() -> void:
	game = get_parent()

# --- Networked startup ---

func begin() -> void:
	if multiplayer.is_server():
		_expected_client_count = multiplayer.get_peers().size()
		game._peer_to_archetype[1] = PlayerPrefs.archetype
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	else:
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		await get_tree().process_frame
		_rpc_client_ready.rpc_id(1, PlayerPrefs.archetype)

@rpc("any_peer", "reliable")
func _rpc_client_ready(arch: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	game._peer_to_archetype[id] = arch
	_clients_ready_count += 1
	if _clients_ready_count < _expected_client_count:
		return
	var center := Vector2(Constants.WORLD_SIZE_X * 0.5, Constants.WORLD_SIZE_Y * 0.5)
	for arena in [game.arena1, game.arena2]:
		arena.spawn_mob(0, center)
		for i in Constants.MOB_COUNT - 1:
			arena.spawn_mob()
	for peer_id in game._peer_to_arena:
		game._spawn_player(peer_id)
	_rpc_spawn_players.rpc(game._peer_to_archetype, PlayerPrefs.mob_win_count)
	game._push_hud_update()

@rpc("authority", "reliable")
func _rpc_spawn_players(archetypes: Dictionary, win_count: int) -> void:
	PlayerPrefs.mob_win_count = win_count
	game._peer_to_archetype = archetypes
	# _peer_to_arena already populated from PlayerPrefs.peer_teams in game._ready()
	for peer_id in game._peer_to_arena:
		game._spawn_player(peer_id)

# --- Host liveness / heartbeat ---

# Server pulses a heartbeat; clients trip the host-left screen when it goes
# silent. This is the only reliable cross-peer signal that the host is gone — see
# HEARTBEAT_INTERVAL.
func update_host_liveness(delta: float) -> void:
	if multiplayer.is_server():
		_heartbeat_timer -= delta
		if _heartbeat_timer <= 0.0:
			_heartbeat_timer = HEARTBEAT_INTERVAL
			_rpc_heartbeat.rpc()
	elif not _host_gone:
		_server_silence += delta
		if _server_silence >= SERVER_TIMEOUT:
			_on_server_disconnected()

@rpc("authority", "unreliable")
func _rpc_heartbeat() -> void:
	_server_silence = 0.0

func _on_server_disconnected() -> void:
	if _host_gone:
		return
	_host_gone = true
	_show_host_left()

# Host vanished mid-match. There is no migration — the match simply ends. Tear
# the dead peer down cleanly and show the end screen with the final scoreboard.
func _show_host_left() -> void:
	if game.get_node("GameOverOverlay").visible:
		return
	game._leaving = true

	# Scrub before dropping the peer so the MultiplayerSpawner's _stop() despawn
	# doesn't trip the SceneCacheInterface dangling-callable errors.
	scrub_multiplayer_hooks()
	multiplayer.multiplayer_peer = null

	for child in game.get_node("PlayerContainer").get_children():
		child.set_physics_process(false)

	var my_id: int = multiplayer.get_unique_id()

	var vbox := game.get_node("GameOverOverlay/VBox")
	var title := vbox.get_node("TitleLabel")
	var sub := vbox.get_node("SubLabel")
	var return_btn := vbox.get_node("ReturnButton")

	title.text = "HOST LEFT"
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	sub.text = "The host disconnected — match ended."
	sub.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5))

	var existing := vbox.find_child("GameOverScoreboard", false, false)
	if existing:
		existing.free()

	var sb: Control = game._build_game_over_scoreboard(my_id)
	sb.name = "GameOverScoreboard"
	vbox.add_child(sb)
	vbox.move_child(return_btn, vbox.get_child_count() - 1)

	game.get_node("GameOverOverlay").visible = true

# --- Peer disconnect ---

func _on_peer_disconnected(id: int) -> void:
	if game._spectator_peer_ids.has(id):
		game._spectator_peer_ids.erase(id)
		_rpc_show_notice.rpc("A spectator disconnected.")
		return

	game.economy.spread_gold(id)
	game._snapshot_disconnected_peer(id)
	if game._networked:
		var arena_idx := 1 if game._peer_to_arena.get(id) == game.arena1 else 2
		_rpc_notify_player_left.rpc(
			id,
			PlayerPrefs.peer_names.get(id, "Player"),
			game._peer_to_archetype.get(id, 0),
			arena_idx,
			{
				"kills":     game._peer_kills.get(id, 0),
				"earned":    game._peer_money_earned.get(id, 0),
				"mobs_sent": game._peer_mobs_sent.get(id, 0),
				"debuffs":   game._peer_debuffs_applied.get(id, 0),
			}
		)
	if game._peer_to_player.has(id):
		game._peer_to_player[id].queue_free()
	game._peer_to_player.erase(id)
	var arena: Node2D = game._peer_to_arena.get(id)
	game._peer_to_arena.erase(id)

	if arena != null and game._count_players_in_arena(arena) == 0:
		var losing_arena_id := 1 if arena == game.arena1 else 2
		game.match_manager._rpc_game_over(losing_arena_id)
		game.match_manager._rpc_game_over.rpc(losing_arena_id)
	else:
		_rpc_show_notice.rpc("A player disconnected.")

@rpc("authority", "reliable")
func _rpc_show_notice(msg: String) -> void:
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.anchors_preset = Control.PRESET_TOP_WIDE
	lbl.offset_top = 60.0
	game.get_node("HUD").add_child(lbl)
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(lbl):
		lbl.queue_free()

@rpc("authority", "reliable")
func _rpc_notify_player_left(peer_id: int, ghost_name: String, arch_id: int, arena_idx: int, stats: Dictionary) -> void:
	if game._peer_to_player.has(peer_id):
		game._peer_to_player[peer_id].queue_free()
	game._peer_to_player.erase(peer_id)
	var arena: Node2D = game.arena1 if arena_idx == 1 else game.arena2
	game._ghost_players.append({
		"name":    ghost_name,
		"arch_id": arch_id,
		"arena":   arena,
		"stats":   stats,
	})
	game._peer_to_arena.erase(peer_id)

# --- Ping ---

@rpc("any_peer", "unreliable")
func _rpc_ping_request() -> void:
	if not multiplayer.is_server():
		return
	_rpc_ping_response.rpc_id(multiplayer.get_remote_sender_id())

@rpc("authority", "unreliable")
func _rpc_ping_response() -> void:
	if _ping_label == null:
		return
	var ms := int(Time.get_ticks_msec() - _ping_send_time)
	_ping_label.text = "%d ms" % ms

func tick_ping(delta: float) -> void:
	if not (game._networked and not multiplayer.is_server() and _ping_label != null):
		return
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = 2.0
		_ping_send_time = Time.get_ticks_msec()
		_rpc_ping_request.rpc_id(1)

# --- Disconnect / leave ---

func scrub_multiplayer_hooks() -> void:
	if _scrubbed:
		return
	_scrubbed = true
	# Godot 4.5: SceneCacheInterface clears its callable refs when processing
	# despawn packets but leaves signal connections intact. When nodes then exit
	# the tree the dangling callable causes a disconnect error. Pre-emptively
	# remove all connections from the signals SceneMultiplayer tracks.
	# Mobs must be freed before the spawner exits the tree; if the spawner's
	# _stop() runs while MobContainer is gone it logs "!node" for every mob.
	for arena in [game.arena1, game.arena2]:
		var mc: Node = arena.get_node_or_null("MobContainer")
		if mc:
			for mob in mc.get_children():
				_clear_signal(mob.tree_exiting)
			mc.free()
		var spawner: Node = arena.get_node_or_null("MobSpawner")
		if spawner:
			_clear_signal(spawner.tree_exited)
	for player in game.get_node("PlayerContainer").get_children():
		_clear_signal(player.tree_exited)
	_clear_signal(game.tree_exited)

func _clear_signal(sig: Signal) -> void:
	for c in sig.get_connections():
		var cb: Callable = c["callable"]
		if cb.is_valid() and sig.is_connected(cb):
			sig.disconnect(cb)

func leave_game() -> void:
	scrub_multiplayer_hooks()
	if game._networked:
		multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
