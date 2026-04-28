// world_desaturate.gdshader
// Screen-space post-process shader.
// Apply to a full-screen ColorRect on a top CanvasLayer (layer = 10).
// Desaturates the full screen with a cool blue-grey tint.
// Characters (guardian, companion) are intentionally included — they carry
// their own colour via PointLight2D which punches through in the glow pass.
//
// To exclude characters entirely, put them on a SubViewport — deferred scope.

shader_type canvas_item;

uniform float desaturation : hint_range(0.0, 1.0) = 0.80;
uniform float brightness : hint_range(0.5, 1.5) = 1.05;
uniform vec4 tint : source_color = vec4(0.93, 0.95, 1.0, 1.0);

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec4 col = texture(screen_texture, SCREEN_UV);

	// Luminance desaturation
	float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	vec3 grey = vec3(lum);
	vec3 desaturated = mix(col.rgb, grey, desaturation);

	// Apply brightness and tint
	desaturated *= brightness;
	desaturated *= tint.rgb;

	COLOR = vec4(desaturated, col.a);
}
