shader_type canvas_item;
// Boden mit Wetter: nass (dunkler, leichter Glanz) und verschneit (aufgehellt). Werte 0..1 kommen aus CityView.
uniform float wet = 0.0;
uniform float snow = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	vec3 wet_col = c.rgb * vec3(0.72, 0.78, 0.88) + vec3(0.0, 0.015, 0.04) * (1.0 - lum);
	c.rgb = mix(c.rgb, wet_col, wet);
	c.rgb = mix(c.rgb, vec3(0.92, 0.95, 1.0) * (0.85 + 0.15 * lum), snow * 0.8);
	COLOR = c;
}
