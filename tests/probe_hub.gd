extends SceneTree
## Grosslager (Auftrag 19): Lage, Gebaeude, Zufahrten und Strassen zu den Staedten fuer mehrere Seeds.
func _init() -> void:
	for seed in [99293, 21, 1675]:
		var ps: Array = []
		for i in 4:
			ps.append({"player_name": "S%d" % i, "company_name": "F%d" % i, "color": Catalog.COMPANY_COLORS[i], "avatar_style": i, "personality": "wachstum"})
		var s := Simulation.new()
		s.world_mode = "region"
		s.start_profile = "unternehmer"
		var t0 := Time.get_ticks_msec()
		s.setup(seed, ps, Catalog.MAP_SIZE, 0.5)
		var H: Dictionary = s.city.hub
		print("Seed %d (%d ms, Versuch %s): Lager %s, Gebaeude %s" % [seed, Time.get_ticks_msec() - t0, str(s.city.gen_params.get("versuch", "?")), str(H.get("rect")), str(H.get("buildings", {}).keys())])
		print("   Zufahrten %s | Strassen %s" % [str(H.get("exits")), str(H.get("links", []).map(func(l): return "%s:%s %d Felder" % [s.towns.name_of(int(l.stadt)), l.zufahrt, int(l.laenge)]))])
		var parcels_in := 0
		var R := Rect2i(int(H.rect[0]), int(H.rect[1]), int(H.rect[2]), int(H.rect[3]))
		for p in s.parcels.items.values():
			if p.state != "bebaut" and R.intersects(Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))):
				parcels_in += 1
		var dealer_offers: int = s.resources.available_offers().filter(func(o): return int(o.dealer) == int(H.buildings.get("fahrzeughandel", -1))).size()
		print("   freie Grundstuecke im Lager %d, Fahrzeugangebote im Lager %d" % [parcels_in, dealer_offers])
	quit()
