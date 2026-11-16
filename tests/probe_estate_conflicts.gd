extends SceneTree
## Stammsitze gegen Verkehrswege pruefen (Benedikt 16.11.2026: "Gebaeude nicht auf Strassen/Eisenbahnen, Mauern darf man nicht mit
## Auto oder Zug durchfahren, die Autobahn muss drumherum"). Zaehlt je Stammsitz Strassen-, Gleis-, Trassen- und Gebaeudefelder
## im Anwesen sowie Bloecke der Wesen auf Strasse/Gleis in der ganzen Welt.
## Aufruf: Godot --headless --path . -s tests/probe_estate_conflicts.gd [-- --file=user://saves/x.json]

func _init() -> void:
	var path := "user://saves/quicksave.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--file="):
			path = a.substr(7)
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	var s := Simulation.from_dict(d.sim)
	if s.rail != null:
		s.rail.ensure()
	s.regional.on_day(GameCalendar.day_of(s.game_min))   # offene Trassen: Umplanung um Stammsitze wie am naechsten Spieltag
	var C: CityData = s.city
	print("Spielzeit: %s, %d Stammsitze, %d Bloecke" % [Catalog.game_minutes_to_text(s.game_min), s.eko.estates.estates.size(), s.eko.blocks.size()])
	for name in s.eko.estates.estates:
		var r: Rect2i = s.eko.estates.rect_of(name)
		var cnt := {"strasse": 0, "gleis": 0, "trasse": 0, "gebaeude": 0}
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var q := Vector2i(x, y)
				if C.is_road(q): cnt.strasse += 1
				if C.g(q) == CityData.G.RAIL or (s.rail != null and s.rail.is_rail(q)): cnt.gleis += 1
				if s.access != null and s.access.reserved(q): cnt.trasse += 1
				if C.building_at[C.idx(q)] >= 0: cnt.gebaeude += 1
		var bauten: Array = (s.eko.estates.estates[name].bauten as Array).map(func(b): return "%s(%s)" % [b.art, b.status])
		print("%s %s: %s  Bauten: %s" % [name, r, cnt, ", ".join(bauten)])
	var on := {"strasse": 0, "gleis": 0}
	var tiles := {}
	for p in s.eko.blocks:
		var t := Vector2i(floori(float(p.x) / EkoWorld.PER_TILE), floori(float(p.y) / EkoWorld.PER_TILE))
		if tiles.has(t):
			continue
		tiles[t] = true
		if C.is_road(t): on.strasse += 1
		if C.g(t) == CityData.G.RAIL or (s.rail != null and s.rail.is_rail(t)): on.gleis += 1
	print("Felder mit Bloecken: %d, davon auf Strasse %d, auf Gleis %d" % [tiles.size(), on.strasse, on.gleis])
	quit()
