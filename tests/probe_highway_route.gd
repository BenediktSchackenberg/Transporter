extends SceneTree
## Autobahntrasse als Bild (Region, Seed wie Tests): Trasse rot, Anschlussstellen gelb, Kreuzungen weiss, Strassen grau, Wasser blau,
## Berge braun, Gebaeude dunkel. Aufruf: Godot --headless --path . -s tests/probe_highway_route.gd [-- --seed=4242 --out=user://trasse.png]

func _init() -> void:
	var seed_v := 4242
	var out := "user://trasse.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_v = int(a.substr(7))
		if a.begins_with("--out="):
			out = a.substr(6)
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var pl: Array = []
	for i in 4:
		pl.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(seed_v, pl, Catalog.MAP_SIZE, 0.5)
	var t0 := Time.get_ticks_msec()
	var hp: Dictionary = s.regional.plan_highway()
	var ms := Time.get_ticks_msec() - t0
	var cd: CityData = s.city
	var img := Image.create(cd.size, cd.size, false, Image.FORMAT_RGB8)
	for y in cd.size:
		for x in cd.size:
			var i := cd.idx(Vector2i(x, y))
			var col := Color(0.35, 0.55, 0.3)
			if cd.ground[i] == CityData.G.WATER:
				col = Color(0.2, 0.4, 0.8)
			elif cd.height.size() > 0 and cd.height[i] > 0:
				col = Color(0.5, 0.4, 0.3)
			elif cd.building_at[i] >= 0:
				col = Color(0.15, 0.15, 0.15)
			elif cd.ground[i] == CityData.G.ROAD:
				col = Color(0.6, 0.6, 0.6)
			img.set_pixel(x, y, col)
	for c in hp.get("cells", []):
		img.set_pixel(int(c[0]), int(c[1]), Color(0.9, 0.1, 0.1))
	for c in hp.get("crossings", []):
		img.set_pixel(int(c[0]), int(c[1]), Color(1, 1, 1))
	for c in hp.get("junctions", []):
		img.set_pixel(int(c[0]), int(c[1]), Color(1, 0.9, 0))
	img.save_png(out)
	# Richtungswechsel entlang der Trasse zaehlen (Mass fuer Zickzack): Anteil der Felder, deren Nachbar in der Liste nicht geradeaus liegt
	var turns := 0
	var cells: Array = hp.get("cells", [])
	for i in range(2, cells.size()):
		var a := Vector2i(int(cells[i - 2][0]), int(cells[i - 2][1]))
		var b := Vector2i(int(cells[i - 1][0]), int(cells[i - 1][1]))
		var c := Vector2i(int(cells[i][0]), int(cells[i][1]))
		if (b - a).length_squared() == 1 and (c - b).length_squared() == 1 and (b - a) != (c - b):
			turns += 1
	print("Trasse ok=%s Felder %d Anschluesse %d Kreuzungen %d Abschnitte %s  Richtungswechsel %d  Planung %d ms -> %s" % [str(hp.get("ok")), cells.size(),
		hp.get("junctions", []).size(), hp.get("crossings", []).size(), str(hp.get("legs", []).map(func(l): return l.get("laenge", -1))), turns, ms,
		ProjectSettings.globalize_path(out)])
	quit()
