extends SceneTree
## Sichtpruefung Fahrzeugwerk (Auftrag 24): Region einige Tage laufen lassen (Personal, Entwuerfe), Band und Hof fuellen und den
## Querschnitt als Bild speichern. Aufruf (mit Fenster, nicht headless):
##   Godot --path . -s tests/probe_works_art.gd -- --out=user://werk.png [--zoom=1.0] [--t=3] [--hour=14]

var out := "user://werk.png"
var wait := 3.0
var clock := 0.0
var frames := 0
var node
var s: Simulation


func _initialize() -> void:
	var zoom := 1.0
	var hour := -1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--zoom="):
			zoom = float(a.substr(7))
		if a.begins_with("--t="):
			wait = float(a.substr(4))
		if a.begins_with("--hour="):
			hour = float(a.substr(7))
	s = Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(4242, ps, Catalog.MAP_SIZE, 0.5)
	while GameCalendar.day_of(s.game_min) < 8:
		s.step(0.1)
	var W: VehicleWorks = s.vworks
	var f := W.plant()
	var k := int(f.town)
	W.designs.clear()
	var specs := [{"klasse": "pkw", "name": "Lerche", "farbe": "rot", "form": "rund"}, {"klasse": "transporter", "name": "Kurier", "farbe": "gelb", "form": "kantig"},
		{"klasse": "lkw", "name": "Atlas", "farbe": "blau", "akzent": "weiss", "form": "keil"}, {"klasse": "sattelzug", "name": "Titan", "farbe": "gruen", "form": "kantig"},
		{"klasse": "pkw", "name": "Komet", "farbe": "silber", "form": "keil"}]
	W.supplier_open()
	for sp in specs:
		var r: Dictionary = W.design(k, sp, "Probe")
		print(r.msg)
	var ids: Array = W.designs.keys()
	for i in ids.size():
		W.designs[ids[i]].status = "serie" if i < 4 else "entwicklung"
	W.line.clear()
	var prog := [0.1, 0.33, 0.6, 0.92]
	for i in 4:
		var d: Dictionary = W.designs[ids[i]]
		W.line.append({"design": d.id, "serial": i, "need_h": float(d.hours), "done_h": float(d.hours) * prog[i], "unpaid": 0.0})
	W.hof.clear()
	for i in 6:
		W.hof.append({"design": ids[i % 4], "serial": 10 + i, "day": 8, "offer": "", "unpaid": 0.0})
	if hour >= 0.0:
		s.game_min = GameCalendar.day_start(8) + (fmod(hour - Catalog.START_HOUR + 24.0, 24.0)) / 24.0 * GameCalendar.day_game_min
	print("Personal: Monteure %d, Konstrukteure %d, Verkaeufer %d" % [s.municipal.staff_count(f.id, "monteur"), s.municipal.staff_count(f.id, "ingenieur"), s.municipal.staff_count(f.id, "autohaendler")])
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	var bg := ColorRect.new()
	bg.color = Color("5b8a3c")
	bg.size = Vector2(40000, 40000)
	bg.position = Vector2(-20000, -20000)
	var b: Dictionary = s.city.building(int(f.building))
	node = WorksView.PlantNode.new()
	node.sim = s
	node.fid = str(f.id)
	node.rect = Rect2i(int(b.x), int(b.y), int(b.w), int(b.h))
	node.origin = Vector2(node.rect.end) * 32.0
	node.position = Iso.to_screen(node.origin)
	bg.position += node.position
	root.add_child(bg)
	root.add_child(node)
	var cam := Camera2D.new()
	cam.zoom = Vector2(zoom, zoom)
	cam.position = Iso.to_screen((Vector2(node.rect.position) + Vector2(2.5, 2.0)) * 32.0) + Vector2(0, -90)
	root.add_child(cam)


func _process(delta: float) -> bool:
	clock += delta
	frames += 1
	if node != null:
		node.t += delta
		node.queue_redraw()
	if clock >= wait and frames > 10:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out)
		print("gespeichert: ", ProjectSettings.globalize_path(out))
		return true
	return false
