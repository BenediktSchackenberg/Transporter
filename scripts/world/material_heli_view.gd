class_name MaterialHeliView
extends Node2D
## Sichtbare Tandemrotor-Materialfluege. Position und Fracht stammen nur aus
## MaterialHeli, damit Speichern/Laden dieselbe Bewegung fortsetzt.

const SCALE := 0.92
const YELLOW := Color("f5c84d")
const WHITE := Color("f7f5df")
const SHADOW := Color(0.07, 0.12, 0.16, 0.35)

var sim: Simulation
var man: Dictionary
var textures := {}
var lights := {}
var clock := 0.0
var night := 0.0


func setup(s: Simulation, city_view: CityView) -> void:
	sim = s
	man = city_view.man
	z_index = 16
	y_sort_enabled = false
	for d in 4:
		textures[d] = load("res://assets/iso/heli_%d.png" % d)
		lights[d] = load("res://assets/iso/heli_%d_lit.png" % d)


func update_view(delta: float, darkness: float) -> void:
	clock += delta
	night = darkness
	queue_redraw()


func _draw() -> void:
	if sim == null or not sim.hub.enabled:
		return
	for c in sim.companies:
		if not sim.material_heli.helis.has(str(c.id)):
			continue
		var h: Dictionary = sim.material_heli.helis[str(c.id)]
		var st: Dictionary = sim.material_heli.flight_state(c.id)
		if st.is_empty():
			continue
		_pad(h, c.color, c.company_name)
		_cargo_scene(c.id, st)
		_aircraft(c.id, st, c.color)


func _ground(p: Vector2) -> Vector2:
	return Iso.to_screen(p * 32.0)


func _diamond(p: Vector2, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([p, p + Vector2(64, 32), p + Vector2(0, 64), p + Vector2(-64, 32)]), color)


func _pad(h: Dictionary, color: Color, name: String) -> void:
	var tile := Vector2i(int(h.pad[0]), int(h.pad[1]))
	for dy in 4:
		for dx in 4:
			var p := _ground(Vector2(tile + Vector2i(dx, dy)))
			_diamond(p, Color("41565c") if (dx + dy) % 2 == 0 else Color("465b62"))
	var center := _ground(Vector2(tile) + Vector2(2, 2))
	var poly := PackedVector2Array([center + Vector2(0, -126), center + Vector2(256, 2), center + Vector2(0, 130), center + Vector2(-256, 2)])
	for i in 4:
		draw_line(poly[i], poly[(i + 1) % 4], YELLOW, 5.0)
	for i in 14:
		var x := -205.0 + i * 30.0
		draw_line(center + Vector2(x, -54), center + Vector2(x + 13, -47), WHITE.darkened(0.18), 3.0)
	# Das gelbe H ist auch bei einem geparkten Hubschrauber noch erkennbar.
	for x in [-27.0, 27.0]:
		draw_line(center + Vector2(x, -24), center + Vector2(x, 32), WHITE, 9.0)
	draw_line(center + Vector2(-27, 4), center + Vector2(27, 4), WHITE, 9.0)
	for i in 4:
		var p: Vector2 = poly[i]
		var flash := 0.55 + 0.45 * sin(clock * 4.5 + float(i) * PI)
		draw_circle(p, 8.0, color.darkened(0.5))
		draw_circle(p, 4.0, Color(1.0, 0.75, 0.31, flash))
	var label := ThemeDB.fallback_font
	draw_string(label, center + Vector2(-105, 105), "%s  •  MATERIALFLUG" % name, HORIZONTAL_ALIGNMENT_LEFT, 220, 14, WHITE)


func _cargo_scene(cid: int, st: Dictionary) -> void:
	var phase := str(st.phase)
	if phase not in ["loading", "unloading"]:
		return
	var p := _ground(st.pos)
	var id := str(st.job)
	var job: Dictionary = sim.material_heli.jobs.get(id, {})
	var cargo := str(job.get("item", "WARE")).to_upper()
	var amount := int(job.get("qty", 0))
	var pulse := 0.5 + 0.5 * sin(clock * 2.4)
	for i in 3:
		var base := p + Vector2(-112 + i * 45, 46 + (i % 2) * 15)
		var step := 13.0 * sin(clock * 3.0 + float(i) * 1.8)
		_draw_worker(base + Vector2(step, 0), i)
		var box := base + Vector2(17 + step, -7)
		draw_rect(Rect2(box, Vector2(17, 14)), Color("a66f3d"))
		draw_line(box + Vector2(2, 4), box + Vector2(15, 4), Color("dfb179"), 2.0)
	var fg := Color("f7e5a8")
	draw_rect(Rect2(p + Vector2(-104, 84), Vector2(194, 21)), Color(0.08, 0.13, 0.16, 0.78))
	draw_string(ThemeDB.fallback_font, p + Vector2(-98, 100), "%s %d × %s" % ["BELADEN" if phase == "loading" else "ENTLADEN", amount, cargo], HORIZONTAL_ALIGNMENT_LEFT, 190, 13, fg)
	draw_circle(p + Vector2(102, 93), 4.0, Color(0.96, 0.72, 0.3, pulse))
	# Hebegeschirr und Palette folgen der Szene statt unsichtbar zu teleportieren.
	var lift := 5.0 * sin(clock * 2.0)
	draw_line(p + Vector2(45, -43), p + Vector2(45, 15 + lift), Color("6d7470"), 2.0)
	draw_rect(Rect2(p + Vector2(19, 15 + lift), Vector2(52, 21)), Color("6b5036"))
	for j in 3:
		draw_rect(Rect2(p + Vector2(22 + j * 16, 4 + lift), Vector2(14, 12)), Color("b6884e"))


func _draw_worker(base: Vector2, idx: int) -> void:
	var bob := sin(clock * 6.0 + idx) * 2.0
	draw_line(base + Vector2(0, -10 + bob), base + Vector2(-4, 5), Color("26383b"), 4.0)
	draw_line(base + Vector2(0, -10 + bob), base + Vector2(5, 5), Color("26383b"), 4.0)
	draw_rect(Rect2(base + Vector2(-6, -26 + bob), Vector2(12, 16)), Color("e7a331"))
	draw_line(base + Vector2(-6, -20 + bob), base + Vector2(6, -20 + bob), WHITE, 2.0)
	draw_circle(base + Vector2(0, -31 + bob), 5, Color("d5a477"))
	draw_rect(Rect2(base + Vector2(-6, -37 + bob), Vector2(12, 4)), YELLOW)


func _aircraft(cid: int, st: Dictionary, color: Color) -> void:
	var p := _ground(st.pos)
	var height := float(st.height) * 28.0
	var dir := 0
	if str(st.phase) in ["to_pickup", "outbound", "returning"]:
		var a: Vector2 = st.pad if str(st.phase) == "to_pickup" else st.from if str(st.phase) == "outbound" else st.to
		var b: Vector2 = st.from if str(st.phase) == "to_pickup" else st.to if str(st.phase) == "outbound" else st.pad
		var d: Vector2 = b - a
		dir = (0 if d.x >= 0.0 else 2) if absf(d.x) >= absf(d.y) else (1 if d.y >= 0.0 else 3)
	var entry: Dictionary = man.get("helicopter", {}).get(str(dir), {})
	if entry.is_empty():
		return
	var pivot := Vector2(float(entry.pivot[0]), float(entry.pivot[1])) * SCALE
	var size := Vector2(float(entry.size[0]), float(entry.size[1])) * SCALE
	var body := p - pivot + Vector2(0, -height)
	# Weicher, mit der Hoehe abnehmender Bodenschatten.
	var shadow_a := 0.36 * (1.0 - clampf(height / 340.0, 0.0, 0.6))
	draw_circle(p + Vector2(0, 17), 55 + height * 0.13, Color(0.07, 0.12, 0.16, shadow_a * 0.35))
	draw_circle(p + Vector2(0, 17), 34 + height * 0.09, Color(0.07, 0.12, 0.16, shadow_a))
	if height < 120.0 and str(st.phase) != "parked":
		for i in 7:
			var phase := clock * (1.7 + i * 0.11) + float(i) * TAU / 7.0
			var radius := 43.0 + 13.0 * sin(clock + i)
			var q := p + Vector2(cos(phase) * radius, sin(phase) * radius * 0.46 + 24)
			draw_circle(q, 3.0 + 2.0 * sin(phase), Color(0.83, 0.77, 0.58, 0.22))
	var tex: Texture2D = textures.get(dir)
	if tex != null:
		draw_texture_rect(tex, Rect2(body, size), false)
	if night > 0.0 and lights.get(dir) != null:
		draw_texture_rect(lights[dir], Rect2(body, size), false, Color(1, 1, 1, night))
	if night > 0.25:
		var blink := 0.45 + 0.55 * sin(clock * 7.0)
		draw_circle(p + Vector2(66, -height - 35), 3.0, Color(1, 0.22, 0.17, night * blink))
		draw_circle(p + Vector2(-62, -height - 35), 3.0, Color(0.25, 1, 0.55, night * blink))
	var rotor_speed := 11.0 if str(st.phase) == "parked" else 40.0
	for rotor in entry.rotors:
		var hub := p + Vector2(float(rotor[0]), float(rotor[1])) * SCALE + Vector2(0, -height)
		_rotor(hub, rotor_speed, color)
	if bool(st.cargo):
		var sling := p + Vector2(0, -height + 30)
		draw_line(sling, sling + Vector2(0, 26), Color("7e8a86"), 2.0)
		draw_rect(Rect2(sling + Vector2(-15, 26), Vector2(30, 16)), Color("aa7644"))
		draw_line(sling + Vector2(-15, 34), sling + Vector2(15, 34), YELLOW, 2.0)


func _rotor(hub: Vector2, speed: float, color: Color) -> void:
	var spin := clock * speed
	for k in 4:
		var angle := spin + float(k) * PI / 2.0
		var tip := hub + Vector2(cos(angle) * 54, sin(angle) * 19)
		draw_line(hub, tip, Color(0.13, 0.2, 0.22, 0.36), 10.0)
		draw_line(hub, tip, Color("96aaa7"), 3.0)
	draw_circle(hub, 5.5, color.lightened(0.18))
	if speed > 20.0:
		for k in 12:
			var a := float(k) * TAU / 12.0 + spin * 0.1
			var b := a + 0.25
			draw_line(hub + Vector2(cos(a) * 53, sin(a) * 19), hub + Vector2(cos(b) * 53, sin(b) * 19), Color(0.82, 0.9, 0.85, 0.21), 2.0)
