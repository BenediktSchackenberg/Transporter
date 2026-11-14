extends SceneTree
## Prueft, ob irgendein Bauwerk (Gebaeude, Firmenhof, Steinwerk, freies Bauwerk, Stadtanlage) auf Strasse, Autobahn oder Gleis steht
## (auch auf geplanten Trassen laufender Projekte). Regel-Buergermeister wie im Spiel ohne Modell.
##   Godot_console.exe --headless --path . -s tests/probe_overlap.gd -- --seed=60034 --days=8

var s: Simulation


func _initialize() -> void:
	var days := 8
	var seed_v := 60034
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			days = int(str(a).trim_prefix("--days="))
		if str(a).begins_with("--seed="):
			seed_v = int(str(a).trim_prefix("--seed="))
	s = Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(seed_v, ps, Catalog.MAP_SIZE, 0.5)
	print("Start: %d Verstoesse" % check("Start"))
	var mayor_day := -1
	while GameCalendar.day_of(s.game_min) < days:
		var day := GameCalendar.day_of(s.game_min)
		if day != mayor_day:
			mayor_day = day
			for M in s.towns.mayors:
				for a in MayorBrain.decide(M.indicators()).actions:
					M.execute(a)
			print("Tag %d: %d Verstoesse" % [day, check("Tag %d" % day)])
		s.step(0.1)
	quit(0)


func _bad(q: Vector2i) -> String:
	var C: CityData = s.city
	if not C.inside(q):
		return ""
	var g := C.g(q)
	if g == CityData.G.ROAD:
		return "Autobahn" if s.regional.on_highway(q) else "Strasse"
	if g == CityData.G.RAIL or s.rail.is_rail(q):
		return "Gleis"
	if s.regional.on_highway(q):
		return "Autobahn"
	if _planned.has(q):
		return "geplante Trasse " + str(_planned[q])
	return ""


var _planned := {}


func check(when: String) -> int:
	_planned = {}
	for r in s.regional.items.values():
		if str(r.get("status", "")) in ["abgelehnt", "gescheitert", "fertig", "verworfen"]:
			continue
		for c in r.get("cells", []):
			_planned[Vector2i(int(c[0]), int(c[1])) if c is Array else Vector2i(c)] = str(r.get("kind", "?"))
	var rects: Array = []
	for b in s.city.buildings:
		if str(b.get("type", "")) in ["plot"]:
			continue
		rects.append(["Gebaeude %s (%s)" % [b.name, b.type], Rect2i(int(b.x), int(b.y), int(b.w), int(b.h))])
	for p in s.estate.plots.values():
		rects.append(["Firmenhof", Rect2i(int(p.x), int(p.y), int(p.w), int(p.h))])
	for w in s.stone.works.values():
		rects.append(["Steinwerk " + str(w.name), _r(w.rect)])
	for fb in s.freebuild.builds.values():
		rects.append(["Freies Bauwerk " + str(fb.name), _r(fb.rect)])
	for an in s.civic.anlagen.values():
		if str(an.status) not in ["abgelehnt", "verworfen"]:
			rects.append(["Stadtanlage %s (%s)" % [an.get("name", an.id), an.status], _r(an.rect)])
	var n := 0
	for e in rects:
		var r: Rect2i = e[1]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var why := _bad(Vector2i(x, y))
				if why != "":
					n += 1
					if n <= 25:
						print("  %s: %s auf %s bei %d,%d" % [when, e[0], why, x, y])
					break
			if n > 0 and false:
				break
	return n


func _r(a) -> Rect2i:
	return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
