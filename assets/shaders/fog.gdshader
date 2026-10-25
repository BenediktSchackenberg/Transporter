shader_type canvas_item;
// Nebel ueber der Stadt: gleichmaessiger heller Schleier, am Bildrand dichter. Die Oberflaeche bleibt lesbar.
uniform float density = 0.0;

void fragment() {
	vec2 d = UV - vec2(0.5);
	float edge = smoothstep(0.15, 0.75, length(d));
	COLOR = vec4(0.80, 0.83, 0.87, density * (0.22 + 0.4 * edge));
}
