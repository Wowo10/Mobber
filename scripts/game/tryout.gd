extends Node

const PLAYER_SCENE = preload("res://scenes/entities/player.tscn")
const DamageDummy = preload("res://scripts/entities/damage_dummy.gd")
const INITIAL_MOB_COUNT = 5

var _player: Node = null

func _ready() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_setup_skill_bar()
	spawn_player()
	_player.skills_unlocked = [true, true, true]
	_sync_skill_bar_unlocks()
	var center := Vector2(Constants.WORLD_SIZE_X * 0.5, Constants.WORLD_SIZE_Y * 0.5)
	$Arena.spawn_mob(0, center)
	for i in INITIAL_MOB_COUNT - 1:
		$Arena.spawn_mob()
	_update_mob_label()
	_spawn_dummy()
	$HUD/ReturnButton.pressed.connect(_on_return_pressed)

func _spawn_dummy() -> void:
	var dummy = DamageDummy.new()
	dummy.position = Vector2(Constants.WORLD_SIZE_X * 0.5 - 300.0, Constants.WORLD_SIZE_Y * 0.5)
	add_child(dummy)

func _on_return_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")

func notify_mob_killed(_arena: Node2D, _killer: Node = null) -> void:
	$Arena.spawn_mob()
	$Arena.spawn_mob()
	call_deferred("_update_mob_label")

func _update_mob_label() -> void:
	$HUD/MobCountLabel.text = "Mobs: %d" % $Arena.get_mob_count()

func _make_archetype(arch_id: int) -> ArchetypeBase:
	match arch_id:
		Constants.ARCHETYPE_PALADIN:   return ArchetypePaladin.new()
		Constants.ARCHETYPE_PIRATE:    return ArchetypePirate.new()
		Constants.ARCHETYPE_MAGE:      return ArchetypeMage.new()
		Constants.ARCHETYPE_CYBORG:    return ArchetypeCyborg.new()
		Constants.ARCHETYPE_ASSASSIN:  return ArchetypeAssassin.new()
		Constants.ARCHETYPE_BERSERKER: return ArchetypeBerserker.new()
		Constants.ARCHETYPE_WARLOCK:   return ArchetypeWarlock.new()
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
	s1.icon_color = arch.get_skill1_color()
	s1.icon = arch.get_skill1_icon()
	s2.icon_color = arch.get_skill2_color()
	s2.icon = arch.get_skill2_icon()
	s3.icon_color = arch.get_skill3_color()
	s3.icon = arch.get_skill3_icon()
	s1.tooltip_text = arch.get_skill1_name() + "\n" + arch.get_skill1_description()
	s2.tooltip_text = arch.get_skill2_name() + "\n" + arch.get_skill2_description()
	s3.tooltip_text = arch.get_skill3_name() + "\n" + arch.get_skill3_description()

func _sync_skill_bar_unlocks() -> void:
	var bar := $HUD/SkillBar
	for i in 3:
		bar.get_node("Skill%dSlot" % (i + 1)).set_locked(false)

func spawn_player() -> void:
	var center := Vector2(Constants.WORLD_SIZE_X * 0.5, Constants.WORLD_SIZE_Y * 0.5)
	var player := PLAYER_SCENE.instantiate()
	player.name = "Player_1"
	player.position = $Arena.position + center
	player.archetype = PlayerPrefs.archetype
	player.player_name = PlayerPrefs.player_name
	$PlayerContainer.add_child(player)
	player.set_multiplayer_authority(1)
	_player = player

func _process(_delta: float) -> void:
	$HUD/FpsLabel.text = "%d fps" % int(Engine.get_frames_per_second())
	if _player == null:
		return
	var bar := $HUD/SkillBar
	var attack_node = bar.get_node("AttackSlot")
	attack_node.set_cooldown(_player.attack_cooldown, Constants.SWORD_SWING_DURATION)
	var p_arch: ArchetypeBase = _player.get_archetype_handler()
	var dyn_icon: Texture2D = p_arch.get_attack_icon()
	if dyn_icon:
		attack_node.icon = dyn_icon
		attack_node.icon_color = p_arch.get_attack_color()
	var dash_slot = bar.get_node("DashSlot")
	dash_slot.set_cooldown(_player.dash_cooldown, Constants.PLAYER_DASH_COOLDOWN)
	var no_dash_active: bool = _player.debuff_no_dash_timer > 0.0
	if dash_slot.debuffed != no_dash_active:
		dash_slot.debuffed = no_dash_active
		dash_slot.queue_redraw()
	var silence_active: bool = _player.debuff_silence_timer > 0.0
	var s1_node = bar.get_node("Skill1Slot")
	var s2_node = bar.get_node("Skill2Slot")
	s1_node.set_cooldown(_player.skill1_cooldown, _player.skill1_max_cooldown)
	s2_node.set_cooldown(_player.skill2_cooldown, _player.skill2_max_cooldown)
	if s1_node.debuffed != silence_active:
		s1_node.debuffed = silence_active
		s1_node.queue_redraw()
	if s2_node.debuffed != silence_active:
		s2_node.debuffed = silence_active
		s2_node.queue_redraw()
	var s3_node = bar.get_node("Skill3Slot")
	s3_node.set_cooldown(_player.skill3_cooldown, _player.skill3_max_cooldown)
	s3_node.set_passive_counter(_player.get_passive_counter())
	if s3_node.debuffed != silence_active:
		s3_node.debuffed = silence_active
		s3_node.queue_redraw()
