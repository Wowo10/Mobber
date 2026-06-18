extends Node

const PLAYER_SCENE = preload("res://scenes/entities/player.tscn")
const SKILL_UNLOCK_THRESHOLDS := [0.10, 0.40, 0.70]

# Host-liveness watchdog. The signaling server closes its sockets shortly after
# the lobby is sealed, and WebRTCMultiplayerPeer does not reliably emit
# server_disconnected when the host vanishes mid-game (especially on a hard
# quit). So the host broadcasts a heartbeat and clients trigger migration if it
# stops arriving.
const HEARTBEAT_INTERVAL := 0.5
const SERVER_TIMEOUT := 2.5

var _peer_to_arena: Dictionary = {}
var _peer_to_player: Dictionary = {}
var _peer_to_archetype: Dictionary = {}
var _networked: bool = false
var _leaving: bool = false
var _scrubbed: bool = false
var _migrating: bool = false
var _heartbeat_timer: float = 0.0
var _server_silence: float = 0.0
var _clients_ready_count: int = 0
var _expected_client_count: int = 0
var _pending_kills: Dictionary = {}  # arena -> count of mobs dying this frame
var _pending_kills_flush_queued: bool = false
var _player_speed_levels: Dictionary = {}   # peer_id -> int
var _player_damage_levels: Dictionary = {}
var _player_sword_size_levels: Dictionary = {}
var _player_attack_speed_levels: Dictionary = {}
var _player_skill1_levels: Dictionary = {}
var _player_skill2_levels: Dictionary = {}
var _player_skill3_levels: Dictionary = {}
var _peer_money: Dictionary = {}  # peer_id -> int
var _player_skills_unlocked: Dictionary = {}   # peer_id -> [false, false, false]
var _player_unlocks_pending: Dictionary = {}   # peer_id -> int
var _player_unlock_milestone: Dictionary = {}  # peer_id -> int (0-3)
var _spectator_peer_ids: Array = []
var _spectator_camera: Camera2D = null
var _in_shop_zone := false
var _in_arena_master_zone := false
var _peer_kills: Dictionary = {}
var _peer_money_earned: Dictionary = {}
var _peer_mobs_sent: Dictionary = {}
var _peer_debuffs_applied: Dictionary = {}
var _peer_stats_cache: Dictionary = {}
var _ghost_players: Array = []  # snapshots of disconnected peers kept for scoreboard display
var _scoreboard_panel: Control = null
var _scoreboard_col1: VBoxContainer = null
var _scoreboard_col2: VBoxContainer = null
var _my_mob_bar: Control = null
var _enemy_mob_bar: Control = null
var _ping_label: Label = null
var _ping_timer: float = 0.0
var _ping_send_time: float = 0.0
var _fps_label: Label = null
var _fps_timer: float = 0.0

func _ready() -> void:
	_networked = not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	_setup_skill_bar()
	_setup_shop()
	_setup_mob_bars()
	$Arena1.player_entered_shop.connect(_on_player_entered_shop)
	$Arena1.player_exited_shop.connect(_on_player_exited_shop)
	$Arena2.player_entered_shop.connect(_on_player_entered_shop)
	$Arena2.player_exited_shop.connect(_on_player_exited_shop)
	$Arena1.player_entered_arena_master.connect(_on_player_entered_arena_master)
	$Arena1.player_exited_arena_master.connect(_on_player_exited_arena_master)
	$Arena2.player_entered_arena_master.connect(_on_player_entered_arena_master)
	$Arena2.player_exited_arena_master.connect(_on_player_exited_arena_master)
	_setup_scoreboard()
	_ping_label = $HUD/PingLabel
	_fps_label = $HUD/FpsLabel

	if not _networked:
		PlayerPrefs.peer_names = {1: PlayerPrefs.player_name}
		_peer_to_arena[1] = $Arena1
		_peer_to_archetype[1] = PlayerPrefs.archetype
		_spawn_player(1)
		var center := Vector2(Constants.WORLD_SIZE_X * 0.5, Constants.WORLD_SIZE_Y * 0.5)
		$Arena1.spawn_mob(0, center)
		for i in Constants.MOB_COUNT - 1:
			$Arena1.spawn_mob()
		_push_hud_update()
		return

	_spectator_peer_ids = PlayerPrefs.peer_spectators

	# Populate arena assignments from the team layout decided in game_room
	for peer_id in PlayerPrefs.peer_teams:
		_peer_to_arena[peer_id] = $Arena1 if PlayerPrefs.peer_teams[peer_id] == 0 else $Arena2

	var my_id_ready: int = multiplayer.get_unique_id()
	if _spectator_peer_ids.has(my_id_ready):
		_setup_spectator_camera()

	if multiplayer.is_server():
		_expected_client_count = multiplayer.get_peers().size()
		_peer_to_archetype[1] = PlayerPrefs.archetype
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
	_peer_to_archetype[id] = arch
	_clients_ready_count += 1
	if _clients_ready_count < _expected_client_count:
		return
	var center := Vector2(Constants.WORLD_SIZE_X * 0.5, Constants.WORLD_SIZE_Y * 0.5)
	for arena in [$Arena1, $Arena2]:
		arena.spawn_mob(0, center)
		for i in Constants.MOB_COUNT - 1:
			arena.spawn_mob()
	for peer_id in _peer_to_arena:
		_spawn_player(peer_id)
	_rpc_spawn_players.rpc(_peer_to_archetype, PlayerPrefs.mob_win_count)
	_push_hud_update()

@rpc("authority", "reliable")
func _rpc_spawn_players(archetypes: Dictionary, win_count: int) -> void:
	PlayerPrefs.mob_win_count = win_count
	_peer_to_archetype = archetypes
	# _peer_to_arena already populated from PlayerPrefs.peer_teams in _ready()
	for peer_id in _peer_to_arena:
		_spawn_player(peer_id)

func _on_server_disconnected() -> void:
	if _migrating:
		return
	_migrating = true
	_begin_host_migration()

# Server pulses a heartbeat; clients trip migration when it goes silent. This is
# the only reliable cross-peer signal that the host is gone — see HEARTBEAT_INTERVAL.
func _update_host_liveness(delta: float) -> void:
	if multiplayer.is_server():
		_heartbeat_timer -= delta
		if _heartbeat_timer <= 0.0:
			_heartbeat_timer = HEARTBEAT_INTERVAL
			_rpc_heartbeat.rpc()
	elif not _migrating:
		_server_silence += delta
		if _server_silence >= SERVER_TIMEOUT:
			_on_server_disconnected()

@rpc("authority", "unreliable")
func _rpc_heartbeat() -> void:
	_server_silence = 0.0

func _begin_host_migration() -> void:
	if _peer_to_player.is_empty():
		_scrub_multiplayer_hooks()
		multiplayer.multiplayer_peer = null
		_show_disconnect("Host disconnected. Returning to lobby...")
		return
	var my_old_id := multiplayer.get_unique_id()
	var a1_count: int = $Arena1.get_mob_count()
	var a2_count: int = $Arena2.get_mob_count()

	# Disconnect tree signals to suppress SceneCacheInterface errors when the
	# spawner stops on peer transition. MobContainer is intentionally NOT freed
	# so spawn_mob() keeps working after we re-enable local authority below.
	if not _scrubbed:
		_scrubbed = true
		for arena in [$Arena1, $Arena2]:
			var mc: Node = arena.get_node_or_null("MobContainer")
			if mc:
				for mob in mc.get_children():
					_clear_signal(mob.tree_exiting)
			var spawner: Node = arena.get_node_or_null("MobSpawner")
			if spawner:
				_clear_signal(spawner.tree_exited)
		for player in $PlayerContainer.get_children():
			_clear_signal(player.tree_exited)
		_clear_signal(tree_exited)

	# Switching to null makes multiplayer.is_server() return true locally and
	# causes the MultiplayerSpawner to despawn all mob nodes via _stop().
	multiplayer.multiplayer_peer = null
	_networked = false

	# Spread the ex-host's gold to their teammates before removing their data.
	_spread_gold(1)
	_snapshot_disconnected_peer(1)

	# Remove the ex-host's player node. In offline mode get_unique_id() == 1,
	# so any node still carrying authority 1 would be wrongly controlled by us.
	var host_player = _peer_to_player.get(1)
	if host_player and is_instance_valid(host_player):
		host_player.queue_free()
	_peer_to_player.erase(1)
	_peer_to_arena.erase(1)
	_peer_to_archetype.erase(1)

	# Remap our old peer ID to 1 (the local offline authority ID) across every
	# peer-keyed dictionary so all existing HUD, shop, and win-condition logic
	# that resolves "my_id = 1 if not _networked" keeps working.
	if my_old_id != 1:
		for dict in [_peer_to_player, _peer_to_arena, _peer_to_archetype,
				_peer_money, _peer_kills, _peer_money_earned, _peer_mobs_sent,
				_peer_debuffs_applied, _peer_stats_cache,
				_player_speed_levels, _player_damage_levels, _player_sword_size_levels,
				_player_attack_speed_levels, _player_skill1_levels, _player_skill2_levels,
				_player_skill3_levels, _player_skills_unlocked, _player_unlocks_pending,
				_player_unlock_milestone, PlayerPrefs.peer_names]:
			if dict.has(my_old_id):
				dict[1] = dict[my_old_id]
				dict.erase(my_old_id)

	# Re-assign authority so our player's is_multiplayer_authority() returns true.
	# It was set to my_old_id at spawn; offline ID is always 1.
	var our_player = _peer_to_player.get(1)
	if our_player and is_instance_valid(our_player):
		our_player.set_multiplayer_authority(1)

	# If the opponent arena is now empty, the local player won — show the end screen.
	var our_arena: Node2D = _peer_to_arena.get(1)
	var opponent_arena: Node2D = $Arena2 if our_arena == $Arena1 else $Arena1
	if _count_players_in_arena(opponent_arena) == 0:
		_rpc_game_over(1 if opponent_arena == $Arena1 else 2)
		return

	# Spawner cleared the mob nodes; re-spawn to match the pre-disconnect counts.
	for i in a1_count:
		$Arena1.spawn_mob()
	for i in a2_count:
		$Arena2.spawn_mob()

	_push_hud_update()

func _snapshot_disconnected_peer(id: int) -> void:
	var arena: Node2D = _peer_to_arena.get(id)
	if arena == null:
		return
	_ghost_players.append({
		"name":     PlayerPrefs.peer_names.get(id, "Player"),
		"arch_id":  _peer_to_archetype.get(id, 0),
		"arena":    arena,
		"stats": {
			"kills":     _peer_kills.get(id, 0),
			"earned":    _peer_money_earned.get(id, 0),
			"mobs_sent": _peer_mobs_sent.get(id, 0),
			"debuffs":   _peer_debuffs_applied.get(id, 0),
		},
	})

func _spread_gold(leaving_id: int) -> void:
	var gold: int = _peer_money.get(leaving_id, 0)
	if gold <= 0:
		return
	var leaving_arena: Node2D = _peer_to_arena.get(leaving_id)
	if leaving_arena == null:
		return
	var teammates: Array = []
	for pid in _peer_to_arena:
		if pid != leaving_id and _peer_to_arena[pid] == leaving_arena:
			teammates.append(pid)
	if teammates.is_empty():
		return
	var share := gold / teammates.size()
	for pid in teammates:
		_peer_money[pid] = _peer_money.get(pid, 0) + share
	_peer_money[leaving_id] = 0
	_update_money_local(_peer_money)
	if _networked:
		_rpc_update_money.rpc(_peer_money)

func _on_peer_disconnected(id: int) -> void:
	if _spectator_peer_ids.has(id):
		_spectator_peer_ids.erase(id)
		_rpc_show_notice.rpc("A spectator disconnected.")
		return

	_spread_gold(id)
	_snapshot_disconnected_peer(id)
	if _networked:
		var arena_idx := 1 if _peer_to_arena.get(id) == $Arena1 else 2
		_rpc_notify_player_left.rpc(
			id,
			PlayerPrefs.peer_names.get(id, "Player"),
			_peer_to_archetype.get(id, 0),
			arena_idx,
			{
				"kills":     _peer_kills.get(id, 0),
				"earned":    _peer_money_earned.get(id, 0),
				"mobs_sent": _peer_mobs_sent.get(id, 0),
				"debuffs":   _peer_debuffs_applied.get(id, 0),
			}
		)
	if _peer_to_player.has(id):
		_peer_to_player[id].queue_free()
	_peer_to_player.erase(id)
	var arena: Node2D = _peer_to_arena.get(id)
	_peer_to_arena.erase(id)

	if arena != null and _count_players_in_arena(arena) == 0:
		var losing_arena_id := 1 if arena == $Arena1 else 2
		_rpc_game_over(losing_arena_id)
		_rpc_game_over.rpc(losing_arena_id)
	else:
		_rpc_show_notice.rpc("A player disconnected.")

func _count_players_in_arena(arena: Node2D) -> int:
	var count := 0
	for pid in _peer_to_player:
		if _peer_to_arena.get(pid) == arena:
			count += 1
	return count

@rpc("authority", "reliable")
func _rpc_show_notice(msg: String) -> void:
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.anchors_preset = Control.PRESET_TOP_WIDE
	lbl.offset_top = 60.0
	$HUD.add_child(lbl)
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(lbl):
		lbl.queue_free()

@rpc("authority", "reliable")
func _rpc_notify_player_left(peer_id: int, ghost_name: String, arch_id: int, arena_idx: int, stats: Dictionary) -> void:
	if _peer_to_player.has(peer_id):
		_peer_to_player[peer_id].queue_free()
	_peer_to_player.erase(peer_id)
	var arena: Node2D = $Arena1 if arena_idx == 1 else $Arena2
	_ghost_players.append({
		"name":    ghost_name,
		"arch_id": arch_id,
		"arena":   arena,
		"stats":   stats,
	})
	_peer_to_arena.erase(peer_id)

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

func _show_disconnect(msg: String) -> void:
	_leaving = true
	for child in $PlayerContainer.get_children():
		child.set_physics_process(false)
	$DisconnectOverlay/MsgLabel.text = msg
	$DisconnectOverlay.visible = true
	await get_tree().create_timer(3.0).timeout
	_leave_game()

func _scrub_multiplayer_hooks() -> void:
	if _scrubbed:
		return
	_scrubbed = true
	# Godot 4.5: SceneCacheInterface clears its callable refs when processing
	# despawn packets but leaves signal connections intact. When nodes then exit
	# the tree the dangling callable causes a disconnect error. Pre-emptively
	# remove all connections from the signals SceneMultiplayer tracks.
	# Mobs must be freed before the spawner exits the tree; if the spawner's
	# _stop() runs while MobContainer is gone it logs "!node" for every mob.
	for arena in [$Arena1, $Arena2]:
		var mc: Node = arena.get_node_or_null("MobContainer")
		if mc:
			for mob in mc.get_children():
				_clear_signal(mob.tree_exiting)
			mc.free()
		var spawner: Node = arena.get_node_or_null("MobSpawner")
		if spawner:
			_clear_signal(spawner.tree_exited)
	for player in $PlayerContainer.get_children():
		_clear_signal(player.tree_exited)
	_clear_signal(tree_exited)

func _clear_signal(sig: Signal) -> void:
	for c in sig.get_connections():
		var cb: Callable = c["callable"]
		if cb.is_valid() and sig.is_connected(cb):
			sig.disconnect(cb)

func _leave_game() -> void:
	_scrub_multiplayer_hooks()
	if _networked:
		multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")

func _setup_spectator_camera() -> void:
	var cam := Camera2D.new()
	cam.set_script(load("res://scripts/game/spectator_camera.gd"))
	add_child(cam)
	cam.init($Arena1, $Arena2)
	_spectator_camera = cam

	$HUD/SkillBar.visible = false

	if _my_mob_bar != null:
		_my_mob_bar.label_prefix = "A1  "
	if _enemy_mob_bar != null:
		_enemy_mob_bar.label_prefix = "A2  "

	var hint := Label.new()
	hint.text = "SPECTATING  |  Tab: switch arena"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.7))
	hint.anchors_preset = Control.PRESET_BOTTOM_WIDE
	hint.offset_bottom = -10.0
	hint.offset_top = -40.0
	$HUD.add_child(hint)

func _spawn_player(peer_id: int) -> void:
	if _peer_to_player.has(peer_id):
		return
	if _spectator_peer_ids.has(peer_id):
		return
	var arena: Node2D = _peer_to_arena[peer_id]
	var slot := 0
	for existing_id in _peer_to_player:
		if _peer_to_arena[existing_id] == arena:
			slot += 1
	var center := Vector2(Constants.WORLD_SIZE_X * 0.5, Constants.WORLD_SIZE_Y * 0.5)
	var offset := Vector2((slot * 200) - 100, 0)
	var player := PLAYER_SCENE.instantiate()
	player.name = "Player_%d" % peer_id
	player.position = arena.position + center + offset
	player.archetype = _peer_to_archetype.get(peer_id, 0)
	player.player_name = PlayerPrefs.peer_names.get(peer_id, "")
	$PlayerContainer.add_child(player, true)
	player.set_multiplayer_authority(peer_id)
	_peer_to_player[peer_id] = player
	if multiplayer.is_server() or not _networked:
		_player_skills_unlocked[peer_id] = [false, false, false]
		_player_unlocks_pending[peer_id] = 0
		_player_unlock_milestone[peer_id] = 0

func notify_mob_killed(arena: Node2D, killer: Node = null) -> void:
	if not multiplayer.is_server() or _leaving:
		return
	var opponent: Node2D = $Arena2 if arena == $Arena1 else $Arena1
	opponent.spawn_mob()
	opponent.spawn_mob()
	var killer_id := -1
	if killer and is_instance_valid(killer):
		for pid in _peer_to_player:
			if _peer_to_player[pid] == killer:
				killer_id = pid
				break
	if killer_id != -1:
		_peer_money[killer_id] = _peer_money.get(killer_id, 0) + Constants.KILL_REWARD
		_peer_kills[killer_id] = _peer_kills.get(killer_id, 0) + 1
		_peer_money_earned[killer_id] = _peer_money_earned.get(killer_id, 0) + Constants.KILL_REWARD
	else:
		for pid in _peer_to_arena:
			if _peer_to_arena[pid] == arena:
				_peer_money[pid] = _peer_money.get(pid, 0) + Constants.KILL_REWARD
				_peer_money_earned[pid] = _peer_money_earned.get(pid, 0) + Constants.KILL_REWARD
	_update_money_local(_peer_money)
	if _networked:
		_rpc_update_money.rpc(_peer_money)
	var _s := _gather_stats()
	_peer_stats_cache = _s
	if _networked:
		_rpc_update_stats.rpc(_s)
	# Accumulate kills this frame — queue_free runs after deferred calls,
	# so every mob that died this frame is still counted by get_mob_count().
	_pending_kills[arena] = _pending_kills.get(arena, 0) + 1
	var a1: int = $Arena1.get_mob_count() - _pending_kills.get($Arena1, 0)
	var a2: int = $Arena2.get_mob_count() - _pending_kills.get($Arena2, 0)
	_update_hud_local(a1, a2)
	if _networked:
		_rpc_update_hud.rpc(a1, a2)
	_check_win(a1, a2)
	_check_skill_unlocks(a1, a2)
	if not _pending_kills_flush_queued:
		_pending_kills_flush_queued = true
		call_deferred("_clear_pending_kills")

func _clear_pending_kills() -> void:
	_pending_kills.clear()
	_pending_kills_flush_queued = false

# --- HUD ---

func _push_hud_update() -> void:
	var a1: int = $Arena1.get_mob_count()
	var a2: int = $Arena2.get_mob_count()
	_update_hud_local(a1, a2)
	if _networked and multiplayer.is_server():
		_rpc_update_hud.rpc(a1, a2)
	if multiplayer.is_server() or not _networked:
		_check_win(a1, a2)
		_check_skill_unlocks(a1, a2)

func _setup_mob_bars() -> void:
	$HUD/MyLabel.visible = false
	$HUD/EnemyLabel.visible = false

	var MobBar := preload("res://scripts/ui/mob_bar.gd")
	var vp := get_viewport().get_visible_rect().size

	var my_bar: Control = MobBar.new()
	$HUD.add_child(my_bar)
	my_bar.size = Vector2(300.0, 32.0)
	my_bar.position = Vector2((vp.x - my_bar.size.x) * 0.5, 10.0)
	_my_mob_bar = my_bar

	var enemy_bar: Control = MobBar.new()
	enemy_bar.label_prefix = "ENEMY  "
	$HUD.add_child(enemy_bar)
	enemy_bar.size = Vector2(220.0, 32.0)
	enemy_bar.position = Vector2(vp.x - enemy_bar.size.x - 10.0, 10.0)
	_enemy_mob_bar = enemy_bar

func _update_hud_local(a1: int, a2: int) -> void:
	if _my_mob_bar == null:
		return
	var my_id: int = 1 if not _networked else multiplayer.get_unique_id()
	if _spectator_peer_ids.has(my_id):
		_my_mob_bar.set_count(a1, PlayerPrefs.mob_win_count)
		_enemy_mob_bar.set_count(a2, PlayerPrefs.mob_win_count)
		return
	var my_is_arena1: bool = _peer_to_arena.get(my_id) == $Arena1
	var my    := a1 if my_is_arena1 else a2
	var enemy := a2 if my_is_arena1 else a1
	_my_mob_bar.set_count(my, PlayerPrefs.mob_win_count)
	_enemy_mob_bar.set_count(enemy, PlayerPrefs.mob_win_count)

@rpc("authority", "reliable")
func _rpc_update_hud(a1: int, a2: int) -> void:
	_update_hud_local(a1, a2)

func _update_money_local(peer_money: Dictionary) -> void:
	_peer_money = peer_money
	var my_id: int = 1 if not _networked else multiplayer.get_unique_id()
	$HUD/MoneyLabel.text = "$%d" % _peer_money.get(my_id, 0)
	_update_shop_ui()
	_update_arena_master_ui()

@rpc("authority", "reliable")
func _rpc_update_money(peer_money: Dictionary) -> void:
	_update_money_local(peer_money)

# --- Win condition ---
func _check_win(a1: int, a2: int) -> void:
	if a1 >= PlayerPrefs.mob_win_count:
		_rpc_game_over(1)
		_rpc_game_over.rpc(1)
	elif a2 >= PlayerPrefs.mob_win_count:
		_rpc_game_over(2)
		_rpc_game_over.rpc(2)

func _check_skill_unlocks(a1: int, a2: int) -> void:
	var win_count := PlayerPrefs.mob_win_count
	if win_count <= 0:
		return
	for peer_id in _peer_to_arena:
		var arena: Node2D = _peer_to_arena[peer_id]
		var count := a1 if arena == $Arena1 else a2
		var milestone: int = _player_unlock_milestone.get(peer_id, 0)
		while milestone < SKILL_UNLOCK_THRESHOLDS.size():
			if float(count) / float(win_count) >= SKILL_UNLOCK_THRESHOLDS[milestone]:
				milestone += 1
				_player_unlock_milestone[peer_id] = milestone
				_player_unlocks_pending[peer_id] = _player_unlocks_pending.get(peer_id, 0) + 1
				if not _networked or peer_id == 1:
					_rpc_notify_skill_unlock_available()
				else:
					_rpc_notify_skill_unlock_available.rpc_id(peer_id)
			else:
				break

func _apply_skill_unlock(peer_id: int, skill_index: int) -> void:
	var pending: int = _player_unlocks_pending.get(peer_id, 0)
	if pending <= 0 or skill_index < 0 or skill_index >= 3:
		return
	if not _player_skills_unlocked.has(peer_id):
		_player_skills_unlocked[peer_id] = [false, false, false]
	var unlocked: Array = _player_skills_unlocked[peer_id]
	if unlocked[skill_index]:
		return
	unlocked[skill_index] = true
	_player_unlocks_pending[peer_id] = pending - 1
	var player = _peer_to_player.get(peer_id)
	if player and is_instance_valid(player):
		player.skills_unlocked = unlocked
		if _networked and peer_id != 1:
			player.rpc_sync_skills_unlocked.rpc_id(peer_id, unlocked)
	if not _networked or peer_id == 1:
		_rpc_sync_skill_unlocks(unlocked)
	else:
		_rpc_sync_skill_unlocks.rpc_id(peer_id, unlocked)
	if _player_unlocks_pending[peer_id] > 0:
		if not _networked or peer_id == 1:
			_rpc_notify_skill_unlock_available()
		else:
			_rpc_notify_skill_unlock_available.rpc_id(peer_id)

@rpc("authority", "reliable")
func _rpc_notify_skill_unlock_available() -> void:
	var my_id: int = 1 if not _networked else multiplayer.get_unique_id()
	var unlocked: Array = _player_skills_unlocked.get(my_id, [false, false, false])
	var bar := $HUD/SkillBar
	for i in 3:
		if not unlocked[i]:
			bar.get_node("Skill%dSlot" % (i + 1)).set_unlock_available(true)

@rpc("any_peer", "reliable")
func _rpc_request_skill_unlock(skill_index: int) -> void:
	if not multiplayer.is_server():
		return
	_apply_skill_unlock(multiplayer.get_remote_sender_id(), skill_index)

@rpc("authority", "reliable")
func _rpc_sync_skill_unlocks(unlocked: Array) -> void:
	var my_id: int = 1 if not _networked else multiplayer.get_unique_id()
	_player_skills_unlocked[my_id] = unlocked
	var bar := $HUD/SkillBar
	for i in 3:
		var slot = bar.get_node("Skill%dSlot" % (i + 1))
		slot.set_locked(not unlocked[i])
		if unlocked[i]:
			slot.set_unlock_available(false)
	_update_shop_ui()

@rpc("authority", "reliable")
func _rpc_game_over(losing_arena_id: int) -> void:
	if $GameOverOverlay.visible:
		return
	for child in $PlayerContainer.get_children():
		child.set_physics_process(false)

	var my_id: int = 1 if not _networked else multiplayer.get_unique_id()

	var vbox := $GameOverOverlay/VBox
	var title := vbox.get_node("TitleLabel")
	var sub := vbox.get_node("SubLabel")
	var return_btn := vbox.get_node("ReturnButton")

	if _spectator_peer_ids.has(my_id):
		title.text = "GAME OVER"
		title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		sub.text = "Arena %d was overrun by mobs." % losing_arena_id
		sub.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5))
	else:
		var my_is_arena1: bool = _peer_to_arena.get(my_id) == $Arena1
		var i_lost: bool = (losing_arena_id == 1 and my_is_arena1) \
			or (losing_arena_id == 2 and not my_is_arena1)
		if i_lost:
			title.text = "YOU LOSE!"
			title.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
			sub.text = "Your arena was overrun by mobs."
			sub.add_theme_color_override("font_color", Color(0.75, 0.4, 0.4))
		else:
			title.text = "YOU WIN!"
			title.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3))
			sub.text = "You kept your arena clear!"
			sub.add_theme_color_override("font_color", Color(0.4, 0.8, 0.5))

	var existing := vbox.find_child("GameOverScoreboard", false, false)
	if existing:
		existing.free()

	if not _networked or multiplayer.is_server():
		_peer_stats_cache = _gather_stats()

	var sb := _build_game_over_scoreboard(my_id)
	sb.name = "GameOverScoreboard"
	vbox.add_child(sb)
	vbox.move_child(return_btn, vbox.get_child_count() - 1)

	$GameOverOverlay.visible = true

func _on_return_pressed() -> void:
	_leaving = true
	_leave_game()

func _make_archetype(arch_id: int) -> ArchetypeBase:
	match arch_id:
		Constants.ARCHETYPE_PALADIN:  return ArchetypePaladin.new()
		Constants.ARCHETYPE_PIRATE:   return ArchetypePirate.new()
		Constants.ARCHETYPE_MAGE:     return ArchetypeMage.new()
		Constants.ARCHETYPE_CYBORG:   return ArchetypeCyborg.new()
		Constants.ARCHETYPE_ASSASSIN: return ArchetypeAssassin.new()
		Constants.ARCHETYPE_BERSERKER: return ArchetypeBerserker.new()
		Constants.ARCHETYPE_WARLOCK:  return ArchetypeWarlock.new()
	return ArchetypeBase.new()

func _setup_skill_bar() -> void:
	var bar := $HUD/SkillBar
	var arch := _make_archetype(PlayerPrefs.archetype)
	var attack_slot := bar.get_node("AttackSlot")
	attack_slot.key_text = "SPC"
	var arch_attack_icon: Texture2D = arch.get_attack_icon()
	if arch_attack_icon:
		attack_slot.icon_color = arch.get_attack_color()
		attack_slot.icon = arch_attack_icon
	else:
		attack_slot.icon_color = Color(0.9, 0.65, 0.15)
		attack_slot.icon = load("res://assets/icons/broadsword.png")
	attack_slot.tooltip_text = "Attack\n" + arch.get_attack_description()
	var dash_slot := bar.get_node("DashSlot")
	dash_slot.key_text = "SHF"
	var dash_icon: Texture2D = arch.get_dash_icon()
	if dash_icon:
		dash_slot.icon_color = arch.get_dash_color()
		dash_slot.icon = dash_icon
	else:
		dash_slot.icon_color = Color(0.25, 0.55, 1.0)
		dash_slot.icon = load("res://assets/icons/boots.png")
	dash_slot.tooltip_text = "Dash\n" + arch.get_dash_description()
	var s1 := bar.get_node("Skill1Slot")
	var s2 := bar.get_node("Skill2Slot")
	var s3 := bar.get_node("Skill3Slot")
	s1.key_text = "1"
	s2.key_text = "2"
	s3.key_text = "3"
	s1.available = true
	s2.available = true
	s3.available = true
	s1.set_locked(true)
	s2.set_locked(true)
	s3.set_locked(true)
	s1.icon_color = arch.get_skill1_color()
	s1.icon = arch.get_skill1_icon()
	s2.icon_color = arch.get_skill2_color()
	s2.icon = arch.get_skill2_icon()
	s3.icon_color = arch.get_skill3_color()
	s3.icon = arch.get_skill3_icon()
	s1.tooltip_text = arch.get_skill1_name() + "\n" + arch.get_skill1_description()
	s2.tooltip_text = arch.get_skill2_name() + "\n" + arch.get_skill2_description()
	s3.tooltip_text = arch.get_skill3_name() + "\n" + arch.get_skill3_description()
	for i in 3:
		var idx := i
		bar.get_node("Skill%dSlot" % (i + 1)).unlock_requested.connect(
			func(): _on_skill_unlock_requested(idx)
		)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.is_echo():
		return
	if not event.ctrl_pressed:
		return
	var idx := -1
	match event.physical_keycode:
		KEY_1: idx = 0
		KEY_2: idx = 1
		KEY_3: idx = 2
	if idx < 0:
		return
	var slot = $HUD/SkillBar.get_node("Skill%dSlot" % (idx + 1))
	if slot.unlock_available:
		get_viewport().set_input_as_handled()
		_on_skill_unlock_requested(idx)

func _process(delta: float) -> void:
	if _fps_label != null:
		_fps_timer -= delta
		if _fps_timer <= 0.0:
			_fps_timer = 0.25
			_fps_label.text = "%d fps" % int(Engine.get_frames_per_second())
	if _leaving:
		return
	if _networked:
		_update_host_liveness(delta)
	if _scoreboard_panel != null and _spectator_camera == null:
		var want_visible := Input.is_action_pressed("scoreboard")
		if want_visible != _scoreboard_panel.visible:
			_scoreboard_panel.visible = want_visible
			if want_visible:
				_refresh_scoreboard()
	var my_id: int = 1 if not _networked else multiplayer.get_unique_id()
	var player = _peer_to_player.get(my_id)
	if player == null:
		return
	var bar := $HUD/SkillBar
	var attack_node = bar.get_node("AttackSlot")
	attack_node.set_cooldown(player.attack_cooldown, Constants.SWORD_SWING_DURATION)
	var p_arch: ArchetypeBase = player.get_archetype_handler()
	var dyn_icon: Texture2D = p_arch.get_attack_icon()
	if dyn_icon:
		attack_node.icon = dyn_icon
		attack_node.icon_color = p_arch.get_attack_color()
	var dash_slot = bar.get_node("DashSlot")
	dash_slot.set_cooldown(player.dash_cooldown, Constants.PLAYER_DASH_COOLDOWN)
	var no_dash_active: bool = player.debuff_no_dash_timer > 0.0
	if dash_slot.debuffed != no_dash_active:
		dash_slot.debuffed = no_dash_active
		dash_slot.queue_redraw()
	var silence_active: bool = player.debuff_silence_timer > 0.0
	var s1_node = bar.get_node("Skill1Slot")
	var s2_node = bar.get_node("Skill2Slot")
	s1_node.set_cooldown(player.skill1_cooldown, player.skill1_max_cooldown)
	s2_node.set_cooldown(player.skill2_cooldown, player.skill2_max_cooldown)
	if s1_node.debuffed != silence_active:
		s1_node.debuffed = silence_active
		s1_node.queue_redraw()
	if s2_node.debuffed != silence_active:
		s2_node.debuffed = silence_active
		s2_node.queue_redraw()
	var s3_node = bar.get_node("Skill3Slot")
	s3_node.set_cooldown(player.skill3_cooldown, player.skill3_max_cooldown)
	s3_node.set_passive_counter(player.get_passive_counter())
	if s3_node.debuffed != silence_active:
		s3_node.debuffed = silence_active
		s3_node.queue_redraw()
	if _networked and not multiplayer.is_server() and _ping_label != null:
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_ping_timer = 2.0
			_ping_send_time = Time.get_ticks_msec()
			_rpc_ping_request.rpc_id(1)

func _on_player_entered_shop() -> void:
	if _leaving:
		return
	_in_shop_zone = true
	$ShopPanel.visible = true
	_update_shop_ui()

func _on_player_exited_shop() -> void:
	_in_shop_zone = false
	$ShopPanel.visible = false

func _on_player_entered_arena_master() -> void:
	if _leaving:
		return
	_in_arena_master_zone = true
	$ArenaMasterPanel.visible = true
	_update_arena_master_ui()

func _on_player_exited_arena_master() -> void:
	_in_arena_master_zone = false
	$ArenaMasterPanel.visible = false

func _upgrade_cost(base: int, inc: int, current_level: int) -> int:
	return base + current_level * inc

func _setup_shop() -> void:
	var upgrade_vbox := $ShopPanel/PanelBG/VBox
	upgrade_vbox.get_node("SpeedBtn").pressed.connect(func(): _buy(3))
	upgrade_vbox.get_node("DamageBtn").pressed.connect(func(): _buy(4))
	upgrade_vbox.get_node("SwordSizeBtn").pressed.connect(func(): _buy(5))
	upgrade_vbox.get_node("AttackSpeedBtn").pressed.connect(func(): _buy(6))
	upgrade_vbox.get_node("Skill1Btn").pressed.connect(func(): _buy(12))
	upgrade_vbox.get_node("Skill2Btn").pressed.connect(func(): _buy(13))
	upgrade_vbox.get_node("Skill3Btn").pressed.connect(func(): _buy(14))
	var am_vbox := $ArenaMasterPanel/PanelBG/VBox
	am_vbox.get_node("SendMobBtn").pressed.connect(func(): _buy(0))
	am_vbox.get_node("Send3MobsBtn").pressed.connect(func(): _buy(1))
	am_vbox.get_node("SendFleeingBtn").pressed.connect(func(): _buy(2))
	am_vbox.get_node("SendBossBtn").pressed.connect(func(): _buy(7))
	am_vbox.get_node("UpgradeMobsBtn").pressed.connect(func(): _buy(15))
	am_vbox.get_node("DebuffNoDashBtn").pressed.connect(func(): _buy(Constants.DEBUFF_NO_DASH))
	am_vbox.get_node("DebuffFrenzyBtn").pressed.connect(func(): _buy(Constants.DEBUFF_FRENZY))
	am_vbox.get_node("DebuffSilenceBtn").pressed.connect(func(): _buy(Constants.DEBUFF_SILENCE))
	am_vbox.get_node("DebuffInvertBtn").pressed.connect(func(): _buy(Constants.DEBUFF_INVERT))


func _update_shop_ui() -> void:
	if not $ShopPanel.visible:
		return
	var my_id: int = 1 if not _networked else multiplayer.get_unique_id()
	var money: int = _peer_money.get(my_id, 0)
	var max_lvl := Constants.SHOP_UPGRADE_MAX_LEVEL
	var vbox := $ShopPanel/PanelBG/VBox
	_refresh_upgrade_btn(vbox.get_node("SpeedBtn"), "Speed",
		_player_speed_levels.get(my_id, 0), max_lvl, money,
		Constants.SHOP_COST_SPEED_BASE, Constants.SHOP_COST_SPEED_INC)
	_refresh_upgrade_btn(vbox.get_node("DamageBtn"), "Damage",
		_player_damage_levels.get(my_id, 0), max_lvl, money,
		Constants.SHOP_COST_DAMAGE_BASE, Constants.SHOP_COST_DAMAGE_INC)
	_refresh_upgrade_btn(vbox.get_node("SwordSizeBtn"), "Sword Size",
		_player_sword_size_levels.get(my_id, 0), max_lvl, money,
		Constants.SHOP_COST_SWORD_SIZE_BASE, Constants.SHOP_COST_SWORD_SIZE_INC)
	_refresh_upgrade_btn(vbox.get_node("AttackSpeedBtn"), "Attack Speed",
		_player_attack_speed_levels.get(my_id, 0), max_lvl, money,
		Constants.SHOP_COST_ATTACK_SPEED_BASE, Constants.SHOP_COST_ATTACK_SPEED_INC)
	var player = _peer_to_player.get(my_id)
	var skill_level_dicts := [_player_skill1_levels, _player_skill2_levels, _player_skill3_levels]
	var unlocked_arr: Array = _player_skills_unlocked.get(my_id, [false, false, false])
	for i in range(1, 4):
		var skill_label: String = player.get_skill_name(i) if player else ("Skill %d" % i)

		var btn: Button = vbox.get_node("Skill%dBtn" % i)
		if not unlocked_arr[i - 1]:
			btn.text = "%s - Locked" % skill_label
			btn.disabled = true
		else:
			_refresh_upgrade_btn(btn, skill_label,
				skill_level_dicts[i - 1].get(my_id, 0), max_lvl, money,
				Constants.SHOP_COST_SKILL_BASE, Constants.SHOP_COST_SKILL_INC)

func _on_skill_unlock_requested(skill_index: int) -> void:
	var bar := $HUD/SkillBar
	for i in 3:
		bar.get_node("Skill%dSlot" % (i + 1)).set_unlock_available(false)
	if _networked and not multiplayer.is_server():
		_rpc_request_skill_unlock.rpc_id(1, skill_index)
	else:
		_apply_skill_unlock(1, skill_index)

func _update_arena_master_ui() -> void:
	if not $ArenaMasterPanel.visible:
		return
	var my_id: int = 1 if not _networked else multiplayer.get_unique_id()
	var money: int = _peer_money.get(my_id, 0)
	var vbox := $ArenaMasterPanel/PanelBG/VBox
	vbox.get_node("SendMobBtn").disabled = money < Constants.SHOP_COST_SEND_MOB
	vbox.get_node("Send3MobsBtn").disabled = money < Constants.SHOP_COST_SEND_3_MOBS
	vbox.get_node("SendFleeingBtn").disabled = money < Constants.SHOP_COST_SEND_FLEEING
	vbox.get_node("SendBossBtn").disabled = money < Constants.SHOP_COST_SEND_BOSS
	vbox.get_node("UpgradeMobsBtn").disabled = money < Constants.SHOP_COST_UPGRADE_MOBS
	vbox.get_node("DebuffNoDashBtn").disabled = money < Constants.DEBUFF_COST_NO_DASH
	vbox.get_node("DebuffFrenzyBtn").disabled = money < Constants.DEBUFF_COST_FRENZY
	vbox.get_node("DebuffSilenceBtn").disabled = money < Constants.DEBUFF_COST_SILENCE
	vbox.get_node("DebuffInvertBtn").disabled = money < Constants.DEBUFF_COST_INVERT

func _refresh_upgrade_btn(btn: Button, label: String, lvl: int, max_lvl: int, money: int, base: int, inc: int) -> void:
	var cost := _upgrade_cost(base, inc, lvl)
	btn.text = "%s (Lv %d/%d)   $%d" % [label, lvl, max_lvl, cost]
	btn.disabled = lvl >= max_lvl or money < cost


func _buy(item_id: int) -> void:
	if _networked and not multiplayer.is_server():
		_rpc_request_purchase.rpc_id(1, item_id)
	else:
		_apply_purchase(1 if not _networked else multiplayer.get_unique_id(), item_id)

@rpc("any_peer", "reliable")
func _rpc_request_purchase(item_id: int) -> void:
	if not multiplayer.is_server():
		return
	_apply_purchase(multiplayer.get_remote_sender_id(), item_id)

func _apply_purchase(peer_id: int, item_id: int) -> void:
	if _leaving:
		return
	var is_a1: bool = _peer_to_arena.get(peer_id) == $Arena1
	var money: int = _peer_money.get(peer_id, 0)
	var opponent_arena: Node2D = $Arena2 if is_a1 else $Arena1

	match item_id:
		0:
			if money < Constants.SHOP_COST_SEND_MOB:
				return
			money -= Constants.SHOP_COST_SEND_MOB
			opponent_arena.spawn_mob()
			_peer_mobs_sent[peer_id] = _peer_mobs_sent.get(peer_id, 0) + 1
		1:
			if money < Constants.SHOP_COST_SEND_3_MOBS:
				return
			money -= Constants.SHOP_COST_SEND_3_MOBS
			for i in 3:
				opponent_arena.spawn_mob()
			_peer_mobs_sent[peer_id] = _peer_mobs_sent.get(peer_id, 0) + 3
		2:
			if money < Constants.SHOP_COST_SEND_FLEEING:
				return
			money -= Constants.SHOP_COST_SEND_FLEEING
			opponent_arena.spawn_mob(1)
			_peer_mobs_sent[peer_id] = _peer_mobs_sent.get(peer_id, 0) + 1
		7:
			if money < Constants.SHOP_COST_SEND_BOSS:
				return
			money -= Constants.SHOP_COST_SEND_BOSS
			opponent_arena.spawn_mob(2)
			_peer_mobs_sent[peer_id] = _peer_mobs_sent.get(peer_id, 0) + 1
		15:
			if money < Constants.SHOP_COST_UPGRADE_MOBS:
				return
			money -= Constants.SHOP_COST_UPGRADE_MOBS
			for mob in opponent_arena.get_node("MobContainer").get_children():
				mob.max_health += Constants.SHOP_MOB_HEALTH_BONUS
				mob.health += Constants.SHOP_MOB_HEALTH_BONUS
		3:
			var cur_level: int = _player_speed_levels.get(peer_id, 0)
			var cost := _upgrade_cost(Constants.SHOP_COST_SPEED_BASE, Constants.SHOP_COST_SPEED_INC, cur_level)
			if cur_level >= Constants.SHOP_UPGRADE_MAX_LEVEL or money < cost:
				return
			money -= cost
			var new_level: int = cur_level + 1
			_player_speed_levels[peer_id] = new_level
			var player = _peer_to_player.get(peer_id)
			if player and is_instance_valid(player):
				player.speed_level = new_level
				if _networked and peer_id != 1:
					player.rpc_apply_speed_level.rpc_id(peer_id, new_level)
			if _networked and peer_id != 1:
				_rpc_sync_speed_level.rpc_id(peer_id, new_level)
		4:
			var cur_level: int = _player_damage_levels.get(peer_id, 0)
			var cost := _upgrade_cost(Constants.SHOP_COST_DAMAGE_BASE, Constants.SHOP_COST_DAMAGE_INC, cur_level)
			if cur_level >= Constants.SHOP_UPGRADE_MAX_LEVEL or money < cost:
				return
			money -= cost
			var new_level: int = cur_level + 1
			_player_damage_levels[peer_id] = new_level
			var player = _peer_to_player.get(peer_id)
			if player and is_instance_valid(player):
				player.damage_level = new_level
				player.apply_upgrades_to_sword()
				if _networked and peer_id != 1:
					player.rpc_apply_damage_level.rpc_id(peer_id, new_level)
		5:
			var cur_level: int = _player_sword_size_levels.get(peer_id, 0)
			var cost := _upgrade_cost(
				Constants.SHOP_COST_SWORD_SIZE_BASE, Constants.SHOP_COST_SWORD_SIZE_INC, cur_level
			)
			if cur_level >= Constants.SHOP_UPGRADE_MAX_LEVEL or money < cost:
				return
			money -= cost
			var new_level: int = cur_level + 1
			_player_sword_size_levels[peer_id] = new_level
			var player = _peer_to_player.get(peer_id)
			if player and is_instance_valid(player):
				player.sword_size_level = new_level
				player.apply_upgrades_to_sword()
				if _networked and peer_id != 1:
					player.rpc_apply_sword_size_level.rpc_id(peer_id, new_level)
		6:
			var cur_level: int = _player_attack_speed_levels.get(peer_id, 0)
			var cost := _upgrade_cost(
				Constants.SHOP_COST_ATTACK_SPEED_BASE, Constants.SHOP_COST_ATTACK_SPEED_INC, cur_level
			)
			if cur_level >= Constants.SHOP_UPGRADE_MAX_LEVEL or money < cost:
				return
			money -= cost
			var new_level: int = cur_level + 1
			_player_attack_speed_levels[peer_id] = new_level
			var player = _peer_to_player.get(peer_id)
			if player and is_instance_valid(player):
				player.attack_speed_level = new_level
				player.apply_upgrades_to_sword()
				if _networked and peer_id != 1:
					player.rpc_apply_attack_speed_level.rpc_id(peer_id, new_level)
		12:
			if not _player_skills_unlocked.get(peer_id, [false, false, false])[0]:
				return
			var cur_level: int = _player_skill1_levels.get(peer_id, 0)
			var cost := _upgrade_cost(Constants.SHOP_COST_SKILL_BASE, Constants.SHOP_COST_SKILL_INC, cur_level)
			if cur_level >= Constants.SHOP_UPGRADE_MAX_LEVEL or money < cost:
				return
			money -= cost
			var new_level: int = cur_level + 1
			_player_skill1_levels[peer_id] = new_level
			var player = _peer_to_player.get(peer_id)
			if player and is_instance_valid(player):
				player.skill1_level = new_level
				player.apply_skill_upgrades()
				if _networked and peer_id != 1:
					player.rpc_apply_skill1_level.rpc_id(peer_id, new_level)
			if _networked and peer_id != 1:
				_rpc_sync_skill1_level.rpc_id(peer_id, new_level)
		13:
			if not _player_skills_unlocked.get(peer_id, [false, false, false])[1]:
				return
			var cur_level: int = _player_skill2_levels.get(peer_id, 0)
			var cost := _upgrade_cost(Constants.SHOP_COST_SKILL_BASE, Constants.SHOP_COST_SKILL_INC, cur_level)
			if cur_level >= Constants.SHOP_UPGRADE_MAX_LEVEL or money < cost:
				return
			money -= cost
			var new_level: int = cur_level + 1
			_player_skill2_levels[peer_id] = new_level
			var player = _peer_to_player.get(peer_id)
			if player and is_instance_valid(player):
				player.skill2_level = new_level
				player.apply_skill_upgrades()
				if _networked and peer_id != 1:
					player.rpc_apply_skill2_level.rpc_id(peer_id, new_level)
			if _networked and peer_id != 1:
				_rpc_sync_skill2_level.rpc_id(peer_id, new_level)
		14:
			if not _player_skills_unlocked.get(peer_id, [false, false, false])[2]:
				return
			var cur_level: int = _player_skill3_levels.get(peer_id, 0)
			var cost := _upgrade_cost(Constants.SHOP_COST_SKILL_BASE, Constants.SHOP_COST_SKILL_INC, cur_level)
			if cur_level >= Constants.SHOP_UPGRADE_MAX_LEVEL or money < cost:
				return
			money -= cost
			var new_level: int = cur_level + 1
			_player_skill3_levels[peer_id] = new_level
			var player = _peer_to_player.get(peer_id)
			if player and is_instance_valid(player):
				player.skill3_level = new_level
				player.apply_skill_upgrades()
				if _networked and peer_id != 1:
					player.rpc_apply_skill3_level.rpc_id(peer_id, new_level)
			if _networked and peer_id != 1:
				_rpc_sync_skill3_level.rpc_id(peer_id, new_level)
		Constants.DEBUFF_NO_DASH, Constants.DEBUFF_SILENCE, Constants.DEBUFF_INVERT:
			var cost_map := {
				Constants.DEBUFF_NO_DASH: Constants.DEBUFF_COST_NO_DASH,
				Constants.DEBUFF_SILENCE: Constants.DEBUFF_COST_SILENCE,
				Constants.DEBUFF_INVERT:  Constants.DEBUFF_COST_INVERT,
			}
			var dur_map := {
				Constants.DEBUFF_NO_DASH: Constants.DEBUFF_DUR_NO_DASH,
				Constants.DEBUFF_SILENCE: Constants.DEBUFF_DUR_SILENCE,
				Constants.DEBUFF_INVERT:  Constants.DEBUFF_DUR_INVERT,
			}
			var cost: int = cost_map[item_id]
			if money < cost:
				return
			money -= cost
			var dur: float = dur_map[item_id]
			_apply_debuff_to_opponents(peer_id, item_id, dur)
			_peer_debuffs_applied[peer_id] = _peer_debuffs_applied.get(peer_id, 0) + 1
		Constants.DEBUFF_FRENZY:
			if money < Constants.DEBUFF_COST_FRENZY:
				return
			money -= Constants.DEBUFF_COST_FRENZY
			opponent_arena.mob_speed_multiplier = Constants.DEBUFF_FRENZY_SPEED_MULT
			opponent_arena.mob_frenzy_timer = Constants.DEBUFF_DUR_FRENZY
			if _networked:
				opponent_arena.rpc_set_frenzy.rpc(Constants.DEBUFF_FRENZY_SPEED_MULT, Constants.DEBUFF_DUR_FRENZY)
			_notify_opponents_debuff_icon(peer_id, Constants.DEBUFF_FRENZY, Constants.DEBUFF_DUR_FRENZY)
			_peer_debuffs_applied[peer_id] = _peer_debuffs_applied.get(peer_id, 0) + 1

	_peer_money[peer_id] = money
	_update_money_local(_peer_money)
	if _networked:
		_rpc_update_money.rpc(_peer_money)
	_push_hud_update()
	var _s := _gather_stats()
	_peer_stats_cache = _s
	if _networked:
		_rpc_update_stats.rpc(_s)

@rpc("authority", "reliable")
func _rpc_sync_speed_level(level: int) -> void:
	var my_id: int = multiplayer.get_unique_id()
	_player_speed_levels[my_id] = level
	_update_shop_ui()

@rpc("authority", "reliable")
func _rpc_sync_skill1_level(level: int) -> void:
	var my_id: int = multiplayer.get_unique_id()
	_player_skill1_levels[my_id] = level
	_update_shop_ui()

@rpc("authority", "reliable")
func _rpc_sync_skill2_level(level: int) -> void:
	var my_id: int = multiplayer.get_unique_id()
	_player_skill2_levels[my_id] = level
	_update_shop_ui()

@rpc("authority", "reliable")
func _rpc_sync_skill3_level(level: int) -> void:
	var my_id: int = multiplayer.get_unique_id()
	_player_skill3_levels[my_id] = level
	_update_shop_ui()

func _apply_debuff_to_opponents(buyer_id: int, item_id: int, dur: float) -> void:
	var my_arena = _peer_to_arena.get(buyer_id)
	for opp_id in _peer_to_player:
		if _peer_to_arena.get(opp_id) == my_arena:
			continue
		var opp_player = _peer_to_player.get(opp_id)
		if not opp_player or not is_instance_valid(opp_player):
			continue
		opp_player.rpc_apply_debuff(item_id, dur)
		if _networked and opp_id != 1:
			opp_player.rpc_apply_debuff.rpc_id(opp_id, item_id, dur)
		_notify_debuff_icon(opp_id, item_id, dur)

func _notify_opponents_debuff_icon(buyer_id: int, item_id: int, dur: float) -> void:
	var my_arena = _peer_to_arena.get(buyer_id)
	for opp_id in _peer_to_player:
		if _peer_to_arena.get(opp_id) != my_arena:
			_notify_debuff_icon(opp_id, item_id, dur)

func _notify_debuff_icon(target_id: int, item_id: int, dur: float) -> void:
	if not _networked or target_id == 1:
		_add_debuff_icon(item_id, dur)
	else:
		_rpc_show_debuff_received.rpc_id(target_id, item_id, dur)

@rpc("authority", "reliable")
func _rpc_show_debuff_received(type: int, duration: float) -> void:
	_add_debuff_icon(type, duration)

func _add_debuff_icon(type: int, duration: float) -> void:
	const DEBUFF_INDICATOR = preload("res://scripts/ui/debuff_indicator.gd")
	const NAMES := {
		Constants.DEBUFF_NO_DASH: "NO DASH",
		Constants.DEBUFF_FRENZY:  "FRENZY",
		Constants.DEBUFF_SILENCE: "SILENCE",
		Constants.DEBUFF_INVERT:  "INVERT",
	}
	const COLORS := {
		Constants.DEBUFF_NO_DASH: Color(0.2, 0.4, 0.9),
		Constants.DEBUFF_FRENZY:  Color(0.75, 0.2, 0.1),
		Constants.DEBUFF_SILENCE: Color(0.55, 0.1, 0.7),
		Constants.DEBUFF_INVERT:  Color(0.85, 0.5, 0.05),
	}
	var bar := $HUD/DebuffBar
	var indicator := DEBUFF_INDICATOR.new()
	indicator.debuff_name = NAMES.get(type, "?")
	indicator.icon_color = COLORS.get(type, Color(0.6, 0.1, 0.1))
	indicator.time_remaining = duration
	bar.add_child(indicator)

# --- Stats ---

func _gather_stats() -> Dictionary:
	var result := {}
	for pid in _peer_to_arena:
		result[pid] = {
			"kills":     _peer_kills.get(pid, 0),
			"earned":    _peer_money_earned.get(pid, 0),
			"mobs_sent": _peer_mobs_sent.get(pid, 0),
			"debuffs":   _peer_debuffs_applied.get(pid, 0),
		}
	return result

@rpc("authority", "reliable")
func _rpc_update_stats(stats: Dictionary) -> void:
	_peer_stats_cache = stats

# --- Scoreboard overlay ---

func _setup_scoreboard() -> void:
	var panel := ColorRect.new()
	panel.name = "ScoreboardOverlay"
	panel.color = Color(0.05, 0.05, 0.1, 0.88)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.visible = false

	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_top", 50)
	outer.add_theme_constant_override("margin_bottom", 50)
	outer.add_theme_constant_override("margin_left", 80)
	outer.add_theme_constant_override("margin_right", 80)
	panel.add_child(outer)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	outer.add_child(root_vbox)

	var title := Label.new()
	title.text = "SCOREBOARD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3))
	root_vbox.add_child(title)

	var sep := HSeparator.new()
	root_vbox.add_child(sep)

	var cols_hbox := HBoxContainer.new()
	cols_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols_hbox.add_theme_constant_override("separation", 16)
	root_vbox.add_child(cols_hbox)

	var col1 := VBoxContainer.new()
	col1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col1.add_theme_constant_override("separation", 8)
	cols_hbox.add_child(col1)

	var vsep := VSeparator.new()
	vsep.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols_hbox.add_child(vsep)

	var col2 := VBoxContainer.new()
	col2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col2.add_theme_constant_override("separation", 8)
	cols_hbox.add_child(col2)

	var hint := Label.new()
	hint.text = "Hold TAB / Select button"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.8))
	root_vbox.add_child(hint)

	$HUD.add_child(panel)
	_scoreboard_panel = panel
	_scoreboard_col1 = col1
	_scoreboard_col2 = col2

func _build_game_over_scoreboard(my_id: int) -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var sep_top := HSeparator.new()
	container.add_child(sep_top)

	var cols_hbox := HBoxContainer.new()
	cols_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols_hbox.add_theme_constant_override("separation", 16)
	container.add_child(cols_hbox)

	var my_arena = _peer_to_arena.get(my_id)

	var col1 := VBoxContainer.new()
	col1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col1.add_theme_constant_override("separation", 8)
	cols_hbox.add_child(col1)

	var vsep := VSeparator.new()
	vsep.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols_hbox.add_child(vsep)

	var col2 := VBoxContainer.new()
	col2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col2.add_theme_constant_override("separation", 8)
	cols_hbox.add_child(col2)

	_add_scoreboard_column_header(col1, "YOUR ARENA", Color(0.3, 0.75, 1.0))
	_add_scoreboard_column_header(col2, "ENEMY ARENA", Color(1.0, 0.42, 0.42))

	for pid in _peer_to_arena:
		var in_my_arena: bool = my_arena != null and _peer_to_arena.get(pid) == my_arena
		var col := col1 if in_my_arena else col2
		var stats: Dictionary = _peer_stats_cache.get(pid, {})
		var pname: String = PlayerPrefs.peer_names.get(pid, "Player")
		if pname.is_empty():
			pname = "Player"
		var arch_id: int = _peer_to_archetype.get(pid, 0)
		var arch_name: String = Constants.ARCHETYPE_NAMES[arch_id] \
			if arch_id >= 0 and arch_id < Constants.ARCHETYPE_NAMES.size() else "?"
		_add_scoreboard_player_row(col, pname, arch_name, stats, pid == my_id)
	for ghost in _ghost_players:
		var in_my_arena: bool = my_arena != null and ghost["arena"] == my_arena
		var col := col1 if in_my_arena else col2
		var pname: String = ghost["name"]
		if pname.is_empty():
			pname = "Player"
		var arch_id: int = ghost["arch_id"]
		var arch_name: String = Constants.ARCHETYPE_NAMES[arch_id] \
			if arch_id >= 0 and arch_id < Constants.ARCHETYPE_NAMES.size() else "?"
		_add_scoreboard_player_row(col, pname + " (left)", arch_name, ghost["stats"], false)

	var sep_bot := HSeparator.new()
	container.add_child(sep_bot)

	return container

func _refresh_scoreboard() -> void:
	if not _networked or multiplayer.is_server():
		_peer_stats_cache = _gather_stats()
	for child in _scoreboard_col1.get_children():
		child.free()
	for child in _scoreboard_col2.get_children():
		child.free()

	var my_id: int = 1 if not _networked else multiplayer.get_unique_id()
	var my_arena = _peer_to_arena.get(my_id)

	_add_scoreboard_column_header(_scoreboard_col1, "YOUR ARENA", Color(0.3, 0.75, 1.0))
	_add_scoreboard_column_header(_scoreboard_col2, "ENEMY ARENA", Color(1.0, 0.42, 0.42))

	for pid in _peer_to_arena:
		var in_my_arena: bool = my_arena != null and _peer_to_arena.get(pid) == my_arena
		var col := _scoreboard_col1 if in_my_arena else _scoreboard_col2
		var stats: Dictionary = _peer_stats_cache.get(pid, {})
		var pname: String = PlayerPrefs.peer_names.get(pid, "Player")
		if pname.is_empty():
			pname = "Player"
		var arch_id: int = _peer_to_archetype.get(pid, 0)
		var arch_name: String = Constants.ARCHETYPE_NAMES[arch_id] \
			if arch_id >= 0 and arch_id < Constants.ARCHETYPE_NAMES.size() else "?"
		_add_scoreboard_player_row(col, pname, arch_name, stats, pid == my_id)
	for ghost in _ghost_players:
		var in_my_arena: bool = my_arena != null and ghost["arena"] == my_arena
		var col := _scoreboard_col1 if in_my_arena else _scoreboard_col2
		var pname: String = ghost["name"]
		if pname.is_empty():
			pname = "Player"
		var arch_id: int = ghost["arch_id"]
		var arch_name: String = Constants.ARCHETYPE_NAMES[arch_id] \
			if arch_id >= 0 and arch_id < Constants.ARCHETYPE_NAMES.size() else "?"
		_add_scoreboard_player_row(col, pname + " (left)", arch_name, ghost["stats"], false)

func _add_scoreboard_column_header(col: VBoxContainer, label_text: String, col_color: Color) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", col_color)
	col.add_child(lbl)
	var sep := HSeparator.new()
	col.add_child(sep)

func _add_scoreboard_player_row(col: VBoxContainer, pname: String, arch_name: String, stats: Dictionary, is_local: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)

	var name_vbox := VBoxContainer.new()
	name_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(name_vbox)

	var name_lbl := Label.new()
	name_lbl.text = pname + (" (You)" if is_local else "")
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5) if is_local else Color(1.0, 1.0, 1.0))
	name_vbox.add_child(name_lbl)

	var arch_lbl := Label.new()
	arch_lbl.text = arch_name
	arch_lbl.add_theme_font_size_override("font_size", 11)
	arch_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	name_vbox.add_child(arch_lbl)

	var stat_cols := [
		["K",       str(stats.get("kills", 0))],
		["G",       "$%d" % stats.get("earned", 0)],
		["Sent",    str(stats.get("mobs_sent", 0))],
		["Debuffs", str(stats.get("debuffs", 0))],
	]
	for sc in stat_cols:
		var cell := VBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.custom_minimum_size = Vector2(62, 0)
		row.add_child(cell)
		var val_lbl := Label.new()
		val_lbl.text = sc[1]
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val_lbl.add_theme_font_size_override("font_size", 15)
		cell.add_child(val_lbl)
		var key_lbl := Label.new()
		key_lbl.text = sc[0]
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_lbl.add_theme_font_size_override("font_size", 10)
		key_lbl.add_theme_color_override("font_color", Color(0.58, 0.58, 0.58))
		cell.add_child(key_lbl)
