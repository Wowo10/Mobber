extends Node

const SCHEME_KEYBOARD := 0
const SCHEME_MOUSE    := 1
const SCHEME_PAD      := 2

var archetype: int = 0  # 0 = Knight, 1 = Pirate
var control_scheme: int = 0
var mob_win_count: int = 120
var peer_teams: Dictionary = {}  # peer_id -> 0 (Arena1/Team1) or 1 (Arena2/Team2)
var room_code: String = ""
var player_name: String = ""
var peer_names: Dictionary = {}  # peer_id -> String
var peer_spectators: Array = []  # peer_ids of spectating peers
