extends Node

# Economy — owns per-peer gold and upgrade levels, and the shop / arena-master
# UI + purchase flow. Server-authoritative: clients send purchase requests, the
# server validates against money and broadcasts the resulting money/level state.
# game.gd (the parent) owns the peer→arena/player topology and the stat counters;
# this node reaches into it via the `game` back-reference.

var game: Node

# State owned here
var _peer_money: Dictionary = {}                 # peer_id -> int
var _player_speed_levels: Dictionary = {}        # peer_id -> int
var _player_damage_levels: Dictionary = {}
var _player_sword_size_levels: Dictionary = {}
var _player_attack_speed_levels: Dictionary = {}
var _player_skill1_levels: Dictionary = {}
var _player_skill2_levels: Dictionary = {}
var _player_skill3_levels: Dictionary = {}

var _in_shop_zone := false
var _in_arena_master_zone := false

@onready var _shop_panel: CanvasLayer = get_parent().get_node("ShopPanel")
@onready var _shop_vbox: VBoxContainer = get_parent().get_node("ShopPanel/PanelBG/VBox")
@onready var _am_panel: CanvasLayer = get_parent().get_node("ArenaMasterPanel")
@onready var _am_vbox: VBoxContainer = get_parent().get_node("ArenaMasterPanel/PanelBG/VBox")
@onready var _money_label: Label = get_parent().get_node("HUD/MoneyLabel")
@onready var _debuff_bar: HBoxContainer = get_parent().get_node("HUD/DebuffBar")

func _ready() -> void:
	game = get_parent()

func _my_id() -> int:
	return 1 if not game._networked else multiplayer.get_unique_id()

# --- Shop / arena-master zone wiring ---

func connect_zone_signals() -> void:
	for arena in [game.arena1, game.arena2]:
		arena.player_entered_shop.connect(_on_player_entered_shop)
		arena.player_exited_shop.connect(_on_player_exited_shop)
		arena.player_entered_arena_master.connect(_on_player_entered_arena_master)
		arena.player_exited_arena_master.connect(_on_player_exited_arena_master)

func _on_player_entered_shop() -> void:
	if game._leaving:
		return
	_in_shop_zone = true
	_shop_panel.visible = true
	update_shop_ui()

func _on_player_exited_shop() -> void:
	_in_shop_zone = false
	_shop_panel.visible = false

func _on_player_entered_arena_master() -> void:
	if game._leaving:
		return
	_in_arena_master_zone = true
	_am_panel.visible = true
	update_arena_master_ui()

func _on_player_exited_arena_master() -> void:
	_in_arena_master_zone = false
	_am_panel.visible = false

# --- Shop setup / UI ---

func setup_shop() -> void:
	_shop_vbox.get_node("SpeedBtn").pressed.connect(func(): buy(3))
	_shop_vbox.get_node("DamageBtn").pressed.connect(func(): buy(4))
	_shop_vbox.get_node("SwordSizeBtn").pressed.connect(func(): buy(5))
	_shop_vbox.get_node("AttackSpeedBtn").pressed.connect(func(): buy(6))
	_shop_vbox.get_node("Skill1Btn").pressed.connect(func(): buy(12))
	_shop_vbox.get_node("Skill2Btn").pressed.connect(func(): buy(13))
	_shop_vbox.get_node("Skill3Btn").pressed.connect(func(): buy(14))
	_am_vbox.get_node("SendMobBtn").pressed.connect(func(): buy(0))
	_am_vbox.get_node("Send3MobsBtn").pressed.connect(func(): buy(1))
	_am_vbox.get_node("SendFleeingBtn").pressed.connect(func(): buy(2))
	_am_vbox.get_node("SendBossBtn").pressed.connect(func(): buy(7))
	_am_vbox.get_node("UpgradeMobsBtn").pressed.connect(func(): buy(15))
	_am_vbox.get_node("DebuffNoDashBtn").pressed.connect(func(): buy(Constants.DEBUFF_NO_DASH))
	_am_vbox.get_node("DebuffFrenzyBtn").pressed.connect(func(): buy(Constants.DEBUFF_FRENZY))
	_am_vbox.get_node("DebuffSilenceBtn").pressed.connect(func(): buy(Constants.DEBUFF_SILENCE))
	_am_vbox.get_node("DebuffInvertBtn").pressed.connect(func(): buy(Constants.DEBUFF_INVERT))

func _upgrade_cost(base: int, inc: int, current_level: int) -> int:
	return base + current_level * inc

func update_shop_ui() -> void:
	if not _shop_panel.visible:
		return
	var my_id: int = _my_id()
	var money: int = _peer_money.get(my_id, 0)
	var max_lvl := Constants.SHOP_UPGRADE_MAX_LEVEL
	var vbox := _shop_vbox
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
	var player = game._peer_to_player.get(my_id)
	var skill_level_dicts := [_player_skill1_levels, _player_skill2_levels, _player_skill3_levels]
	var unlocked_arr: Array = game.match_manager._player_skills_unlocked.get(my_id, [false, false, false])
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

func update_arena_master_ui() -> void:
	if not _am_panel.visible:
		return
	var my_id: int = _my_id()
	var money: int = _peer_money.get(my_id, 0)
	var vbox := _am_vbox
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

# --- Money ---

func update_money(peer_money: Dictionary) -> void:
	_peer_money = peer_money
	var my_id: int = _my_id()
	_money_label.text = "$%d" % _peer_money.get(my_id, 0)
	update_shop_ui()
	update_arena_master_ui()

@rpc("authority", "reliable")
func _rpc_update_money(peer_money: Dictionary) -> void:
	update_money(peer_money)

func _broadcast_money() -> void:
	update_money(_peer_money)
	if game._networked:
		_rpc_update_money.rpc(_peer_money)

# Reward gold for a mob kill. killer_id == -1 falls back to crediting everyone in
# the killing arena. Returns nothing; game.gd tracks the kill counter separately.
func award_kill(killer_id: int, arena: Node2D) -> void:
	if killer_id != -1:
		_peer_money[killer_id] = _peer_money.get(killer_id, 0) + Constants.KILL_REWARD
		game._peer_money_earned[killer_id] = game._peer_money_earned.get(killer_id, 0) + Constants.KILL_REWARD
	else:
		for pid in game._peer_to_arena:
			if game._peer_to_arena[pid] == arena:
				_peer_money[pid] = _peer_money.get(pid, 0) + Constants.KILL_REWARD
				game._peer_money_earned[pid] = game._peer_money_earned.get(pid, 0) + Constants.KILL_REWARD
	_broadcast_money()

# Spread a leaving peer's gold among their arena teammates (host migration / leave).
func spread_gold(leaving_id: int) -> void:
	var gold: int = _peer_money.get(leaving_id, 0)
	if gold <= 0:
		return
	var leaving_arena: Node2D = game._peer_to_arena.get(leaving_id)
	if leaving_arena == null:
		return
	var teammates: Array = []
	for pid in game._peer_to_arena:
		if pid != leaving_id and game._peer_to_arena[pid] == leaving_arena:
			teammates.append(pid)
	if teammates.is_empty():
		return
	var share := gold / teammates.size()
	for pid in teammates:
		_peer_money[pid] = _peer_money.get(pid, 0) + share
	_peer_money[leaving_id] = 0
	_broadcast_money()

# --- Purchases ---

func buy(item_id: int) -> void:
	if game._networked and not multiplayer.is_server():
		_rpc_request_purchase.rpc_id(1, item_id)
	else:
		apply_purchase(_my_id(), item_id)

@rpc("any_peer", "reliable")
func _rpc_request_purchase(item_id: int) -> void:
	if not multiplayer.is_server():
		return
	apply_purchase(multiplayer.get_remote_sender_id(), item_id)

func apply_purchase(peer_id: int, item_id: int) -> void:
	if game._leaving:
		return
	var is_a1: bool = game._peer_to_arena.get(peer_id) == game.arena1
	var money: int = _peer_money.get(peer_id, 0)
	var opponent_arena: Node2D = game.arena2 if is_a1 else game.arena1

	match item_id:
		0:
			if money < Constants.SHOP_COST_SEND_MOB:
				return
			money -= Constants.SHOP_COST_SEND_MOB
			opponent_arena.spawn_mob()
			game._peer_mobs_sent[peer_id] = game._peer_mobs_sent.get(peer_id, 0) + 1
		1:
			if money < Constants.SHOP_COST_SEND_3_MOBS:
				return
			money -= Constants.SHOP_COST_SEND_3_MOBS
			for i in 3:
				opponent_arena.spawn_mob()
			game._peer_mobs_sent[peer_id] = game._peer_mobs_sent.get(peer_id, 0) + 3
		2:
			if money < Constants.SHOP_COST_SEND_FLEEING:
				return
			money -= Constants.SHOP_COST_SEND_FLEEING
			opponent_arena.spawn_mob(1)
			game._peer_mobs_sent[peer_id] = game._peer_mobs_sent.get(peer_id, 0) + 1
		7:
			if money < Constants.SHOP_COST_SEND_BOSS:
				return
			money -= Constants.SHOP_COST_SEND_BOSS
			opponent_arena.spawn_mob(2)
			game._peer_mobs_sent[peer_id] = game._peer_mobs_sent.get(peer_id, 0) + 1
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
			var player = game._peer_to_player.get(peer_id)
			if player and is_instance_valid(player):
				player.speed_level = new_level
				if game._networked and peer_id != 1:
					player.net_sync.rpc_apply_speed_level.rpc_id(peer_id, new_level)
			if game._networked and peer_id != 1:
				_rpc_sync_speed_level.rpc_id(peer_id, new_level)
		4:
			var cur_level: int = _player_damage_levels.get(peer_id, 0)
			var cost := _upgrade_cost(Constants.SHOP_COST_DAMAGE_BASE, Constants.SHOP_COST_DAMAGE_INC, cur_level)
			if cur_level >= Constants.SHOP_UPGRADE_MAX_LEVEL or money < cost:
				return
			money -= cost
			var new_level: int = cur_level + 1
			_player_damage_levels[peer_id] = new_level
			var player = game._peer_to_player.get(peer_id)
			if player and is_instance_valid(player):
				player.damage_level = new_level
				player.apply_upgrades_to_sword()
				if game._networked and peer_id != 1:
					player.net_sync.rpc_apply_damage_level.rpc_id(peer_id, new_level)
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
			var player = game._peer_to_player.get(peer_id)
			if player and is_instance_valid(player):
				player.sword_size_level = new_level
				player.apply_upgrades_to_sword()
				if game._networked and peer_id != 1:
					player.net_sync.rpc_apply_sword_size_level.rpc_id(peer_id, new_level)
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
			var player = game._peer_to_player.get(peer_id)
			if player and is_instance_valid(player):
				player.attack_speed_level = new_level
				player.apply_upgrades_to_sword()
				if game._networked and peer_id != 1:
					player.net_sync.rpc_apply_attack_speed_level.rpc_id(peer_id, new_level)
		12:
			if not game.match_manager._player_skills_unlocked.get(peer_id, [false, false, false])[0]:
				return
			var cur_level: int = _player_skill1_levels.get(peer_id, 0)
			var cost := _upgrade_cost(Constants.SHOP_COST_SKILL_BASE, Constants.SHOP_COST_SKILL_INC, cur_level)
			if cur_level >= Constants.SHOP_UPGRADE_MAX_LEVEL or money < cost:
				return
			money -= cost
			var new_level: int = cur_level + 1
			_player_skill1_levels[peer_id] = new_level
			var player = game._peer_to_player.get(peer_id)
			if player and is_instance_valid(player):
				player.skill1_level = new_level
				player.apply_skill_upgrades()
				if game._networked and peer_id != 1:
					player.net_sync.rpc_apply_skill1_level.rpc_id(peer_id, new_level)
			if game._networked and peer_id != 1:
				_rpc_sync_skill1_level.rpc_id(peer_id, new_level)
		13:
			if not game.match_manager._player_skills_unlocked.get(peer_id, [false, false, false])[1]:
				return
			var cur_level: int = _player_skill2_levels.get(peer_id, 0)
			var cost := _upgrade_cost(Constants.SHOP_COST_SKILL_BASE, Constants.SHOP_COST_SKILL_INC, cur_level)
			if cur_level >= Constants.SHOP_UPGRADE_MAX_LEVEL or money < cost:
				return
			money -= cost
			var new_level: int = cur_level + 1
			_player_skill2_levels[peer_id] = new_level
			var player = game._peer_to_player.get(peer_id)
			if player and is_instance_valid(player):
				player.skill2_level = new_level
				player.apply_skill_upgrades()
				if game._networked and peer_id != 1:
					player.net_sync.rpc_apply_skill2_level.rpc_id(peer_id, new_level)
			if game._networked and peer_id != 1:
				_rpc_sync_skill2_level.rpc_id(peer_id, new_level)
		14:
			if not game.match_manager._player_skills_unlocked.get(peer_id, [false, false, false])[2]:
				return
			var cur_level: int = _player_skill3_levels.get(peer_id, 0)
			var cost := _upgrade_cost(Constants.SHOP_COST_SKILL_BASE, Constants.SHOP_COST_SKILL_INC, cur_level)
			if cur_level >= Constants.SHOP_UPGRADE_MAX_LEVEL or money < cost:
				return
			money -= cost
			var new_level: int = cur_level + 1
			_player_skill3_levels[peer_id] = new_level
			var player = game._peer_to_player.get(peer_id)
			if player and is_instance_valid(player):
				player.skill3_level = new_level
				player.apply_skill_upgrades()
				if game._networked and peer_id != 1:
					player.net_sync.rpc_apply_skill3_level.rpc_id(peer_id, new_level)
			if game._networked and peer_id != 1:
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
			game._peer_debuffs_applied[peer_id] = game._peer_debuffs_applied.get(peer_id, 0) + 1
		Constants.DEBUFF_FRENZY:
			if money < Constants.DEBUFF_COST_FRENZY:
				return
			money -= Constants.DEBUFF_COST_FRENZY
			opponent_arena.mob_speed_multiplier = Constants.DEBUFF_FRENZY_SPEED_MULT
			opponent_arena.mob_frenzy_timer = Constants.DEBUFF_DUR_FRENZY
			if game._networked:
				opponent_arena.rpc_set_frenzy.rpc(Constants.DEBUFF_FRENZY_SPEED_MULT, Constants.DEBUFF_DUR_FRENZY)
			_notify_opponents_debuff_icon(peer_id, Constants.DEBUFF_FRENZY, Constants.DEBUFF_DUR_FRENZY)
			game._peer_debuffs_applied[peer_id] = game._peer_debuffs_applied.get(peer_id, 0) + 1

	_peer_money[peer_id] = money
	_broadcast_money()
	game._push_hud_update()
	game._sync_stats()

@rpc("authority", "reliable")
func _rpc_sync_speed_level(level: int) -> void:
	var my_id: int = multiplayer.get_unique_id()
	_player_speed_levels[my_id] = level
	update_shop_ui()

@rpc("authority", "reliable")
func _rpc_sync_skill1_level(level: int) -> void:
	var my_id: int = multiplayer.get_unique_id()
	_player_skill1_levels[my_id] = level
	update_shop_ui()

@rpc("authority", "reliable")
func _rpc_sync_skill2_level(level: int) -> void:
	var my_id: int = multiplayer.get_unique_id()
	_player_skill2_levels[my_id] = level
	update_shop_ui()

@rpc("authority", "reliable")
func _rpc_sync_skill3_level(level: int) -> void:
	var my_id: int = multiplayer.get_unique_id()
	_player_skill3_levels[my_id] = level
	update_shop_ui()

# --- Debuffs ---

func _apply_debuff_to_opponents(buyer_id: int, item_id: int, dur: float) -> void:
	var my_arena = game._peer_to_arena.get(buyer_id)
	for opp_id in game._peer_to_player:
		if game._peer_to_arena.get(opp_id) == my_arena:
			continue
		var opp_player = game._peer_to_player.get(opp_id)
		if not opp_player or not is_instance_valid(opp_player):
			continue
		opp_player.net_sync.rpc_apply_debuff(item_id, dur)
		if game._networked and opp_id != 1:
			opp_player.net_sync.rpc_apply_debuff.rpc_id(opp_id, item_id, dur)
		_notify_debuff_icon(opp_id, item_id, dur)

func _notify_opponents_debuff_icon(buyer_id: int, item_id: int, dur: float) -> void:
	var my_arena = game._peer_to_arena.get(buyer_id)
	for opp_id in game._peer_to_player:
		if game._peer_to_arena.get(opp_id) != my_arena:
			_notify_debuff_icon(opp_id, item_id, dur)

func _notify_debuff_icon(target_id: int, item_id: int, dur: float) -> void:
	if not game._networked or target_id == 1:
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
	var indicator := DEBUFF_INDICATOR.new()
	indicator.debuff_name = NAMES.get(type, "?")
	indicator.icon_color = COLORS.get(type, Color(0.6, 0.1, 0.1))
	indicator.time_remaining = duration
	_debuff_bar.add_child(indicator)
