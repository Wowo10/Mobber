extends Node

var archetype: int = 0  # 0 = Knight, 1 = Pirate
var mob_win_count: int = 50
var peer_teams: Dictionary = {}  # peer_id -> 0 (Arena1/Team1) or 1 (Arena2/Team2)
var room_code: String = ""
