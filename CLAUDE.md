# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Mobber** — a competitive two-arena arena game built in Godot 4.6 (GDScript, GL Compatibility renderer, 1280×720 viewport).

Two players (or two teams) each defend their own arena. Mobs accumulate; when a player kills a mob, two more spawn in the **opponent's** arena. The first arena to reach `PlayerPrefs.mob_win_count` mobs **loses**. Players earn gold per kill and spend it in a shop (self-upgrades) or at an "Arena Master" station (send mobs / debuffs to the opponent). Each player picks one of seven archetypes with distinct attacks, dashes, and three unlockable skills.

## Running the game

```bash
# Opens the Godot window (headless not supported)
godot --path /home/wowo/projects/godot/clone-mob

# Or open the project in the Godot editor and press F5
```

There is no separate build step, linter, or test runner. The editor itself is the development environment. The main scene is the **lobby** (`scenes/ui/lobby.tscn`).

## Scene flow

```
lobby.tscn  ──Host/Join──►  game_room.tscn  ──Start──►  game.tscn
   │                         (team assignment,
   │                          archetype, win count)
   └──Tryout──►  tryout.tscn   (offline solo practice vs a damage dummy)
```

- **lobby** — name / archetype / control-scheme selection; Host or Join (room code). Wires `WebRTCSignaling`.
- **game_room** — pre-game: host sees a Start button, assigns teams/arenas, sets `mob_win_count`. Players pick archetype. Spectators supported.
- **game** — the match. Owns `Arena1` + `Arena2`, the HUD, shop & arena-master panels, scoreboard, game-over overlay.
- **tryout** — offline sandbox (`OfflineMultiplayerPeer`), all skills pre-unlocked, a `damage_dummy` for testing.

## Architecture

Scenes and scripts mirror each other's folder structure under `scenes/` and `scripts/`.

| Path | Role |
|---|---|
| `scripts/game/game.gd` | Match controller — both arenas, HUD, shop/arena-master economy, skill unlocks, win condition, host migration, scoreboard |
| `scripts/game/arena.gd` | One arena (`Node2D`) — walls, floor, shop/master zones, mob spawning + mob-state network sync, frenzy debuff |
| `scripts/game/spectator_camera.gd` | Free camera for spectators (Tab switches arena) |
| `scripts/entities/player.gd` | `CharacterBody2D` — self-drawn droplet, movement, dash, the three input/sim paths, all visual/sync RPCs |
| `scripts/entities/mob.gd` | `CharacterBody2D` — BASIC / FLEEING / BOSS types, wander/flee/chase AI, knockback, client interpolation |
| `scripts/entities/sword.gd` | Melee swing/spin hitbox attached to the player |
| `scripts/entities/damage_dummy.gd` | Stationary target for tryout mode |
| `scripts/archetypes/archetype_base.gd` | `ArchetypeBase` (RefCounted) — base class for the 7 archetypes; defines attack/dash/skill hooks |
| `scripts/archetypes/archetype_*.gd` | Per-archetype handlers (paladin, pirate, mage, cyborg, assassin, berserker, warlock) |
| `scripts/archetypes/projectile_base.gd` + `scripts/archetypes/<arch>/*.gd` | Per-archetype projectiles/abilities (fireball, cannonball, trap, void rift, etc.) |
| `scripts/ui/*.gd` | Lobby, game_room, skill bar/slots, mob bars, indicators, skill-unlock panel, debuff indicator |
| `scripts/utils/particle_utils.gd` | `ParticleUtils` — shared particle setup/polish helper |

### Autoloads (singletons)

- **`Constants`** (`autoloads/Constants.gd`) — all tuning values: world size, speeds, radii, mob stats, archetype IDs, shop/debuff costs and effects, skill cooldowns. **Add new shared constants here, not hardcoded per-script.**
- **`WebRTCSignaling`** (`autoloads/WebRTCSignaling.gd`) — full WebSocket signaling client + WebRTC offer/answer/ICE handshake. Emits `lobby_created`, `game_ready`, `error`.
- **`PlayerPrefs`** — in-memory session state shared across scenes: `archetype`, `control_scheme`, `mob_win_count`, `peer_teams` (peer_id → arena 0/1), `peer_names`, `peer_spectators`, `room_code`, `player_name`.

## Networking

**WebRTC via `WebRTCMultiplayerPeer`** with a WebSocket signaling server (`Constants.SIGNALING_URL` = `wss://mobber.onrender.com`). One player hosts (`create_server()`); others join with a room code. Signaling only brokers connection setup — all game logic is peer-to-peer. The host is peer `1` and is the authority.

### Server authority + the three simulation paths

`player.gd::_physics_process` branches into:

- **Path A — Offline** (`OfflineMultiplayerPeer`): read input, full local sim, no RPCs.
- **Path B — Server**: simulate every player authoritatively. Own player reads input; others consume buffered input from client RPCs (`_received_direction`, `_pending_*`). Spawns attacks/skills, broadcasts position via `_rpc_sync_pos`.
- **Path C — Client (own player)**: predict movement locally, send only *input* to the server (`_rpc_send_direction` / `_rpc_send_facing` / `_rpc_send_action`). Visual-only skill prediction; no authoritative spawning.

**RPC discipline** — clients send input only; server sends state only. RPC handlers guard on `multiplayer.is_server()` and validate `get_remote_sender_id()`.

### Prediction & interpolation

- `Constants.CLIENT_PREDICTION` toggles own-player local prediction. With it on, the client trusts local sim and only reconciles on drift (`CORRECTION_THRESHOLD`) or snaps on large desync (`SNAP_THRESHOLD`, e.g. teleports).
- **Observed (remote) players** are rendered from a snapshot buffer interpolated `OBSERVED_INTERP_DELAY` behind real-time (no velocity extrapolation → no snap-back when they stop). See `player.gd::_sample_snapshot_buffer`.
- **Mobs** sync the same way: `arena.gd` broadcasts mob `(id, pos, vel)` at ~60 Hz, skipping mobs that moved < `MOVE_THRESHOLD_SQ`; clients interpolate in `mob.gd` and locally predict player-push.

### Mob spawning

`arena.gd` owns a `MultiplayerSpawner` (`MobContainer` spawn path). `spawn_mob(type, near_pos)` runs server-side only; the spawner replicates nodes to clients. Each mob carries `mob_worth` (BOSS counts more); `get_mob_count()` sums worth, and that total drives the HUD and win check.

### Host disconnect

There is no host migration — if the host vanishes mid-match the match ends. The host pulses a heartbeat (`net_sync.gd::_rpc_heartbeat`); clients run a watchdog (`update_host_liveness`) and, when it goes silent past `SERVER_TIMEOUT` (or `server_disconnected` fires), call `net_sync.gd::_show_host_left`. That scrubs multiplayer signal hooks (Godot 4.x `SceneCacheInterface` cleanup), drops the dead peer, and shows the game-over overlay with the final scoreboard and a Return-to-lobby button. A *non-host* peer leaving is handled separately by `net_sync.gd::_on_peer_disconnected` (gold redistribution, ghosting, arena-empty win check).

## Economy & progression

- **Kills** grant `Constants.KILL_REWARD` gold (tracked per peer in `_peer_money`).
- **Shop zone** (`SHOP_ZONE_RECT` in arena): self-upgrades — Speed / Damage / Sword Size / Attack Speed and the three skills. Escalating costs (`base + level * inc`), capped at `SHOP_UPGRADE_MAX_LEVEL`.
- **Arena Master zone** (`ARENA_MASTER_ZONE_RECT`): offensive purchases sent to the *opponent's* arena — send 1/3 mobs, a fleeing mob, a boss, upgrade enemy mob HP, and four debuffs (No-Dash, Frenzy, Silence, Invert). Item IDs and costs live in `Constants`; resolution is `game.gd::_apply_purchase`.
- **Skill unlocks** — each player unlocks one of three skills when their arena's mob count crosses `SKILL_UNLOCK_THRESHOLDS` (10% / 40% / 70% of win count). Server-tracked in `_player_unlock_milestone` / `_player_unlocks_pending`; player chooses which skill via the skill bar (or Ctrl+1/2/3).

## Conventions

- **Player draws itself** via `_draw()` (a droplet polygon facing `last_facing`) — no Sprite2D; `radius`/`color` are node properties. Mobs likewise self-draw.
- **Archetypes are RefCounted handlers**, not nodes. `player.gd::_apply_archetype` (and `game.gd::_make_archetype`) instantiate by `Constants.ARCHETYPE_*` ID. Add behavior by overriding `ArchetypeBase` hooks (`use_attack`, `use_dash`, `use_skill1..3`, the `*_client_predict` and `spawn_*_local` visual helpers) rather than editing `player.gd`.
- Arena walls are `StaticBody2D` `RectangleShape2D` collision built in `arena.gd::_build_walls`; mobs use physics layer `Constants.MOB_COLLISION_LAYER`.
- `player.gd` uses a local `SPEED = 800`; `Constants.PLAYER_SPEED` (300) still exists but is unused — consolidate when tuning.
- `PlayerPrefs.archetype` comment says "0 = Knight" but ID 0 is **Paladin** (`Constants.ARCHETYPE_NAMES`); the knight assets back the Paladin handler.
