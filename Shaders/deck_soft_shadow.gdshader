// Soft drop shadow from a sprite's alpha. Used under DeviceShell art.
shader_type canvas_item;

uniform float strength = 0.6;
uniform float blur_px = 9.0;

void fragment() {
	vec2 step_uv = TEXTURE_PIXEL_SIZE * blur_px * 0.5;
	float a = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			a += texture(TEXTURE, UV + vec2(float(x), float(y)) * step_uv).a;
		}
	}
	a /= 25.0;
	COLOR = vec4(0.0, 0.0, 0.0, a * strength);
}
