extends Area2D
class_name ProjectileBase

var direction := Vector2.RIGHT
var player_ref: Node = null
var visual_only := false
var _distance_traveled := 0.0

# Lateral tolerance (px) applied to server-authoritative projectiles to compensate
# for mob position drift between client fire and server execution (~1-2 physics frames).
const _NET_HIT_TOLERANCE := 22.0

func _check_hit(from: Vector2) -> void:
	var space := get_world_2d().direct_space_state
	if not visual_only:
		var seg := global_position - from
		var seg_len := seg.length()
		if seg_len < 0.5:
			return
		var params := PhysicsShapeQueryParameters2D.new()
		var cap := CapsuleShape2D.new()
		cap.radius = _NET_HIT_TOLERANCE
		cap.height = seg_len + _NET_HIT_TOLERANCE * 2.0
		params.shape = cap
		params.transform = Transform2D(seg.angle() - PI * 0.5, (from + global_position) * 0.5)
		if player_ref != null:
			params.exclude = [player_ref.get_rid()]
		for hit in space.intersect_shape(params, 8):
			var body: Node2D = hit["collider"]
			if body.has_method("take_damage"):
				_on_hit(body)
				return
	else:
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

func _add_trail(color: Color, scale_min: float = 0.3, scale_max: float = 0.8, amount: int = 10, lifetime: float = 0.20) -> void:
	var p := CPUParticles2D.new()
	p.emitting = true
	p.one_shot = false
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.0
	p.spread = 180.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 20.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = scale_min
	p.scale_amount_max = scale_max
	p.color = color
	ParticleUtils.polish(p)
	add_child(p)
