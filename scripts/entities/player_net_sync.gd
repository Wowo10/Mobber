extends Node

# PlayerNetSync — the player's RPC message-passing layer. Lives as a child node
# of each Player so Godot routes RPCs by the stable node path .../Player_<id>/NetSync.
#
# What lives here: the input RPCs (client → server) plus their server-side input
# buffers, every visual/broadcast RPC that mirrors an archetype ability or sword/
# dash/spin effect to the other peers, and the upgrade/debuff/skill-unlock
# appliers. All of these are pure message passing — they read no per-packet player
# state and only poke the player (via its public surface) or the archetype handler.
#
# What deliberately stays on player.gd: _rpc_sync_pos, the snapshot buffer +
# interpolation, prediction/reconciliation, the camera and _rpc_shake_camera, and
# _physics_process/_draw. That is the simulation core, not a separable layer —
# moving it would make this node write ~10 player fields every position packet.
#
# Authority: MultiplayerSpawner does not replicate authority, and this child does
# not inherit the player's. player._ready calls set_multiplayer_authority(peer_id)
# on this node too, so the authority guards below (and get_multiplayer_authority())
# match the player's.

var player: CharacterBody2D

# Server-side input buffers — written by the input RPCs, consumed each physics
# tick by player._physics_process (Path B).
var _received_direction := Vector2.ZERO
var _received_facing := Vector2.RIGHT
var _pending_attack := false
var _pending_dash := false
var _pending_skill1 := false
var _pending_skill2 := false
var _pending_skill3 := false

func _ready() -> void:
	player = get_parent()

# --- Input RPCs (client → server) ---

@rpc("any_peer", "unreliable_ordered")
func _rpc_send_direction(direction: Vector2) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	_received_direction = direction

@rpc("any_peer", "unreliable_ordered")
func _rpc_send_facing(f: Vector2) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	_received_facing = f

@rpc("any_peer", "reliable")
func _rpc_send_action(action_mask: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	if action_mask & 1: _pending_attack = true
	if action_mask & 2: _pending_dash   = true
	if action_mask & 4:  _pending_skill1 = true
	if action_mask & 8:  _pending_skill2 = true
	if action_mask & 16: _pending_skill3 = true

# --- Upgrade / debuff / skill-unlock RPCs ---

@rpc("any_peer", "reliable")
func rpc_apply_speed_level(level: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	player.speed_level = level

@rpc("any_peer", "reliable")
func rpc_apply_damage_level(level: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	player.damage_level = level
	player.apply_upgrades_to_sword()

@rpc("any_peer", "reliable")
func rpc_apply_sword_size_level(level: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	player.sword_size_level = level
	player.apply_upgrades_to_sword()

@rpc("any_peer", "reliable")
func rpc_apply_attack_speed_level(level: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	player.attack_speed_level = level
	player.apply_upgrades_to_sword()

@rpc("any_peer", "reliable")
func rpc_apply_skill1_level(level: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	player.skill1_level = level
	player.apply_skill_upgrades()

@rpc("any_peer", "reliable")
func rpc_apply_skill2_level(level: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	player.skill2_level = level
	player.apply_skill_upgrades()

@rpc("any_peer", "reliable")
func rpc_apply_skill3_level(level: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	player.skill3_level = level
	player.apply_skill_upgrades()

@rpc("any_peer", "reliable")
func rpc_sync_skills_unlocked(unlocked: Array) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	player.skills_unlocked = unlocked

@rpc("any_peer", "reliable")
func rpc_apply_debuff(type: int, duration: float) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	match type:
		Constants.DEBUFF_NO_DASH: player.debuff_no_dash_timer = duration
		Constants.DEBUFF_SILENCE: player.debuff_silence_timer = duration
		Constants.DEBUFF_INVERT:  player.debuff_invert_timer  = duration

# --- Broadcast helpers (called by archetype handlers) ---

func broadcast_swing(angle: float) -> void:
	rpc_trigger_swing.rpc(angle)

func broadcast_cannonball(pos: Vector2, dir: Vector2, homing: bool) -> void:
	var networked := not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if networked and multiplayer.is_server():
		rpc_spawn_cannonball.rpc(pos, dir, homing)

# --- Visual / sync RPCs ---

@rpc("any_peer", "reliable")
func rpc_spawn_cannonball(pos: Vector2, dir: Vector2, homing: bool) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypePirate).spawn_visual_cannonball(pos, dir, homing)

@rpc("any_peer", "reliable")
func rpc_place_turret(pos: Vector2, fac: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypePirate).place_visual_turret(pos, fac)

@rpc("any_peer", "reliable")
func rpc_place_pirate_barrel(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypePirate).spawn_barrel_local(pos, true)

@rpc("any_peer", "reliable")
func rpc_detonate_pirate_barrel() -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypePirate).detonate_visual_barrel()

@rpc("any_peer", "reliable")
func rpc_knight_shield_bash(pos: Vector2, dir: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypePaladin).spawn_bash_visual(pos, dir)

@rpc("any_peer", "reliable")
func rpc_spawn_consecration(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypePaladin).spawn_consecration_local(pos, true)

@rpc("any_peer", "reliable")
func rpc_spawn_mage_bolt(pos: Vector2, dir: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	if is_multiplayer_authority():
		return
	(player.get_archetype_handler() as ArchetypeMage).spawn_bolt_local(pos, dir, true)

@rpc("any_peer", "reliable")
func rpc_spawn_rain(pos: Vector2, rs: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeMage).spawn_rain_local(pos, true, rs)

@rpc("any_peer", "reliable")
func rpc_spawn_fireball(pos: Vector2, dir: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeMage).spawn_fireball_local(pos, dir, true)

@rpc("any_peer", "reliable")
func rpc_spawn_cyber_bullet(pos: Vector2, dir: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	if is_multiplayer_authority():
		return
	(player.get_archetype_handler() as ArchetypeCyborg).spawn_bullet_local(pos, dir, true)

@rpc("any_peer", "reliable")
func rpc_spawn_cyber_ray(pos: Vector2, facing: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeCyborg).spawn_ray_local(pos, facing, true)

@rpc("any_peer", "reliable")
func rpc_set_cyborg_ranged_mode(active: bool) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeCyborg).set_ranged_mode(active)

@rpc("any_peer", "reliable")
func rpc_shadowstep_visual(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeAssassin).spawn_visual_at(pos)

@rpc("any_peer", "reliable")
func rpc_set_berserker_rage(active: bool) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeBerserker).set_rage(active)

@rpc("any_peer", "reliable")
func rpc_spawn_ground_slam(pos: Vector2, slam_radius: float = -1.0) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeBerserker).spawn_slam_local(pos, true, -1.0, slam_radius)

@rpc("any_peer", "reliable")
func rpc_spawn_warlock_bolt(pos: Vector2, dir: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	if is_multiplayer_authority():
		return
	(player.get_archetype_handler() as ArchetypeWarlock).spawn_bolt_local(pos, dir, true)

@rpc("any_peer", "reliable")
func rpc_spawn_wisp_bolt(pos: Vector2, dir: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	if is_multiplayer_authority():
		return
	(player.get_archetype_handler() as ArchetypeWarlock).spawn_wisp_bolt_visual(pos, dir)

@rpc("any_peer", "reliable")
func rpc_spawn_drain_life() -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeWarlock).spawn_drain_local(true)

@rpc("any_peer", "reliable")
func rpc_spawn_void_rift(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeWarlock).spawn_rift_local(pos, true)

@rpc("any_peer", "reliable")
func rpc_spawn_fan_of_knives(pos: Vector2, facing_angle: float) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	if is_multiplayer_authority():
		return
	(player.get_archetype_handler() as ArchetypeAssassin).spawn_fan_local(pos, facing_angle, true)

@rpc("any_peer", "reliable")
func rpc_place_warlock_portal(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeWarlock).place_visual_portal(pos)

@rpc("any_peer", "reliable")
func rpc_consume_warlock_portal() -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeWarlock).consume_visual_portal()

@rpc("any_peer", "reliable")
func rpc_mage_force_pull(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeMage).spawn_pull_visual(pos)

@rpc("any_peer", "reliable")
func rpc_spawn_arcane_implosion(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeMage).spawn_implosion_local(pos, true)

@rpc("any_peer", "reliable")
func rpc_set_cyborg_overclock(active: bool) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeCyborg).set_overclock(active)

@rpc("any_peer", "reliable")
func rpc_spawn_berserker_mini_smash(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeBerserker).spawn_mini_smash_local(pos, true)

@rpc("any_peer", "reliable")
func rpc_berserker_set_hit_count(count: int) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeBerserker).set_hit_count(count)

@rpc("any_peer", "reliable")
func rpc_spawn_assassin_trap(pos: Vector2) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeAssassin).spawn_trap_local(pos, true)

@rpc("any_peer", "reliable")
func rpc_spawn_warlock_wisp() -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	(player.get_archetype_handler() as ArchetypeWarlock).spawn_wisp_local(true)

@rpc("any_peer", "unreliable_ordered")
func _rpc_set_dash_particles(dir: Vector2, emitting: bool) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	var p := player.get_node("DashParticles")
	p.direction = dir
	p.emitting = emitting

@rpc("any_peer", "reliable")
func rpc_trigger_swing(facing_angle: float) -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	player.get_node("Sword").swing(facing_angle)

@rpc("any_peer", "reliable")
func rpc_trigger_spin_start() -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	player.spinning = true
	player.spin_timer = ArchetypePaladin.SPIN_DURATION
	player.get_node("Sword").enter_spin()
	if is_multiplayer_authority():
		player._spin_loop_timer = 0.0
		player.get_node("SfxSpin").play()

@rpc("any_peer", "reliable")
func _rpc_trigger_spin_stop() -> void:
	var _s := multiplayer.get_remote_sender_id()
	if _s != 0 and _s != 1:
		return
	player.spinning = false
	player.get_node("Sword").exit_spin()
