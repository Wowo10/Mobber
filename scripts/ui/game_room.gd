extends CanvasLayer

const GAME_SCENE = "res://scenes/game/game.tscn"
const LOBBY_SCENE = "res://scenes/ui/lobby.tscn"

var _is_host: bool = false
var _is_web: bool = false
var _team_assignments: Dictionary = {}  # peer_id -> 0 (Team1) or 1 (Team2)
var _peer_rows: Dictionary = {}         # peer_id -> HBoxContainer
var _team_lists: Array                  # [%Team1List, %Team2List]

func _ready() -> void:
	_is_host = multiplayer.is_server()
	_is_web = OS.get_name() == "Web" or Constants.FORCE_WEBRTC
	_team_lists = [%Team1List, %Team2List]
	%StartButton.visible = _is_host
	%StartButton.disabled = true

	if _is_host:
		_team_assignments[1] = 0
		_add_row(1, true, 0)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		if _is_web and not PlayerPrefs.room_code.is_empty():
			%CodeDisplay.text = "Room: %s  [click to copy]" % PlayerPrefs.room_code
			%CodeDisplay.visible = true
	else:
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		await get_tree().process_frame
		_rpc_hello.rpc_id(1)

func _count_team(team: int) -> int:
	var count := 0
	for id in _team_assignments:
		if _team_assignments[id] == team:
			count += 1
	return count

func _auto_assign_team() -> int:
	return 0 if _count_team(0) < Constants.MAX_PLAYERS_PER_TEAM else 1

func _add_row(peer_id: int, is_self: bool, team: int) -> void:
	if _peer_rows.has(peer_id):
		return
	var row := HBoxContainer.new()
	var label := Label.new()
	var role := "Host" if peer_id == 1 else "Player"
	label.text = "%s%s" % [role, " (You)" if is_self else ""]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if _is_host and not is_self:
		var kick_btn := Button.new()
		kick_btn.text = "Kick"
		kick_btn.pressed.connect(func(): _kick_peer(peer_id))
		row.add_child(kick_btn)
	_team_lists[team].add_child(row)
	_peer_rows[peer_id] = row

func _remove_row(peer_id: int) -> void:
	if _peer_rows.has(peer_id):
		_peer_rows[peer_id].queue_free()
		_peer_rows.erase(peer_id)

func _refresh_start_button() -> void:
	%StartButton.disabled = _count_team(0) < 1 or _count_team(1) < 1

func _update_status() -> void:
	var total := _peer_rows.size()
	if _count_team(1) < 1:
		%StatusLabel.text = "Waiting for opponents..."
	else:
		%StatusLabel.text = "%d player%s ready" % [total, "s" if total != 1 else ""]

# --- Host-side: new peer announced themselves ---

@rpc("any_peer", "reliable")
func _rpc_hello() -> void:
	if not _is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if _team_assignments.has(id):
		return
	var team := _auto_assign_team()
	_team_assignments[id] = team
	# send full current state to the newcomer
	_rpc_sync_state.rpc_id(id, _team_assignments)
	# tell all existing peers about the newcomer
	for existing_id in _peer_rows:
		if existing_id != id:
			_rpc_peer_joined.rpc_id(existing_id, id, team)
	# add row locally on host
	_add_row(id, false, team)
	_refresh_start_button()
	_update_status()

# --- Sync to a newly joined client ---

@rpc("authority", "reliable")
func _rpc_sync_state(assignments: Dictionary) -> void:
	_team_assignments = assignments
	# clear any stale rows
	for id in _peer_rows:
		_peer_rows[id].queue_free()
	_peer_rows.clear()
	var my_id := multiplayer.get_unique_id()
	for peer_id in assignments:
		_add_row(peer_id, peer_id == my_id, assignments[peer_id])
	_update_status()

# --- Broadcast to existing clients when roster changes ---

@rpc("authority", "reliable")
func _rpc_peer_joined(peer_id: int, team: int) -> void:
	_team_assignments[peer_id] = team
	_add_row(peer_id, false, team)
	_update_status()

@rpc("authority", "reliable")
func _rpc_peer_left(peer_id: int) -> void:
	_team_assignments.erase(peer_id)
	_remove_row(peer_id)
	_update_status()

# --- Disconnect handling ---

func _on_peer_disconnected(id: int) -> void:
	_team_assignments.erase(id)
	_remove_row(id)
	for remaining_id in _peer_rows:
		if remaining_id != 1:
			_rpc_peer_left.rpc_id(remaining_id, id)
	_refresh_start_button()
	_update_status()

func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file(LOBBY_SCENE)

# --- Kick ---

func _kick_peer(peer_id: int) -> void:
	_rpc_kicked.rpc_id(peer_id)
	call_deferred("_disconnect_peer", peer_id)

func _disconnect_peer(peer_id: int) -> void:
	var peer = multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		peer.disconnect_peer(peer_id)
	elif peer is WebRTCMultiplayerPeer:
		peer.remove_peer(peer_id)

@rpc("authority", "reliable")
func _rpc_kicked() -> void:
	multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file(LOBBY_SCENE)

# --- Start ---

func _on_code_display_pressed() -> void:
	var code: String = PlayerPrefs.room_code
	if OS.get_name() == "Web":
		JavaScriptBridge.eval("navigator.clipboard.writeText('%s').catch(()=>{})" % code)
	else:
		DisplayServer.clipboard_set(code)
	%StatusLabel.text = "Copied!"

func _on_start_pressed() -> void:
	if not _is_host:
		return
	if _is_web:
		WebRTCSignaling.seal()
	PlayerPrefs.peer_teams = _team_assignments
	_rpc_start_game.rpc(_team_assignments)
	get_tree().change_scene_to_file(GAME_SCENE)

@rpc("authority", "reliable")
func _rpc_start_game(assignments: Dictionary) -> void:
	PlayerPrefs.peer_teams = assignments
	get_tree().change_scene_to_file(GAME_SCENE)

# --- Back ---

func _on_back_pressed() -> void:
	PlayerPrefs.room_code = ""
	multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file(LOBBY_SCENE)
