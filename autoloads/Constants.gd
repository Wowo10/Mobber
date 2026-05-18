extends Node

const WORLD_SIZE_X = 2667
const WORLD_SIZE_Y = 2000
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
const MOB_WIN_COUNT = 50

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

const MOB_FLEE_SPEED = 220.0
const MOB_FLEE_MAX_HEALTH = 1.0
const MOB_FLEE_RADIUS = 9.0

const ARCHETYPE_KNIGHT = 0
const ARCHETYPE_PIRATE = 1

const SKILL_SPIN_DURATION = 2.5
const SKILL_SPIN_SPEED = TAU * 3.0   # ~18.8 rad/s, ~3 rotations/sec
const SKILL_SPIN_DAMAGE = SWORD_DAMAGE
const SKILL_SPIN_KNOCKBACK = 1800.0
const SKILL_SPIN_HIT_INTERVAL = 0.4  # minimum seconds between hits on the same mob
const SKILL_SPIN_COOLDOWN = 7.0
const SKILL_WARCRY_DURATION = 3.0
const SKILL_WARCRY_SPEED_MULT = 1.7
const SKILL_WARCRY_COOLDOWN = 9.0
const SKILL_CANNON_SPEED = 1200.0
const SKILL_CANNON_RANGE = 800.0
const SKILL_CANNON_DAMAGE = 20.0
const SKILL_CANNON_KNOCKBACK = 10000.0
const SKILL_CANNON_COOLDOWN = 3.5
const SKILL_CANNON_TURN_SPEED = 4.5  # lerp rate for homing steering
const SKILL_BLINK_DISTANCE = 220.0
const SKILL_BLINK_COOLDOWN = 5.0