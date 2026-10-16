// glitch_mirage.gdshader
// Heat-haze over a Glitch decoy: re-draws what's behind it with a slow,
// wavy refraction and a soft edge, so the fake image shimmers like a mirage.
// Needs a BackBufferCopy just before it (signal_entity adds one).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength_px = 3.5;     // max refraction offset, in pixels
uniform float wave_freq = 0.09;      // waves per pixel
uniform float speed = 2.4;
uniform float shimmer = 0.10;        // brightness ripple
uniform float alpha = 0.95;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 frag = SCREEN_UV / px;
	float t = TIME * speed;
	// Two crossed slow waves, rising like heat.
	float wx = sin(frag.y * wave_freq + t) + 0.5 * sin(frag.y * wave_freq * 2.3 - t * 1.7);
	float wy = 0.4 * sin(frag.x * wave_freq * 0.8 + t * 1.3);
	vec2 offset = vec2(wx, wy) * strength_px * px;
	vec4 c = texture(screen_tex, SCREEN_UV + offset);
	c.rgb *= 1.0 + shimmer * sin(frag.y * wave_freq * 1.5 - t * 2.0);
	// Fade toward the rect edges so there's no visible box.
	vec2 d = abs(UV - 0.5) * 2.0;
	float edge = 1.0 - smoothstep(0.55, 1.0, max(d.x, d.y));
	COLOR = vec4(c.rgb, alpha * edge);
}
