class_name ParticleUtils

static func polish(p: CPUParticles2D) -> void:
	p.texture = _make_circle_texture()
	var sc := _make_shrink_curve()
	p.scale_curve_x = sc
	p.scale_curve_y = sc
	p.color_ramp = _make_fade_gradient()
	p.damping_min = 80.0
	p.damping_max = 180.0

static func _make_circle_texture(size: int = 16) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var radius := size * 0.5 - 0.5
	for y in size:
		for x in size:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var alpha := clampf(radius - dist + 1.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)

static func _make_shrink_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	return c

static func _make_fade_gradient() -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	return g
