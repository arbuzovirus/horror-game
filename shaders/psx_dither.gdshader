shader_type canvas_item;
// Goes on the PSXScreen: 15-bit colour with a 4x4 ordered dither, grain and a vignette,
// all on the low-resolution pixel grid.

uniform float levels = 31.0;
uniform float grain = 0.03;
uniform float vignette = 0.5;

float bayer(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	const float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
			3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return m[y * 4 + x] / 16.0 - 0.5;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
	vec3 c = texture(TEXTURE, UV).rgb;
	c += (hash(px + fract(TIME) * 100.0) - 0.5) * grain;
	c = floor(c * levels + 0.5 + bayer(px)) / levels;
	c *= 1.0 - vignette * smoothstep(0.25, 0.85, length(UV - 0.5) * 1.35);
	c *= vec3(0.97, 1.0, 0.94);
	COLOR = vec4(c, 1.0);
}
