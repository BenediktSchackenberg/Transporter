shader_type canvas_item;
// Dezentes Hitzeflimmern: leichte vertikale Verzerrung des Bildes (nur bei Hitze am Tag).
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float amount = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	uv.x += sin(uv.y * 90.0 + TIME * 2.5) * 0.0009 * amount;
	uv.y += sin(uv.x * 60.0 + TIME * 1.7) * 0.0006 * amount;
	COLOR = vec4(texture(screen_tex, uv).rgb, amount > 0.01 ? 1.0 : 0.0);
}
