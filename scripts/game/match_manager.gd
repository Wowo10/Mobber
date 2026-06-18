extends Node

# MatchManager — owns the win condition and the skill-unlock progression. Skills
# unlock as a player's arena fills toward the loss threshold; the server grants a
# pending unlock at each milestone and the player chooses which skill to reveal.
# game.gd (parent) owns the peer topology and scoreboard rendering; reached via
# the `game` back-reference.

const SKILL_UNLOCK_THRESHOLDS := [0.10, 0.40, 0.70]

var game: Node

# State owned here
var _player_skills_unlocked: Dictionary = {}   # peer_id -> [false, false, false]
var _player_unlocks_pending: Dictionary = {}   # peer_id -> int
var _player_unlock_milestone: Dictionary = {}  # peer_id -> int (0-3)

@onready var _skill_bar: HBoxContainer = get_parent().get_node("HUD/SkillBar")

func _ready() -> void:
	game = get_parent()

func _my_id() -> int:
	return 1 if not game._networked else multiplayer.get_unique_id()

# --- Host-migration support ---

func remap_peer_id(old_id: int, new_id: int) -> void:
	for dict in [_player_skills_unlocked, _player_unlocks_pending, _player_unlock_milestone]:
		if dict.has(old_id):
			dict[new_id] = dict[old_id]
			dict.erase(old_id)

# Initialise unlock state for a freshly spawned player (server / offline only).
func init_unlock_state(peer_id: int) -> void:
	_player_skills_unlocked[peer_id] = [false, false, false]
	_player_unlocks_pending[peer_id] = 0
	_player_unlock_milestone[peer_id] = 0

# --- Skill bar ---

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

func setup_skill_bar() -> void:
	var bar := _skill_bar
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

# Reflect player cooldowns / debuff state onto the skill bar. Called each frame
# from game._process with the local player (may be null before spawn).
func update_skill_bar(player: Node) -> void:
	if player == null:
		return
	var bar := _skill_bar
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
	var slot = _skill_bar.get_node("Skill%dSlot" % (idx + 1))
	if slot.unlock_available:
		get_viewport().set_input_as_handled()
		_on_skill_unlock_requested(idx)

func _on_skill_unlock_requested(skill_index: int) -> void:
	var bar := _skill_bar
	for i in 3:
		bar.get_node("Skill%dSlot" % (i + 1)).set_unlock_available(false)
	if game._networked and not multiplayer.is_server():
		_rpc_request_skill_unlock.rpc_id(1, skill_index)
	else:
		apply_skill_unlock(1, skill_index)

# --- Win condition ---

func check_win(a1: int, a2: int) -> void:
	if a1 >= PlayerPrefs.mob_win_count:
		_rpc_game_over(1)
		_rpc_game_over.rpc(1)
	elif a2 >= PlayerPrefs.mob_win_count:
		_rpc_game_over(2)
		_rpc_game_over.rpc(2)

@rpc("authority", "reliable")
func _rpc_game_over(losing_arena_id: int) -> void:
	var overlay := game.get_node("GameOverOverlay")
	if overlay.visible:
		return
	for child in game.get_node("PlayerContainer").get_children():
		child.set_physics_process(false)

	var my_id: int = _my_id()

	var vbox := overlay.get_node("VBox")
	var title := vbox.get_node("TitleLabel")
	var sub := vbox.get_node("SubLabel")
	var return_btn := vbox.get_node("ReturnButton")

	if game._spectator_peer_ids.has(my_id):
		title.text = "GAME OVER"
		title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		sub.text = "Arena %d was overrun by mobs." % losing_arena_id
		sub.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5))
	else:
		var my_is_arena1: bool = game._peer_to_arena.get(my_id) == game.arena1
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

	if not game._networked or multiplayer.is_server():
		game._peer_stats_cache = game._gather_stats()

	var sb: Control = game._build_game_over_scoreboard(my_id)
	sb.name = "GameOverScoreboard"
	vbox.add_child(sb)
	vbox.move_child(return_btn, vbox.get_child_count() - 1)

	overlay.visible = true

# --- Skill unlock progression ---

func check_skill_unlocks(a1: int, a2: int) -> void:
	var win_count := PlayerPrefs.mob_win_count
	if win_count <= 0:
		return
	for peer_id in game._peer_to_arena:
		var arena: Node2D = game._peer_to_arena[peer_id]
		var count := a1 if arena == game.arena1 else a2
		var milestone: int = _player_unlock_milestone.get(peer_id, 0)
		while milestone < SKILL_UNLOCK_THRESHOLDS.size():
			if float(count) / float(win_count) >= SKILL_UNLOCK_THRESHOLDS[milestone]:
				milestone += 1
				_player_unlock_milestone[peer_id] = milestone
				_player_unlocks_pending[peer_id] = _player_unlocks_pending.get(peer_id, 0) + 1
				if not game._networked or peer_id == 1:
					_rpc_notify_skill_unlock_available()
				else:
					_rpc_notify_skill_unlock_available.rpc_id(peer_id)
			else:
				break

func apply_skill_unlock(peer_id: int, skill_index: int) -> void:
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
	var player = game._peer_to_player.get(peer_id)
	if player and is_instance_valid(player):
		player.skills_unlocked = unlocked
		if game._networked and peer_id != 1:
			player.net_sync.rpc_sync_skills_unlocked.rpc_id(peer_id, unlocked)
	if not game._networked or peer_id == 1:
		_rpc_sync_skill_unlocks(unlocked)
	else:
		_rpc_sync_skill_unlocks.rpc_id(peer_id, unlocked)
	if _player_unlocks_pending[peer_id] > 0:
		if not game._networked or peer_id == 1:
			_rpc_notify_skill_unlock_available()
		else:
			_rpc_notify_skill_unlock_available.rpc_id(peer_id)

@rpc("authority", "reliable")
func _rpc_notify_skill_unlock_available() -> void:
	var my_id: int = _my_id()
	var unlocked: Array = _player_skills_unlocked.get(my_id, [false, false, false])
	var bar := _skill_bar
	for i in 3:
		if not unlocked[i]:
			bar.get_node("Skill%dSlot" % (i + 1)).set_unlock_available(true)

@rpc("any_peer", "reliable")
func _rpc_request_skill_unlock(skill_index: int) -> void:
	if not multiplayer.is_server():
		return
	apply_skill_unlock(multiplayer.get_remote_sender_id(), skill_index)

@rpc("authority", "reliable")
func _rpc_sync_skill_unlocks(unlocked: Array) -> void:
	var my_id: int = _my_id()
	_player_skills_unlocked[my_id] = unlocked
	var bar := _skill_bar
	for i in 3:
		var slot = bar.get_node("Skill%dSlot" % (i + 1))
		slot.set_locked(not unlocked[i])
		if unlocked[i]:
			slot.set_unlock_available(false)
	game.economy.update_shop_ui()
