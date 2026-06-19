class_name ArchetypeData
extends Resource

## Pure tuning + visual data for one archetype. Behavior (use_skill*, use_dash,
## physics_process, spawn helpers) stays in the archetype_*.gd handler; this holds
## only the values the base-class getters read. See ArchetypeBase.

@export_group("General")
@export var color := Color.WHITE
@export var speed_mult := 0.8          ## base move speed multiplier (dynamic archetypes still override get_speed_mult)
@export var dash_duration := 0.1       ## defaults mirror Constants.PLAYER_DASH_DURATION

@export_group("Sword")
@export var sword_damage := 10.0       ## defaults mirror Constants.SWORD_* base values
@export var sword_length := 45.0
@export var sword_width := 8.0
@export var sword_swing_duration := 0.25

@export_group("Attack")
@export var attack_color := Color(0.9, 0.65, 0.15)
@export var attack_icon: Texture2D
@export_multiline var attack_description := "Melee swing."

@export_group("Dash")
@export var dash_color := Color(0.25, 0.55, 1.0)
@export var dash_icon: Texture2D
@export_multiline var dash_description := "Dash in movement direction."

@export_group("Skill 1")
@export var skill1_name := "Skill 1"
@export var skill1_color := Color.WHITE
@export var skill1_icon: Texture2D
@export_multiline var skill1_description := ""
@export var skill1_cooldown := 1.0     ## base cooldown; level scaling applied in ArchetypeBase

@export_group("Skill 2")
@export var skill2_name := "Skill 2"
@export var skill2_color := Color.WHITE
@export var skill2_icon: Texture2D
@export_multiline var skill2_description := ""
@export var skill2_cooldown := 1.0

@export_group("Skill 3")
@export var skill3_name := "Skill 3"
@export var skill3_color := Color.WHITE
@export var skill3_icon: Texture2D
@export_multiline var skill3_description := ""
@export var skill3_cooldown := 1.0
