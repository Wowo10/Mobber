extends Node

const WORLD_SIZE_X = 4000
const WORLD_SIZE_Y = 3000
const ARENA_GAP = 300
const NET_PORT = 7777
const SIGNALING_URL = "wss://mobber.onrender.com"
const FORCE_WEBRTC = true   # set false before shipping; true forces WebRTC even on desktop
const PLAYER_SPEED = 300.0
const PLAYER_START_RADIUS = 30.0
const FOOD_RADIUS = 5.0
const FOOD_COUNT = 200

const MOB_RADIUS = 15.0
const MOB_SPEED = 120.0
const MOB_MAX_HEALTH = 30.0
const MOB_WANDER_INTERVAL = 2.0
const MOB_COUNT = 5

const PLAYER_DASH_SPEED = 2400.0
const PLAYER_DASH_DURATION = 0.1
const PLAYER_DASH_COOLDOWN = 0.8

const SWORD_DAMAGE = 10.0
const SWORD_LENGTH = 45.0
const SWORD_WIDTH = 8.0
const SWORD_SWING_DURATION = 0.25
const SWORD_ARC_HALF = 70.0

const MOB_PUSH_FORCE = 140.0      # must exceed MOB_FRICTION/60 or contact push cancels out
const MOB_KNOCKBACK = 5000.0
const MOB_FRICTION = 1500.0      # higher = faster stop after knockback
const MOB_MAX_EXTERNAL_SPEED = 600.0