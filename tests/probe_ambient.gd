extends SceneTree
## Diagnose Kartenleben: wie viele Orte je Art die AmbientView anlegt (ohne Grafik).
func _initialize() -> void:
	var t = load("res://tests/run_tests.gd").new()
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	s.setup(21, t.players(4))
	var cv := CityView.new()
	root.add_child(cv)
	cv.build(s)
	var counts := {}
	for sp in cv.ambient_view._spots:
		counts[sp.kind] = int(counts.get(sp.kind, 0)) + 1
	print("Orte je Art: ", counts)
	for sp in cv.ambient_view._spots:
		if sp.kind == "passanten":
			print("erster Passanten-Ort: Feld ", sp.world / 32.0, " Daten ", sp.data)
			break
	var houses: Array = s.city.buildings.filter(func(b): return str(b.type) in ["house", "semi", "villa"])
	print("Haeuser: ", houses.size(), " Typen gesamt: ", s.city.buildings.map(func(b): return str(b.type)).filter(func(t): return t.begins_with("h") or t == "semi").slice(0, 10))
	if not houses.is_empty():
		var b: Dictionary = houses[0]
		print("erstes Haus: ", b.type, " ", b.x, ",", b.y, " ", b.w, "x", b.h, " road ", b.get("road"), " lot ", b.get("lot", "-"))
	quit()
