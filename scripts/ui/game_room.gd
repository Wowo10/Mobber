extends CanvasLayer

const GAME_SCENE = "res://scenes/game/game.tscn"
const LOBBY_SCENE = "res://scenes/ui/lobby.tscn"
const ARCHETYPE_NAMES := ["Knight", "Pirate"]

var _is_host: bool = false
var _team_assignments: Dictionary = {}   # peer_id -> 0 or 1
var _peer_names: Dictionary = {}         # peer_id -> String
var _peer_archetypes: Dictionary = {}    # peer_id -> int
var _peer_rows: Dictionary = {}          # peer_id -> HBoxContainer
var _peer_arch_nodes: Dictionary = {}    # peer_id -> OptionButton (self) or Label (others)
var _team_lists: Array                   # [%Team1List, %Team2List]

func _ready() -> void:
	_is_host = multiplayer.is_server()
	_team_lists = [%Team1List, %Team2List]
	%StartButton.visible = _is_host
	%StartButton.disabled = true

	var win_opts := [50, 75, 100, 120]
	for v in win_opts:
		%WinCountSelect.add_item(str(v), v)
	var default_idx := win_opts.find(PlayerPrefs.mob_win_count)
	%WinCountSelect.select(default_idx if default_idx >= 0 else 0)
	%WinCountSelect.disabled = not _is_host

	if _is_host:
		_peer_names[1] = PlayerPrefs.player_name
		_peer_archetypes[1] = PlayerPrefs.archetype
		_team_assignments[1] = 0
		_add_row(1, true, 0)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		if not PlayerPrefs.room_code.is_empty():
			%CodeDisplay.text = "Room: %s  [click to copy]" % PlayerPrefs.room_code
			%CodeDisplay.visible = true
	else:
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		await get_tree().process_frame
		_rpc_hello.rpc_id(1, PlayerPrefs.player_name, PlayerPrefs.archetype)

# --- Helpers ---

func _archetype_name(arch: int) -> String:
	return ARCHETYPE_NAMES[arch] if arch >= 0 and arch < ARCHETYPE_NAMES.size() else "?"

func _display_name(peer_id: int) -> String:
	var n: String = _peer_names.get(peer_id, "")
	return n if not n.is_empty() else ("Host" if peer_id == 1 else "Player")

func _count_team(team: int) -> int:
	var count := 0
	for id in _team_assignments:
		if _team_assignments[id] == team:
			count += 1
	return count

func _auto_assign_team() -> int:
	var t0 := _count_team(0)
	var t1 := _count_team(1)
	return 0 if t0 <= t1 else 1

# --- Row management ---

func _add_row(peer_id: int, is_self: bool, team: int) -> void:
	if _peer_rows.has(peer_id):
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var name_lbl := Label.new()
	name_lbl.text = "%s%s" % [_display_name(peer_id), " (You)" if is_self else ""]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	if is_self:
		var arch_btn := OptionButton.new()
		for i in ARCHETYPE_NAMES.size():
			arch_btn.add_item(ARCHETYPE_NAMES[i], i)
		arch_btn.select(_peer_archetypes.get(peer_id, 0))
		arch_btn.item_selected.connect(func(idx: int): _on_archetype_selected(arch_btn.get_item_id(idx)))
		row.add_child(arch_btn)
		_peer_arch_nodes[peer_id] = arch_btn
	else:
		var arch_lbl := Label.new()
		arch_lbl.text = _archetype_name(_peer_archetypes.get(peer_id, 0))
		row.add_child(arch_lbl)
		_peer_arch_nodes[peer_id] = arch_lbl

		if _is_host:
			var switch_btn := Button.new()
			switch_btn.text = "⇄"
			switch_btn.tooltip_text = "Switch team"
			switch_btn.pressed.connect(func(): _switch_team(peer_id))
			row.add_child(switch_btn)

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
	_peer_arch_nodes.erase(peer_id)

func _update_arch_display(peer_id: int, arch: int) -> void:
	var node = _peer_arch_nodes.get(peer_id)
	if node is Label:
		node.text = _archetype_name(arch)

func _refresh_start_button() -> void:
	%StartButton.disabled = _count_team(0) < 1 or _count_team(1) < 1

func _update_status() -> void:
	var total := _peer_rows.size()
	if _count_team(1) < 1:
		%StatusLabel.text = "Waiting for opponents..."
	else:
		%StatusLabel.text = "%d player%s ready" % [total, "s" if total != 1 else ""]

# --- Archetype change ---

func _on_archetype_selected(arch: int) -> void:
	PlayerPrefs.archetype = arch
	if _is_host:
		var my_id := multiplayer.get_unique_id()
		_peer_archetypes[my_id] = arch
		_rpc_peer_archetype_changed.rpc(my_id, arch)
	else:
		_rpc_request_archetype.rpc_id(1, arch)

@rpc("any_peer", "reliable")
func _rpc_request_archetype(arch: int) -> void:
	if not _is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	_peer_archetypes[id] = arch
	_rpc_peer_archetype_changed.rpc(id, arch)

@rpc("authority", "reliable")
func _rpc_peer_archetype_changed(peer_id: int, arch: int) -> void:
	_peer_archetypes[peer_id] = arch
	_update_arch_display(peer_id, arch)

# --- Team switch (host only) ---

func _switch_team(peer_id: int) -> void:
	var new_team := 1 if _team_assignments.get(peer_id, 0) == 0 else 0
	_rpc_peer_team_changed.rpc(peer_id, new_team)
	_refresh_start_button()

@rpc("authority", "reliable")
func _rpc_peer_team_changed(peer_id: int, new_team: int) -> void:
	_team_assignments[peer_id] = new_team
	_remove_row(peer_id)
	var my_id := multiplayer.get_unique_id()
	_add_row(peer_id, peer_id == my_id, new_team)
	_update_status()

# --- Host-side: new peer announced themselves ---

@rpc("any_peer", "reliable")
func _rpc_hello(pname: String, arch: int) -> void:
	if not _is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if _team_assignments.has(id):
		return
	_peer_names[id] = pname
	_peer_archetypes[id] = arch
	var team := _auto_assign_team()
	_team_assignments[id] = team
	_rpc_sync_state.rpc_id(id, _team_assignments, _peer_names, _peer_archetypes, PlayerPrefs.mob_win_count)
	for existing_id in _peer_rows:
		if existing_id != id:
			_rpc_peer_joined.rpc_id(existing_id, id, team, pname, arch)
	_add_row(id, false, team)
	_refresh_start_button()
	_update_status()

# --- Sync to a newly joined client ---

@rpc("authority", "reliable")
func _rpc_sync_state(assignments: Dictionary, names: Dictionary, archetypes: Dictionary, win_count: int) -> void:
	_team_assignments = assignments
	_peer_names = names
	_peer_archetypes = archetypes
	PlayerPrefs.peer_names = names
	PlayerPrefs.mob_win_count = win_count
	var win_opts := [50, 75, 100, 120]
	var widx := win_opts.find(win_count)
	if widx >= 0:
		%WinCountSelect.select(widx)
	for id in _peer_rows:
		_peer_rows[id].queue_free()
	_peer_rows.clear()
	_peer_arch_nodes.clear()
	var my_id := multiplayer.get_unique_id()
	for peer_id in assignments:
		_add_row(peer_id, peer_id == my_id, assignments[peer_id])
	_update_status()

# --- Broadcast to existing clients when roster changes ---

@rpc("authority", "reliable")
func _rpc_peer_joined(peer_id: int, team: int, pname: String, arch: int) -> void:
	_team_assignments[peer_id] = team
	_peer_names[peer_id] = pname
	_peer_archetypes[peer_id] = arch
	PlayerPrefs.peer_names[peer_id] = pname
	_add_row(peer_id, false, team)
	_update_status()

@rpc("authority", "reliable")
func _rpc_peer_left(peer_id: int) -> void:
	_team_assignments.erase(peer_id)
	_peer_names.erase(peer_id)
	_peer_archetypes.erase(peer_id)
	_remove_row(peer_id)
	_update_status()

# --- Disconnect handling ---

func _on_peer_disconnected(id: int) -> void:
	_team_assignments.erase(id)
	_peer_names.erase(id)
	_peer_archetypes.erase(id)
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
	(multiplayer.multiplayer_peer as WebRTCMultiplayerPeer).remove_peer(peer_id)

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

func _on_win_count_selected(_idx: int) -> void:
	var new_count: int = %WinCountSelect.get_selected_id()
	PlayerPrefs.mob_win_count = new_count
	_rpc_win_count_changed.rpc(new_count)

@rpc("authority", "reliable")
func _rpc_win_count_changed(count: int) -> void:
	PlayerPrefs.mob_win_count = count
	var win_opts := [50, 75, 100, 120]
	var widx := win_opts.find(count)
	if widx >= 0:
		%WinCountSelect.select(widx)

func _on_start_pressed() -> void:
	if not _is_host:
		return
	WebRTCSignaling.seal()
	PlayerPrefs.peer_teams = _team_assignments
	PlayerPrefs.peer_names = _peer_names
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
