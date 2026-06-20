extends Node

const PLAYER_SCENE = preload("res://scenes/entities/player.tscn")

# game.gd is the orchestrator and owner of the peer→arena/player topology and the
# per-peer stat counters. The networking, economy, and match-flow concerns live
# on the NetSync / Economy / MatchManager child nodes (see _ready wiring).

var _peer_to_arena: Dictionary = {}
var _peer_to_player: Dictionary = {}
var _peer_to_archetype: Dictionary = {}
var _networked: bool = false
var _leaving: bool = false
var _pending_kills: Dictionary = {}  # arena -> count of mobs dying this frame
var _pending_kills_flush_queued: bool = false
var _spectator_peer_ids: Array = []
var _spectator_camera: Camera2D = null

# Stat counters (rendered by the scoreboard; written here on kills and by Economy on purchases)
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
var _fps_label: Label = null
var _fps_timer: float = 0.0

@onready var arena1: Node2D = $Arena1
@onready var arena2: Node2D = $Arena2
@onready var net_sync: Node = $NetSync
@onready var economy: Node = $Economy
@onready var match_manager: Node = $MatchManager

func _ready() -> void:
	_networked = not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	match_manager.setup_skill_bar()
	economy.setup_shop()
	_setup_mob_bars()
	economy.connect_zone_signals()
	_setup_scoreboard()
	_fps_label = $HUD/FpsLabel

	if not _networked:
		PlayerPrefs.peer_names = {1: PlayerPrefs.player_name}
		_peer_to_arena[1] = arena1
		_peer_to_archetype[1] = PlayerPrefs.archetype
		_spawn_player(1)
		var center := Vector2(Constants.WORLD_SIZE_X * 0.5, Constants.WORLD_SIZE_Y * 0.5)
		arena1.spawn_mob(0, center)
		for i in Constants.MOB_COUNT - 1:
			arena1.spawn_mob()
		_push_hud_update()
		return

	_spectator_peer_ids = PlayerPrefs.peer_spectators

	# Populate arena assignments from the team layout decided in game_room
	for peer_id in PlayerPrefs.peer_teams:
		_peer_to_arena[peer_id] = arena1 if PlayerPrefs.peer_teams[peer_id] == 0 else arena2

	var my_id_ready: int = multiplayer.get_unique_id()
	if _spectator_peer_ids.has(my_id_ready):
		_setup_spectator_camera()

	net_sync.begin()

# --- Host-migration support ---

func _remap_peer_id(old_id: int, new_id: int) -> void:
	for dict in [_peer_to_player, _peer_to_arena, _peer_to_archetype,
			_peer_kills, _peer_money_earned, _peer_mobs_sent,
			_peer_debuffs_applied, _peer_stats_cache, PlayerPrefs.peer_names]:
		if dict.has(old_id):
			dict[new_id] = dict[old_id]
			dict.erase(old_id)

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

func _count_players_in_arena(arena: Node2D) -> int:
	var count := 0
	for pid in _peer_to_player:
		if _peer_to_arena.get(pid) == arena:
			count += 1
	return count

func _setup_spectator_camera() -> void:
	var cam := Camera2D.new()
	cam.set_script(load("res://scripts/game/spectator_camera.gd"))
	add_child(cam)
	cam.init(arena1, arena2)
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
		match_manager.init_unlock_state(peer_id)

func notify_mob_killed(arena: Node2D, killer: Node = null) -> void:
	if not multiplayer.is_server() or _leaving:
		return
	var opponent: Node2D = arena2 if arena == arena1 else arena1
	opponent.spawn_mob()
	opponent.spawn_mob()
	var killer_id := -1
	if killer and is_instance_valid(killer):
		for pid in _peer_to_player:
			if _peer_to_player[pid] == killer:
				killer_id = pid
				break
	economy.award_kill(killer_id, arena)
	if killer_id != -1:
		_peer_kills[killer_id] = _peer_kills.get(killer_id, 0) + 1
	_sync_stats()
	# Accumulate kills this frame — queue_free runs after deferred calls,
	# so every mob that died this frame is still counted by get_mob_count().
	_pending_kills[arena] = _pending_kills.get(arena, 0) + 1
	var a1: int = arena1.get_mob_count() - _pending_kills.get(arena1, 0)
	var a2: int = arena2.get_mob_count() - _pending_kills.get(arena2, 0)
	# Refill an emptied arena so it never sits at zero.
	if a1 <= 0:
		arena1.spawn_mob()
		arena1.spawn_mob()
		a1 = arena1.get_mob_count() - _pending_kills.get(arena1, 0)
	if a2 <= 0:
		arena2.spawn_mob()
		arena2.spawn_mob()
		a2 = arena2.get_mob_count() - _pending_kills.get(arena2, 0)
	_update_hud_local(a1, a2)
	if _networked:
		_rpc_update_hud.rpc(a1, a2)
	match_manager.check_win(a1, a2)
	match_manager.check_skill_unlocks(a1, a2)
	if not _pending_kills_flush_queued:
		_pending_kills_flush_queued = true
		call_deferred("_clear_pending_kills")

func _clear_pending_kills() -> void:
	_pending_kills.clear()
	_pending_kills_flush_queued = false

# --- HUD ---

func _push_hud_update() -> void:
	var a1: int = arena1.get_mob_count()
	var a2: int = arena2.get_mob_count()
	_update_hud_local(a1, a2)
	if _networked and multiplayer.is_server():
		_rpc_update_hud.rpc(a1, a2)
	if multiplayer.is_server() or not _networked:
		match_manager.check_win(a1, a2)
		match_manager.check_skill_unlocks(a1, a2)

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
	var my_is_arena1: bool = _peer_to_arena.get(my_id) == arena1
	var my    := a1 if my_is_arena1 else a2
	var enemy := a2 if my_is_arena1 else a1
	_my_mob_bar.set_count(my, PlayerPrefs.mob_win_count)
	_enemy_mob_bar.set_count(enemy, PlayerPrefs.mob_win_count)

@rpc("authority", "reliable")
func _rpc_update_hud(a1: int, a2: int) -> void:
	_update_hud_local(a1, a2)

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

func _sync_stats() -> void:
	_peer_stats_cache = _gather_stats()
	if _networked:
		_rpc_update_stats.rpc(_peer_stats_cache)

@rpc("authority", "reliable")
func _rpc_update_stats(stats: Dictionary) -> void:
	_peer_stats_cache = stats

# --- Process loop ---

func _process(delta: float) -> void:
	if _fps_label != null:
		_fps_timer -= delta
		if _fps_timer <= 0.0:
			_fps_timer = 0.25
			_fps_label.text = "%d fps" % int(Engine.get_frames_per_second())
	if _leaving:
		return
	if _networked:
		net_sync.update_host_liveness(delta)
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
	match_manager.update_skill_bar(player)
	net_sync.tick_ping(delta)

func _on_return_pressed() -> void:
	_leaving = true
	net_sync.leave_game()

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
