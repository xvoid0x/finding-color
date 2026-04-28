extends Node
## CrackTextureGen — Autoload
## Generates a procedural crack texture at runtime and caches it.
## Enemies call CrackTextureGen.get_texture() to get their crack map.
##
## The texture is a greyscale noise pattern with vein-like dark channels
## that the enemy_crack.gdshader uses as its crack_texture uniform.
## Brighter pixels = more crack revealed at that spot.

const TEXTURE_SIZE: int = 64

var _crack_texture: ImageTexture = null


func _ready() -> void:
	_crack_texture = _generate_crack_texture()
	print("[CRACK_GEN] Procedural crack texture generated (%dx%d)" % [TEXTURE_SIZE, TEXTURE_SIZE])


func get_texture() -> ImageTexture:
	return _crack_texture


func _generate_crack_texture() -> ImageTexture:
	var img := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_L8)

	# Fill with a value noise base — random greyscale
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345  # Fixed seed so it's consistent across runs

	# Start with dark background
	img.fill(Color(0.1, 0.1, 0.1))

	# Draw several crack "veins" as random walks across the texture
	var num_veins: int = 8
	for _v in range(num_veins):
		var x: float = rng.randf_range(0.1, 0.9) * TEXTURE_SIZE
		var y: float = rng.randf_range(0.1, 0.9) * TEXTURE_SIZE
		var angle: float = rng.randf() * TAU
		var length: int = rng.randi_range(20, 50)
		var thickness: float = rng.randf_range(0.5, 2.0)

		for step in range(length):
			# Slight random jitter to angle (crack curves)
			angle += rng.randf_range(-0.4, 0.4)

			x += cos(angle) * 1.2
			y += sin(angle) * 1.2

			var px: int = int(x) % TEXTURE_SIZE
			var py: int = int(y) % TEXTURE_SIZE
			if px < 0: px += TEXTURE_SIZE
			if py < 0: py += TEXTURE_SIZE

			# Paint the crack bright (shader uses .r channel)
			var brightness: float = rng.randf_range(0.7, 1.0)
			_paint_circle(img, px, py, thickness, brightness)

			# Branch occasionally
			if rng.randf() < 0.08 and step > 5:
				var branch_angle: float = angle + rng.randf_range(0.5, 1.2) * (1.0 if rng.randf() > 0.5 else -1.0)
				var bx: float = x
				var by: float = y
				var branch_len: int = rng.randi_range(5, 15)
				for _b in range(branch_len):
					branch_angle += rng.randf_range(-0.3, 0.3)
					bx += cos(branch_angle) * 1.2
					by += sin(branch_angle) * 1.2
					var bpx: int = int(bx) % TEXTURE_SIZE
					var bpy: int = int(by) % TEXTURE_SIZE
					if bpx < 0: bpx += TEXTURE_SIZE
					if bpy < 0: bpy += TEXTURE_SIZE
					_paint_circle(img, bpx, bpy, thickness * 0.6, brightness * 0.85)

	# Soften slightly so cracks blend smoother
	# (Godot Image doesn't have a blur — tile the texture and let the shader smooth it)

	var tex := ImageTexture.create_from_image(img)
	return tex


func _paint_circle(img: Image, cx: int, cy: int, radius: float, value: float) -> void:
	var r: int = int(ceil(radius))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= radius * radius:
				var px: int = (cx + dx) % TEXTURE_SIZE
				var py: int = (cy + dy) % TEXTURE_SIZE
				if px < 0: px += TEXTURE_SIZE
				if py < 0: py += TEXTURE_SIZE
				# Only brighten, don't darken existing cracks
				var existing: Color = img.get_pixel(px, py)
				if value > existing.r:
					img.set_pixel(px, py, Color(value, value, value))
