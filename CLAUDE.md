# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Mobber** — an agar.io-style arena game built in Godot 4.5 (GDScript, GL Compatibility renderer, 1280×720 viewport).

## Running the game

```bash
# Run from terminal (headless not supported — opens the Godot window)
godot --path /home/wowo/projects/godot/mobber

# Or open the project in the Godot editor and press F5
```

There is no separate build step, linter, or test runner. The editor itself is the development environment.

## Architecture

Scenes and scripts mirror each other's folder structure:

| Scene | Script | Role |
|---|---|---|
| `scenes/game/game.tscn` | `scripts/game/game.gd` | Main scene — draws arena grid and boundary, owns all world nodes |
| `scenes/entities/player.tscn` | `scripts/entities/player.gd` | Player entity — `CharacterBody2D`, self-drawn circle, arrow-key movement, attached `Camera2D` |

**`autoloads/Constants.gd`** is the global singleton (registered as `Constants`) for shared game tuning values: world size, player speed, radii, food count. Add new shared constants here rather than hardcoding them per-script.

### Key design notes

- The player draws itself via `_draw()` (no Sprite2D) — radius and color are properties on the node, making them easy to change dynamically as the player grows.
- `Camera2D` is a child of the Player node, so the viewport follows the player automatically.
- Arena walls are `WorldBoundaryShape2D` collision shapes on a `StaticBody2D`; the player is kept inside by physics, not by clamping (the clamping code in `player.gd` is currently commented out).
- `Constants.PLAYER_SPEED` (300) exists but `player.gd` currently uses its own local `SPEED = 800`. Consolidate to `Constants` when tuning movement.

## Game plan

### Concept

Two-arena competitive game. Each player owns one arena. Mobs spawn in both arenas (starting with one each). When a player kills a mob, two mobs spawn at random positions in the **opponent's** arena. First player to accumulate 100 mobs in their arena loses.

The player has a basic melee attack. The server is authoritative: it validates input, runs hit detection, and broadcasts game state to both clients.

### Networking approach

Use **Godot's built-in `ENetMultiplayerPeer`** — no separate server process needed. One player calls `create_server()`, the other calls `create_client(ip)`. The host runs server logic in the same process. Start with direct IP connection; add a relay/matchmaking layer (Go server) only if room codes or NAT traversal become necessary. A Go server would only handle connection brokering — never game logic, since that would duplicate all hit detection and spawning in a second language.

### Design patterns to follow

**RPC discipline** — Use `@rpc` annotations explicitly. Clients send only *input* to the server (never positions or kill events). Server sends *state* to clients.

```gdscript
# Client → Server: inputs only
@rpc("any_peer", "reliable")
func send_input(direction: Vector2, attacking: bool): ...

# Server → Clients: authoritative state
@rpc("authority", "unreliable_ordered")
func sync_state(pos: Vector2, mob_positions: Array): ...
```

**Server authority** — All game logic (movement correction, hit detection, mob spawning, win condition) runs on the peer with `multiplayer.is_server()`. Clients are display-only and send input.

**Scene ownership** — Each arena is its own scene instance. The server owns (and runs physics for) both arenas. Clients only see their own arena's viewport; the server tracks both.

**Mob spawning** — Use `MultiplayerSpawner` to replicate mob nodes automatically. The server spawns/despawns; the spawner propagates to clients. Avoid manual `add_child` + RPC for spawning.

**Peer IDs** — Assign arena ownership by peer ID: `multiplayer.get_unique_id()`. Store a mapping `{ peer_id: arena_node }` on the server to route kill events and mob spawns correctly.

### Implementation steps (rough order)

1. Add a basic melee hitbox to the player (Area2D, swing animation optional).
2. Create a `Mob` scene (CharacterBody2D, simple wandering AI, health).
3. Build a `GameServer` singleton that owns both arenas, handles mob spawning, tracks counts.
4. Wire up `ENetMultiplayerPeer` with a host/join UI (two buttons: Host / Join + IP field).
5. Implement server-authoritative movement: client sends direction input, server moves the character, broadcasts position.
6. Implement kill → spawn-2-in-opponent's-arena logic on the server.
7. Add win condition check (mob count ≥ 100) and game-over RPC.
