// enemy_crack.gdshader
// Renders an enemy sprite with progressive white crack damage overlay.
// Attach as ShaderMaterial to enemy Sprite2D.
//
// Uniforms driven from GDScript (EnemyBase._update_crack_shader):
//   health_percent  -- 0.0 = dead, 1.0 = full HP
//   crack_texture   -- procedural crack map (CrackTextureGen autoload)
//   body_color      -- base body colour (set once on spawn)
//
// If TEXTURE is null/white (no sprite assigned yet), the shader falls back
// to rendering body_color as a solid square — placeholder-safe.

shader_type canvas_item;

uniform float health_percent : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D crack_texture : hint_default_white;
uniform vec4 body_color : source_color = vec4(0.7, 0.15, 0.85, 1.0);
uniform vec4 crack_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float crack_glow_intensity : hint_range(0.0, 3.0) = 1.5;
uniform float flicker_speed : hint_range(0.0, 20.0) = 8.0;

void fragment() {
	vec4 original = texture(TEXTURE, UV);

	// If the sprite texture is white/null (placeholder mode),
	// treat the whole quad as opaque body_color.
	// We detect "no real texture" by checking if it's perfectly white.
	bool is_placeholder = (original.r > 0.99 && original.g > 0.99 && original.b > 0.99);

	vec4 base_col;
	if (is_placeholder) {
		// Solid body colour, full opacity
		base_col = body_color;
	} else {
		// Real sprite texture — use as-is
		base_col = original;
		if (base_col.a < 0.01) {
			discard;
		}
	}

	// Sample crack texture
	vec4 cracks = texture(crack_texture, UV);

	// How much crack to show — increases as health drops
	float crack_threshold = 1.0 - health_percent;
	float crack_amount = smoothstep(crack_threshold - 0.15, crack_threshold + 0.25, cracks.r);

	// Near death: add flicker
	float flicker = 1.0;
	if (health_percent < 0.3) {
		flicker = 0.7 + 0.3 * sin(TIME * flicker_speed);
	}

	// Glow intensity through cracks increases as health drops
	float glow = (1.0 - health_percent) * crack_glow_intensity * crack_amount;

	// Blend original with crack colour
	vec4 cracked = mix(base_col, crack_color, crack_amount * flicker);

	// Add glow bloom on cracks
	cracked.rgb += crack_color.rgb * glow * flicker;

	// Apply overall flicker to alpha near death
	cracked.a = base_col.a * (is_placeholder ? 1.0 : flicker);

	COLOR = cracked;
}
