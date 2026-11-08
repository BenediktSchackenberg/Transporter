extends SceneTree
## Diagnose Seeverkehr: Liegeplaetze und Wasserwege zwischen den Haefen (Anteil der Wegpunkte auf Wasser).
## Godot_console.exe --headless --path . -s tests/probe_sea_route.gd -- [--seed=21]
func _initialize() -> void:
	var seed_v := 21
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--seed="):
			seed_v = int(str(a).trim_prefix("--seed="))
	var t = load("res://tests/run_tests.gd").new()
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	s.setup(seed_v, t.players(4))
	var v := ShipView.new()
	v.setup(s)
	print("Haefen: ", s.sea.ports, " Groesse ", s.city.size)
	for k in v._ports:
		var p: Dictionary = v._ports[k]
		print("Ort %d %s: berth %s (Wasser %s) berth2 %s (Wasser %s) edge %s west %s" % [k, s.towns.name_of(k), str(p.berth / 32.0), _water(s, p.berth), str(p.berth2 / 32.0), _water(s, p.berth2), str(p.edge / 32.0), p.west])
	for a in v._ports:
		for b in v._ports:
			if a == b:
				continue
			var r: PackedVector2Array = v._route(a, b)
			var wet := 0
			var samples := 0
			for i in r.size() - 1:
				for j in 10:
					var q := r[i].lerp(r[i + 1], j / 10.0)
					samples += 1
					if _water(s, q):
						wet += 1
			print("Route %d>%d: %d Punkte, %.0f %% auf Wasser, Laenge %.0f Felder" % [a, b, r.size(), 100.0 * wet / maxf(1, samples), _len(r) / 32.0])
	v.free()
	quit()


func _water(s: Simulation, p: Vector2) -> bool:
	var c := Vector2i(p / 32.0)
	return not s.city.inside(c) or s.city.g(c) == CityData.G.WATER


func _len(r: PackedVector2Array) -> float:
	var d := 0.0
	for i in r.size() - 1:
		d += r[i].distance_to(r[i + 1])
	return d
