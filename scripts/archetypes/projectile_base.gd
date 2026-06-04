class_name ProjectileBase
extends Area2D

var direction := Vector2.RIGHT
var player_ref: Node = null
var visual_only := false
var _distance_traveled := 0.0

func _check_hit(from: Vector2) -> void:
	var space := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(from, global_position)
	if player_ref != null:
		params.exclude = [player_ref.get_rid()]
	var result := space.intersect_ray(params)
	if result.is_empty():
		return
	var body: Node2D = result["collider"]
	if not body.has_method("take_damage"):
		return
	_on_hit(body)

func _on_hit(_body: Node2D) -> void:
	pass
