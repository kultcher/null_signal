// Overlay drawn on top of a device screen's UI: scanlines, edge vignette and a faint
// diagonal reflection, so Control UI reads as being behind old glass.
shader_type canvas_item;

uniform float scanline_strength = 0.10;
uniform float vignette_strength = 0.45;
uniform float reflection_strength = 0.035;
uniform vec3 reflection_tint : source_color = vec3(0.8, 1.0, 0.9);

void fragment() {
	float scan = (0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159)) * scanline_strength;

	vec2 c = UV - 0.5;
	float v = smoothstep(0.30, 0.78, length(c * vec2(0.9, 1.25))) * vignette_strength;

	float d = UV.x * 0.55 + UV.y * 0.45 - 0.16;
	float refl = smoothstep(0.0, 0.015, d) * (1.0 - smoothstep(0.015, 0.22, d)) * reflection_strength;

	float a = clamp(scan + v + refl, 0.0, 1.0);
	COLOR = vec4(reflection_tint * (refl / max(a, 0.0001)), a);
}
