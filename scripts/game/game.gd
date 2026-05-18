extends Node

const PLAYER_SCENE = preload("res://scenes/entities/player.tscn")

var _peer_to_arena: Dictionary = {}
var _peer_to_player: Dictionary = {}
var _networked: bool = false
var _leaving: bool = false
var _scrubbed: bool = false

func _ready() -> void:
	_networked = not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	_setup_skill_bar()

	if not _networked:
		_peer_to_arena[1] = $Arena1
		_spawn_player(1)
		for i in Constants.MOB_COUNT:
			$Arena1.spawn_mob()
		_push_hud_update()
		return

	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		_peer_to_arena[1] = $Arena1
	else:
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		await get_tree().process_frame
		_rpc_client_ready.rpc_id(1)

@rpc("any_peer", "reliable")
func _rpc_client_ready() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	_peer_to_arena[id] = $Arena2
	for i in Constants.MOB_COUNT:
		$Arena1.spawn_mob()
	for i in Constants.MOB_COUNT:
		$Arena2.spawn_mob()
	_spawn_player(1)
	_spawn_player(id)
	_rpc_spawn_players.rpc(id)
	_push_hud_update()

@rpc("authority", "reliable")
func _rpc_spawn_players(client_id: int) -> void:
	_peer_to_arena[1] = $Arena1
	_peer_to_arena[client_id] = $Arena2
	_spawn_player(1)
	_spawn_player(client_id)

func _on_server_disconnected() -> void:
	_scrub_multiplayer_hooks()
	multiplayer.multiplayer_peer = null
	_show_disconnect("Host disconnected. Returning to lobby...")

func _on_peer_disconnected(id: int) -> void:
	if _peer_to_player.has(id):
		_peer_to_player[id].queue_free()
	_peer_to_player.erase(id)
	_peer_to_arena.erase(id)
	_show_disconnect("Player disconnected. Returning to lobby...")

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
	if not multiplayer.is_server() or _leaving:
		return
	var opponent: Node2D = $Arena2 if arena == $Arena1 else $Arena1
	opponent.spawn_mob()
	opponent.spawn_mob()
	# Dying mob not freed yet; subtract 1 from killer's arena count.
	var a1: int = $Arena1.get_mob_count() - (1 if arena == $Arena1 else 0)
	var a2: int = $Arena2.get_mob_count() - (1 if arena == $Arena2 else 0)
	_update_hud_local(a1, a2)
	if _networked:
		_rpc_update_hud.rpc(a1, a2)
	_check_win(a1, a2)

# --- HUD ---

func _push_hud_update() -> void:
	var a1: int = $Arena1.get_mob_count()
	var a2: int = $Arena2.get_mob_count()
	_update_hud_local(a1, a2)
	if _networked and multiplayer.is_server():
		_rpc_update_hud.rpc(a1, a2)

func _update_hud_local(a1: int, a2: int) -> void:
	var my_is_arena1 := (not _networked) or multiplayer.get_unique_id() == 1
	var my    := a1 if my_is_arena1 else a2
	var enemy := a2 if my_is_arena1 else a1
	$HUD/MyLabel.text    = "MY ARENA\n%d / 100" % my
	$HUD/EnemyLabel.text = "ENEMY ARENA\n%d / 100" % enemy

@rpc("authority", "reliable")
func _rpc_update_hud(a1: int, a2: int) -> void:
	_update_hud_local(a1, a2)

# --- Win condition ---
func _check_win(a1: int, a2: int) -> void:
	if a1 >= 100:
		_rpc_game_over(1)
		_rpc_game_over.rpc(1)
	elif a2 >= 100:
		_rpc_game_over(2)
		_rpc_game_over.rpc(2)

@rpc("authority", "reliable")
func _rpc_game_over(losing_arena_id: int) -> void:
	for child in $PlayerContainer.get_children():
		child.set_physics_process(false)

	var my_is_arena1 := (not _networked) or multiplayer.get_unique_id() == 1
	var i_lost: bool = (losing_arena_id == 1 and my_is_arena1) or (losing_arena_id == 2 and not my_is_arena1)

	var title := $GameOverOverlay/VBox/TitleLabel
	if i_lost:
		title.text = "YOU LOSE!"
		title.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	else:
		title.text = "YOU WIN!"
		title.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3))

	$GameOverOverlay.visible = true

func _on_return_pressed() -> void:
	_leaving = true
	_leave_game()

func _setup_skill_bar() -> void:
	var bar := $HUD/SkillBar
	bar.get_node("AttackSlot").key_text = "SPC"
	bar.get_node("AttackSlot").icon_color = Color(0.9, 0.65, 0.15)
	bar.get_node("DashSlot").key_text = "SHF"
	bar.get_node("DashSlot").icon_color = Color(0.25, 0.55, 1.0)
	bar.get_node("Skill1Slot").key_text = "1"
	bar.get_node("Skill1Slot").available = false
	bar.get_node("Skill2Slot").key_text = "2"
	bar.get_node("Skill2Slot").available = false
	bar.get_node("Skill3Slot").key_text = "3"
	bar.get_node("Skill3Slot").available = false

func _process(_delta: float) -> void:
	if _leaving:
		return
	var my_id: int = 1 if not _networked else multiplayer.get_unique_id()
	var player = _peer_to_player.get(my_id)
	if player == null:
		return
	var bar := $HUD/SkillBar
	bar.get_node("AttackSlot").set_cooldown(player.attack_cooldown, Constants.SWORD_SWING_DURATION)
	bar.get_node("DashSlot").set_cooldown(player.dash_cooldown, Constants.PLAYER_DASH_COOLDOWN)
