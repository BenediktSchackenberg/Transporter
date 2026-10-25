shader_type canvas_item;
// Wind: Baumkronen und Fahnen schwingen, oben staerker als am Fuss. wind = 0 (still) .. 1 (Sturm).
uniform float wind = 0.0;
uniform float phase = 0.0;

void vertex() {
	float h = clamp(1.0 - UV.y, 0.0, 1.0);
	VERTEX.x += sin(TIME * (1.6 + wind * 3.0) + phase + VERTEX.y * 0.04) * (0.4 + wind * 5.0) * h * h;
}
